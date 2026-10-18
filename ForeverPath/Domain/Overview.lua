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
        if plan and plan.isComplete and plan.obtain then
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
        elseif plan and tree and tree.summary then
          -- Bottom-up: the first intermediate whose own reagents are all on
          -- hand is the next thing to craft; otherwise obtain the biggest gap.
          local craftStep
          for _, c in ipairs(tree.summary.crafts) do
            if c.ready and (c.learned or c.combine or c.crafter) then craftStep = c break end
          end
          if craftStep then
            local who = craftStep.crafter and not craftStep.crafter.isCurrent and (" on " .. craftStep.crafter.name) or ""
            local verb = craftStep.combine and "Combine" or "Craft"
            step = {
              title = string.format("%s %d x %s%s", verb, craftStep.expectedOutput, nameOf(craftStep.itemID), who),
              detail = string.format("%s - for %s", craftStep.professionName or "Profession", goalName),
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
