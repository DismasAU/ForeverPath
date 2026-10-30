-- Dashboard aggregation: missing materials across active goals and the
-- recommended next steps. Pure Lua over Planner views.
local _, ns = ...
local Routes = ns.DependencyResolver.Routes

local Readiness = ns.Readiness
local GoalModel = ns.GoalModel

local Overview = {}
ns.Overview = Overview

-- Badge text for a missing leaf: how the player is expected to get it.
local function routeLabel(leaf)
  if leaf.step then return "Train" end
  if leaf.learn then return "Recipe" end
  if leaf.tool then return "Tool" end
  if leaf.route == Routes.CRAFT then
    return leaf.professionName and ("Craft - " .. leaf.professionName) or "Craft"
  end
  if leaf.noRoute then return "Soulbound" end
  if leaf.route == Routes.BUY then return "Buy" end
  if leaf.route == Routes.GATHER and leaf.gatherer then return "Gather - " .. leaf.gatherer end
  local labels = ns.DependencyResolver.RouteLabels
  return labels[leaf.route] or "Obtain"
end
Overview.RouteLabel = routeLabel

-- The next step for one goal. Each rule takes ctx = { goal, view, plan,
-- tree, goalName, nameOf, opts } and returns matched, step: the first rule
-- that matches decides (its step may be nil when there is nothing to do).
-- One rule per kind of view, in the order they are tried.
local NEXT_STEP_RULES = {}
local function rule(fn) NEXT_STEP_RULES[#NEXT_STEP_RULES + 1] = fn end

-- Enchant goals: done, blocked by the profession or skill, or ready to cast.
rule(function(c)
  local enchant, goalName = c.view and c.view.enchant, c.goalName
  if not enchant then return false end
  if enchant.remaining <= 0 then
    return true, { title = string.format("%s cast %d time%s", goalName, enchant.casts, enchant.casts == 1 and "" or "s"), detail = "Mark the goal complete", badge = "Ready", badgeKind = "ok" }
  elseif enchant.blocked == "profession" then
    return true, { title = string.format("Learn %s", enchant.recipe.professionName or "the profession"), detail = string.format("Needed before %s can be cast", goalName), badge = "Profession", badgeKind = "partial" }
  elseif enchant.blocked == "skill" then
    return true, { title = string.format("Reach %s %d", enchant.recipe.professionName or "skill", enchant.need), detail = string.format("You have %d - needed for %s", enchant.have or 0, goalName), badge = "Skill", badgeKind = "partial" }
  elseif c.plan and c.plan.isComplete then
    return true, {
      title = string.format("Cast %d x %s", enchant.remaining, goalName),
      detail = "All materials are in your bags" .. (enchant.casts > 0 and string.format(" - %d of %d done", enchant.casts, enchant.quantity) or ""),
      badge = "Ready", badgeKind = "ok",
    }
  end
  return false
end)

-- Reputation goals: the standing so far, or ready.
rule(function(c)
  local reputation = c.view and c.view.reputation
  if not reputation then return false end
  local p = reputation.progress
  return true, {
    title = c.view.nextStep or c.goalName,
    detail = p.reached and "Mark the goal complete" or string.format("%s now - %d to go - for %s", reputation.record.standingLabel, p.remaining, c.goalName),
    badge = p.reached and "Ready" or reputation.record.standingLabel, badgeKind = p.reached and "ok" or "info",
  }
end)

-- Quest goals: where the quest stands, inside its chain when it has one.
rule(function(c)
  local quest = c.view and c.view.quest
  if not quest then return false end
  local label, kind = quest.label, "info"
  if quest.state.completed then kind = "ok" elseif quest.state.ready then kind = "ok" elseif label == "Locked" then kind = "partial" end
  local where = quest.line and not quest.state.completed
    and string.format("%s - step %d of %d - ", quest.line.attune.name, math.min(quest.line.done + 1, quest.line.total), quest.line.total)
    or (quest.entry and quest.entry.instance and (quest.entry.instance .. " - ") or "")
  return true, {
    title = c.view.nextStep or c.goalName,
    detail = where .. (quest.state.completed and "Mark the goal complete" or ("For " .. c.goalName)),
    badge = quest.state.completed and "Ready" or label, badgeKind = kind,
  }
end)

-- Learn-recipe goals: learned, nothing to learn, blocked, or plans in the bags.
rule(function(c)
  local learn, goalName = c.view and c.view.learn, c.goalName
  if not learn then return false end
  if learn.learned then
    return true, { title = string.format("Learned: %s", goalName), detail = "Mark the goal complete", badge = "Ready", badgeKind = "ok" }
  elseif learn.kind == "combine" then
    return true, { title = string.format("%s needs no recipe", goalName), detail = "Combine the items whenever you have them", badge = "Combine", badgeKind = "ok" }
  elseif learn.blocked == "profession" then
    return true, { title = string.format("Learn %s", learn.recipe.professionName or "the profession"), detail = string.format("Needed before %s can be learned", goalName), badge = "Profession", badgeKind = "partial" }
  elseif learn.blocked == "skill" then
    return true, { title = string.format("Reach %s %d", learn.recipe.professionName or "skill", learn.need), detail = string.format("You have %d - needed for %s", learn.have or 0, goalName), badge = "Skill", badgeKind = "partial" }
  elseif c.plan and c.plan.isComplete and learn.kind == "plans" then
    return true, { title = string.format("Read %s", c.nameOf(learn.teachItemID)), detail = string.format("Teaches %s - it is in your bags", goalName), badge = "Recipe", badgeKind = "ok" }
  end
  return false
end)

-- Reach-skill goals: reached, not scanned, nothing to craft, or the first craft ready.
rule(function(c)
  local skill, view, goalName = c.view and c.view.skill, c.view, c.goalName
  if not skill then return false end
  if skill.reached then
    return true, { title = string.format("%s reached", goalName), detail = "Mark the goal complete", badge = "Ready", badgeKind = "ok" }
  elseif not skill.scanned then
    return true, { title = string.format("Open your %s window", skill.professionName), detail = string.format("ForeverPath needs your recipe list to plan %s", goalName), badge = "Scan", badgeKind = "partial" }
  elseif view.skillPlan and #view.skillPlan.list == 0 then
    return true, { title = string.format("Find a recipe for %s %d+", skill.professionName, skill.current), detail = string.format("Nothing you know gives points - visit a trainer or find a pattern"), badge = "Recipe", badgeKind = "partial" }
  elseif c.plan and c.plan.isComplete and c.tree and c.tree.summary and c.tree.summary.crafts[1] then
    -- Every reagent of the skill plan is in the bags: name its first craft.
    local craft = c.tree.summary.crafts[1]
    return true, {
      title = string.format("%s %d x %s", craft.enchant and "Cast" or (craft.combine and "Combine" or "Craft"), craft.crafts, craft.itemID and c.nameOf(craft.itemID) or (craft.name or "?")),
      detail = string.format("%s (skill %d-%d) - all materials are in your bags - for %s", craft.professionName or "Profession",
        craft.forSkill and craft.forSkill.from or 0, craft.forSkill and craft.forSkill.to or 0, goalName),
      badge = "Ready", badgeKind = "ok",
    }
  end
  return false
end)

-- Item goals with everything on hand.
rule(function(c)
  local plan = c.plan
  if not (plan and plan.isComplete) then return false end
  if plan.obtain then
    return true, { title = string.format("%d x %s on hand", plan.quantityWanted or 0, c.goalName), detail = "Mark the goal complete", badge = "Ready", badgeKind = "ok" }
  end
  return true, { title = string.format("Craft %d x %s", plan.craftsNeeded, c.goalName), detail = "All materials are in your bags", badge = "Ready", badgeKind = "ok" }
end)

-- A quest reward: the next step of the chain that leads to it.
rule(function(c)
  local view = c.view
  if not (view and view.questline and view.nextStep) then return false end
  local q, line = view.questline.quest, view.questline.line
  return true, {
    title = view.nextStep,
    detail = (line and string.format("%s - step %d of %d - ", line.attune.name, math.min(line.done + 1, line.total), line.total) or ((q.instance or "Quest") .. " - "))
      .. string.format("rewards %s", c.goalName),
    badge = "Quest", badgeKind = "info",
  }
end)

-- A dependency tree: bottom-up, the first intermediate whose own reagents
-- are all on hand is the next craft; otherwise obtain the biggest gap.
rule(function(c)
  local tree, nameOf, goalName = c.tree, c.nameOf, c.goalName
  if not (c.plan and tree and tree.summary) then return false end
  for _, craft in ipairs(tree.summary.crafts) do
    if craft.ready and (craft.learned or craft.combine or craft.crafter) then
      local who = craft.crafter and not craft.crafter.isCurrent and (" on " .. craft.crafter.name) or ""
      local verb = craft.combine and "Combine" or (craft.enchant and "Cast" or "Craft")
      local range = craft.forSkill and string.format(" (skill %d-%d)", craft.forSkill.from or 0, craft.forSkill.to or 0) or ""
      return true, {
        title = string.format("%s %d x %s%s", verb, craft.forSkill and craft.crafts or craft.expectedOutput, craft.itemID and nameOf(craft.itemID) or (craft.name or "?"), who),
        detail = string.format("%s%s - for %s", craft.professionName or "Profession", range, goalName),
        badge = craft.combine and "Combine" or (craft.professionName and ("Craft - " .. craft.professionName) or "Craft"), badgeKind = "ok",
      }
    end
  end
  local top = tree.summary.missingLeaves[1]
  if not top then return true, nil end
  local label = routeLabel(top)
  local title
  if top.step then
    local trainer = top.step.trainer
    title = string.format("Train %s", top.step.name or "the recipe")
    top = { count = top.count, itemID = nil, step = top.step,
      hint = trainer and trainer.name and (trainer.name .. (trainer.zone and (", " .. trainer.zone) or "")) or ((top.step.professionName or "profession") .. " trainer") }
  elseif top.learn then
    title = string.format("Get %s", nameOf(top.itemID))
  elseif top.route == Routes.ALT and top.altName then
    title = string.format("Get %d x %s from %s", top.count, nameOf(top.itemID), top.altName)
  elseif top.route == Routes.ALTCRAFT and top.altName then
    title = string.format("Have %s craft %d x %s", top.altName, top.count, nameOf(top.itemID))
  else
    title = string.format("Obtain %d x %s", top.count, nameOf(top.itemID))
  end
  local hint = top.hint
  if top.learn and top.learnFor then hint = "Teaches " .. top.learnFor .. (hint and (" - " .. hint) or "") end
  if top.farm then hint = top.farm.text .. (hint and (" - " .. hint) or "") end
  return true, {
    title = title,
    detail = (hint and (hint .. " - ") or "") .. string.format("For %s - %d of %d dependencies resolved", goalName, tree.summary.resolved, tree.summary.nodes),
    badge = label, badgeKind = (label == "Recipe" or label == "Soulbound") and "partial" or "info",
  }
end)

-- A flat requirements plan (no tree): the material most missing.
rule(function(c)
  local plan = c.plan
  if not plan then return false end
  local top
  for _, material in ipairs(plan.materials) do
    if material.missing > 0 and (not top or material.missing > top.missing) then top = material end
  end
  if not top then return true, nil end
  local craftable = c.opts.craftableBy and c.opts.craftableBy(top.itemID) or nil
  return true, {
    title = string.format("Obtain %d x %s", top.missing, c.nameOf(top.itemID)),
    detail = string.format("For %s - %d of %d materials still missing", c.goalName, plan.totals.materialsMissing, #plan.materials),
    badge = craftable and ("Craft - " .. craftable) or nil, badgeKind = "ok",
  }
end)

-- Attunement goals: attuned, or the next step.
rule(function(c)
  local a = c.view and c.view.attunement
  if not a then return false end
  if a.complete then
    return true, { title = string.format("Attuned: %s", c.goalName), detail = "Mark the goal complete", badge = "Ready", badgeKind = "ok" }
  elseif a.next then
    return true, {
      title = string.format("%s: %s", a.next.typeLabel, a.next.name),
      detail = (a.next.location and (a.next.location .. " - ") or "") .. string.format("step %d of %d for %s", a.done + 1, a.total, c.goalName),
      badge = a.next.typeLabel, badgeKind = a.next.inLog and "ok" or "info",
    }
  end
  return true, nil
end)

-- Goals the Planner could not plan: what would unblock them.
rule(function(c)
  local view, goalName = c.view, c.goalName
  if not view then return false end
  if view.readiness == Readiness.RECIPES_NOT_SCANNED then
    return true, { title = "Open your profession windows", detail = "ForeverPath records recipes while a window is open", badge = "Scan", badgeKind = "partial" }
  elseif view.readiness == Readiness.RECIPE_NOT_LEARNED and view.recipe then
    return true, { title = string.format("Learn %s", view.recipe.name or "the recipe"), detail = string.format("%s - needed for %s", view.recipe.professionName or "Profession", goalName), badge = "Recipe", badgeKind = "partial" }
  elseif view.readiness == Readiness.RECIPE_NOT_FOUND then
    return true, { title = string.format("Find a recipe for %s", goalName), detail = "No recorded profession makes this item", badge = "Unknown", badgeKind = "missing" }
  end
  return false
end)

local function nextStep(ctx)
  for _, fn in ipairs(NEXT_STEP_RULES) do
    local matched, step = fn(ctx)
    if matched then return step end
  end
  return nil
end

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
        local step = nextStep({ goal = goal, view = view, plan = plan, tree = tree, goalName = goalName, nameOf = nameOf, opts = opts })
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
