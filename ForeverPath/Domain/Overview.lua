-- Dashboard aggregation: missing materials across active goals and the
-- recommended next steps. Pure Lua over Planner views.
local _, ns = ...

local Status = ns.Status
local GoalModel = ns.GoalModel

local Overview = {}
ns.Overview = Overview

-- Badge text for a missing leaf: how the player is expected to get it.
local function routeLabel(leaf)
  if leaf.step then return "Train" end
  if leaf.learn then return "Recipe" end
  if leaf.tool then return "Tool" end
  if leaf.route == "craft" then
    return leaf.professionName and ("Craft - " .. leaf.professionName) or "Craft"
  end
  if leaf.noRoute then return "Soulbound" end
  if leaf.route == "buy" then return "Buy" end
  if leaf.route == "gather" and leaf.gatherer then return "Gather - " .. leaf.gatherer end
  local labels = ns.DependencyResolver and ns.DependencyResolver.RouteLabels or {}
  return labels[leaf.route] or "Obtain"
end
Overview.RouteLabel = routeLabel

-- entries: { { goal = goal, view = view }, ... } in priority order.
-- opts.nameOf(itemID) -> display name; opts.craftableBy(itemID) -> profession name or nil
function Overview.Build(entries, opts)
  opts = opts or {}
  local nameOf = opts.nameOf or function(itemID) return "Item " .. tostring(itemID) end
  local result = {
    missing = {},     -- { itemID, count, goals = { names }, craftableBy }
    nextSteps = {},   -- { title, detail, badge, badgeKind, goalID }
    activeCount = 0,
    completedCount = opts.completedCount or 0,
  }
  local byItem = {}

  for _, entry in ipairs(entries) do
    local goal, view = entry.goal, entry.view
    if goal.status == GoalModel.Statuses.ACTIVE then
      result.activeCount = result.activeCount + 1
      local goalName = GoalModel.Name(goal, nameOf)
      local plan = view and view.plan
      local tree = view and view.tree
      -- With a dependency tree the things to obtain are its missing leaves
      -- (raw materials); intermediates you will craft yourself are not listed.
      local function addMissing(itemID, count)
        local item = byItem[itemID]
        if not item then
          item = { itemID = itemID, count = 0, goals = {}, craftableBy = opts.craftableBy and opts.craftableBy(itemID) or nil }
          byItem[itemID] = item
          result.missing[#result.missing + 1] = item
        end
        item.count = item.count + count
        item.goals[#item.goals + 1] = goalName
      end
      if tree and tree.summary then
        for _, leaf in ipairs(tree.summary.missingLeaves) do
          if leaf.itemID then addMissing(leaf.itemID, leaf.count) end
        end
      elseif plan then
        for _, material in ipairs(plan.materials) do
          if material.missing > 0 then
            addMissing(material.itemID, material.missing)
          end
        end
      end

      if #result.nextSteps < (opts.maxSteps or 3) then
        local step
        local learn, skill, quest, reputation = view and view.learn, view and view.skill, view and view.quest, view and view.reputation
        local enchant = view and view.enchant
        if enchant and enchant.remaining <= 0 then
          step = { title = string.format("%s cast %d time%s", goalName, enchant.casts, enchant.casts == 1 and "" or "s"), detail = "Mark the goal complete", badge = "Ready", badgeKind = "ok" }
        elseif enchant and enchant.blocked == "profession" then
          step = { title = string.format("Learn %s", enchant.recipe.professionName or "the profession"), detail = string.format("Needed before %s can be cast", goalName), badge = "Profession", badgeKind = "partial" }
        elseif enchant and enchant.blocked == "skill" then
          step = { title = string.format("Reach %s %d", enchant.recipe.professionName or "skill", enchant.need), detail = string.format("You have %d - needed for %s", enchant.have or 0, goalName), badge = "Skill", badgeKind = "partial" }
        elseif enchant and plan and plan.isComplete then
          step = {
            title = string.format("Cast %d x %s", enchant.remaining, goalName),
            detail = "All materials are in your bags" .. (enchant.casts > 0 and string.format(" - %d of %d done", enchant.casts, enchant.quantity) or ""),
            badge = "Ready", badgeKind = "ok",
          }
        elseif reputation then
          local p = reputation.progress
          step = {
            title = view.nextStep or goalName,
            detail = p.reached and "Mark the goal complete" or string.format("%s now - %d to go - for %s", reputation.record.standingLabel, p.remaining, goalName),
            badge = p.reached and "Ready" or reputation.record.standingLabel, badgeKind = p.reached and "ok" or "info",
          }
        elseif quest then
          local label, kind = quest.label, "info"
          if quest.state.completed then kind = "ok" elseif quest.state.ready then kind = "ok" elseif label == "Locked" then kind = "partial" end
          local where = quest.line and not quest.state.completed
            and string.format("%s - step %d of %d - ", quest.line.attune.name, math.min(quest.line.done + 1, quest.line.total), quest.line.total)
            or (quest.entry and quest.entry.instance and (quest.entry.instance .. " - ") or "")
          step = {
            title = view.nextStep or goalName,
            detail = where .. (quest.state.completed and "Mark the goal complete" or ("For " .. goalName)),
            badge = quest.state.completed and "Ready" or label, badgeKind = kind,
          }
        elseif learn and learn.learned then
          step = { title = string.format("Learned: %s", goalName), detail = "Mark the goal complete", badge = "Ready", badgeKind = "ok" }
        elseif learn and learn.kind == "combine" then
          step = { title = string.format("%s needs no recipe", goalName), detail = "Combine the items whenever you have them", badge = "Combine", badgeKind = "ok" }
        elseif learn and learn.blocked == "profession" then
          step = { title = string.format("Learn %s", learn.recipe.professionName or "the profession"), detail = string.format("Needed before %s can be learned", goalName), badge = "Profession", badgeKind = "partial" }
        elseif learn and learn.blocked == "skill" then
          step = { title = string.format("Reach %s %d", learn.recipe.professionName or "skill", learn.need), detail = string.format("You have %d - needed for %s", learn.have or 0, goalName), badge = "Skill", badgeKind = "partial" }
        elseif learn and plan and plan.isComplete and learn.kind == "plans" then
          step = { title = string.format("Read %s", nameOf(learn.teachItemID)), detail = string.format("Teaches %s - it is in your bags", goalName), badge = "Recipe", badgeKind = "ok" }
        elseif skill and skill.reached then
          step = { title = string.format("%s reached", goalName), detail = "Mark the goal complete", badge = "Ready", badgeKind = "ok" }
        elseif skill and not skill.scanned then
          step = { title = string.format("Open your %s window", skill.professionName), detail = string.format("ForeverPath needs your recipe list to plan %s", goalName), badge = "Scan", badgeKind = "partial" }
        elseif skill and view.skillPlan and #view.skillPlan.list == 0 then
          step = { title = string.format("Find a recipe for %s %d+", skill.professionName, skill.current), detail = string.format("Nothing you know gives points - visit a trainer or find a pattern"), badge = "Recipe", badgeKind = "partial" }
        elseif skill and plan and plan.isComplete and tree and tree.summary and tree.summary.crafts[1] then
          -- Every reagent of the skill plan is in the bags: name its first craft.
          local c = tree.summary.crafts[1]
          step = {
            title = string.format("%s %d x %s", c.enchant and "Cast" or (c.combine and "Combine" or "Craft"), c.crafts, c.itemID and nameOf(c.itemID) or (c.name or "?")),
            detail = string.format("%s (skill %d-%d) - all materials are in your bags - for %s", c.professionName or "Profession",
              c.forSkill and c.forSkill.from or 0, c.forSkill and c.forSkill.to or 0, goalName),
            badge = "Ready", badgeKind = "ok",
          }
        elseif plan and plan.isComplete and plan.obtain then
          step = {
            title = string.format("%d x %s on hand", plan.quantityWanted or 0, goalName),
            detail = "Mark the goal complete",
            badge = "Ready", badgeKind = "ok",
          }
        elseif plan and plan.isComplete then
          step = {
            title = string.format("Craft %d x %s", plan.craftsNeeded, goalName),
            detail = "All materials are in your bags",
            badge = "Ready", badgeKind = "ok",
          }
        elseif view and view.questline and view.nextStep then
          -- A quest reward: the next step of the chain that leads to it.
          local q, line = view.questline.quest, view.questline.line
          step = {
            title = view.nextStep,
            detail = (line and string.format("%s - step %d of %d - ", line.attune.name, math.min(line.done + 1, line.total), line.total) or ((q.instance or "Quest") .. " - "))
              .. string.format("rewards %s", goalName),
            badge = "Quest", badgeKind = "info",
          }
        elseif plan and tree and tree.summary then
          -- Bottom-up: the first intermediate whose own reagents are all on
          -- hand is the next thing to craft; otherwise obtain the biggest gap.
          local craftStep
          for _, c in ipairs(tree.summary.crafts) do
            if c.ready and (c.learned or c.combine or c.crafter) then craftStep = c break end
          end
          if craftStep then
            local who = craftStep.crafter and not craftStep.crafter.isCurrent and (" on " .. craftStep.crafter.name) or ""
            local verb = craftStep.combine and "Combine" or (craftStep.enchant and "Cast" or "Craft")
            local range = craftStep.forSkill and string.format(" (skill %d-%d)", craftStep.forSkill.from or 0, craftStep.forSkill.to or 0) or ""
            step = {
              title = string.format("%s %d x %s%s", verb, craftStep.forSkill and craftStep.crafts or craftStep.expectedOutput, craftStep.itemID and nameOf(craftStep.itemID) or (craftStep.name or "?"), who),
              detail = string.format("%s%s - for %s", craftStep.professionName or "Profession", range, goalName),
              badge = craftStep.combine and "Combine" or (craftStep.professionName and ("Craft - " .. craftStep.professionName) or "Craft"), badgeKind = "ok",
            }
          else
            local top = tree.summary.missingLeaves[1]
            if top then
              local label = routeLabel(top)
              local title
              if top.step then
                local trainer = top.step.trainer
                title = string.format("Train %s", top.step.name or "the recipe")
                top = { count = top.count, itemID = nil, step = top.step,
                  hint = trainer and trainer.name and (trainer.name .. (trainer.zone and (", " .. trainer.zone) or "")) or ((top.step.professionName or "profession") .. " trainer") }
              elseif top.learn then
                title = string.format("Get %s", nameOf(top.itemID))
              elseif top.route == "alt" and top.altName then
                title = string.format("Get %d x %s from %s", top.count, nameOf(top.itemID), top.altName)
              elseif top.route == "altcraft" and top.altName then
                title = string.format("Have %s craft %d x %s", top.altName, top.count, nameOf(top.itemID))
              else
                title = string.format("Obtain %d x %s", top.count, nameOf(top.itemID))
              end
              local hint = top.hint
              if top.learn and top.learnFor then hint = "Teaches " .. top.learnFor .. (hint and (" - " .. hint) or "") end
              if top.farm then hint = top.farm.text .. (hint and (" - " .. hint) or "") end
              step = {
                title = title,
                detail = (hint and (hint .. " - ") or "") .. string.format("For %s - %d of %d dependencies resolved", goalName, tree.summary.resolved, tree.summary.nodes),
                badge = label, badgeKind = (label == "Recipe" or label == "Soulbound") and "partial" or "info",
              }
            end
          end
        elseif plan then
          local top
          for _, material in ipairs(plan.materials) do
            if material.missing > 0 and (not top or material.missing > top.missing) then
              top = material
            end
          end
          if top then
            local craftable = opts.craftableBy and opts.craftableBy(top.itemID) or nil
            step = {
              title = string.format("Obtain %d x %s", top.missing, nameOf(top.itemID)),
              detail = string.format("For %s - %d of %d materials still missing", goalName, plan.totals.materialsMissing, #plan.materials),
              badge = craftable and ("Craft - " .. craftable) or nil, badgeKind = "ok",
            }
          end
        elseif view and view.attunement then
          local a = view.attunement
          if a.complete then
            step = { title = string.format("Attuned: %s", goalName), detail = "Mark the goal complete", badge = "Ready", badgeKind = "ok" }
          elseif a.next then
            step = {
              title = string.format("%s: %s", a.next.typeLabel, a.next.name),
              detail = (a.next.location and (a.next.location .. " - ") or "") .. string.format("step %d of %d for %s", a.done + 1, a.total, goalName),
              badge = a.next.typeLabel, badgeKind = a.next.inLog and "ok" or "info",
            }
          end
        elseif view and view.status == Status.RECIPES_NOT_SCANNED then
          step = { title = "Open your profession windows", detail = "ForeverPath records recipes while a window is open", badge = "Scan", badgeKind = "partial" }
        elseif view and view.status == Status.RECIPE_NOT_LEARNED and view.recipe then
          step = { title = string.format("Learn %s", view.recipe.name or "the recipe"), detail = string.format("%s - needed for %s", view.recipe.professionName or "Profession", goalName), badge = "Recipe", badgeKind = "partial" }
        elseif view and view.status == Status.RECIPE_NOT_FOUND then
          step = { title = string.format("Find a recipe for %s", goalName), detail = "No recorded profession makes this item", badge = "Unknown", badgeKind = "missing" }
        end
        if step then
          step.goalID = goal.id
          result.nextSteps[#result.nextSteps + 1] = step
        end
      end
    end
  end

  table.sort(result.missing, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.itemID < b.itemID
  end)
  return result
end

-- Percent complete (0..100) for a view, or nil when no plan exists.
function Overview.Percent(view)
  if view and view.attunement then return view.attunement.percent end
  if view and view.skill then return view.skill.percent end
  if view and (view.quest or view.reputation or view.enchant) then return view.progress and view.progress.percent or 0 end
  local plan = view and view.plan
  if not plan then return nil end
  if plan.totals.required <= 0 then return 100 end
  return math.floor(plan.totals.owned * 100 / plan.totals.required + 0.5)
end

-- "Missing: 12 Thorium Bar, 3 Essence of Fire, +2 more"
function Overview.MissingSummary(view, nameOf, limit)
  local plan = view and view.plan
  if not plan then return nil end
  if plan.isComplete then return "All materials on hand" end
  limit = limit or 3
  local parts, extra = {}, 0
  for _, material in ipairs(plan.materials) do
    if material.missing > 0 then
      if #parts < limit then
        parts[#parts + 1] = string.format("%d %s", material.missing, nameOf(material.itemID))
      else
        extra = extra + 1
      end
    end
  end
  local text = "Missing: " .. table.concat(parts, ", ")
  if extra > 0 then
    text = text .. string.format(", +%d more", extra)
  end
  return text
end
