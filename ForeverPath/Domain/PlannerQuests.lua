-- Planner part: attunement, quest and reputation goals, and the quest text
-- and questlines item goals use. Extends ns.Planner (Domain/Planner.lua).
local _, ns = ...

local Readiness = ns.Readiness
local DependencyResolver = ns.DependencyResolver
local Steps = DependencyResolver.Steps
local Planner = ns.Planner

-- Where a quest stands for the player (QuestProvider.StateKey); the display
-- text comes from QuestProvider.StateText, so planning never branches on it.
Planner.QuestStates = ns.Util.StrictNames({ "done", "ready", "in_log", "available", "locked" }, "quest state")
local QuestStates = Planner.QuestStates
local Shared = Planner.Shared
local inventoryContext = Shared.inventoryContext

-- Attunement goals: progress through the Attune bridge. The view carries
-- `attunement` (AttuneBridge.Progress), a synthetic `item` for icons and
-- names, `progress.percent`, and the next step as the message.
function Planner.EvaluateAttunement(view, goal, deps)
  local attune = deps.attune
  view.item = { name = goal.target.name, icon = goal.target.icon, quality = 1, loaded = true, exists = true }
  if not attune or not attune.IsAvailable() then
    view.readiness = Readiness.PROVIDER_UNAVAILABLE
    view.message = "Attunement chains come from the Attune addon. Install and enable Attune to plan this goal."
    return view
  end
  local progress = attune.Progress(goal.target.attuneID)
  if not progress then
    view.readiness = Readiness.ITEM_INVALID
    view.message = string.format("Attune has no attunement with id %s.", tostring(goal.target.attuneID))
    return view
  end
  view.attunement = progress
  view.item.name = progress.attune.name
  view.item.icon = progress.attune.icon or view.item.icon
  view.progress = { percent = progress.percent, stepsDone = progress.done, stepsTotal = progress.total }
  if progress.complete then
    view.message = string.format("Attuned: every step of %s is done.", progress.attune.name)
  elseif progress.next then
    view.message = string.format("%d of %d steps done. Next: %s", progress.done, progress.total, attune.StepText(progress.next))
  else
    view.message = string.format("%d of %d steps done.", progress.done, progress.total)
  end
  return view
end

---------------------------------------------------------------------------
-- Questlines (quest goals and quest-reward items)
---------------------------------------------------------------------------
local QUEST_STEP = { Quest = true, ["Pick Up"] = true, ["Turn In"] = true }

-- "Pick up Elemental Aid from Prate Cloudseer in Thousand Needles" for a
-- questline step (or a bare quest: { questID, name }).
function Planner.QuestStepText(quest, step)
  local stepType = step.type or "Quest"
  if stepType == "Level" then return "Reach level " .. tostring(step.wowheadID or step.name) end
  if stepType == "Item" then
    return string.format("Collect %d x %s", step.count or 1, step.name or "item") .. (step.location and (" - " .. step.location) or "")
  end
  if not QUEST_STEP[stepType] then return (step.typeLabel or stepType) .. ": " .. tostring(step.name) end
  local questID = step.questID
  local state = step.questState or (questID and quest.State(questID)) or {}
  local name = step.name or (questID and quest.Name(questID)) or "the quest"
  local entry = step.entry or (questID and quest.Get and quest.Get(questID)) or nil
  local fallbackZone = step.location or (entry and entry.location) or nil
  if state.ready or (stepType == "Turn In" and state.inLog) then
    local turnin = questID and quest.Turnin and quest.Turnin(questID) or nil
    local zone = (turnin and turnin.zone) or fallbackZone
    return "Turn in " .. name .. (turnin and turnin.name and (" to " .. turnin.name) or "") .. (zone and (" in " .. zone) or "")
  elseif state.inLog then
    local progress = quest.ObjectiveText(state)
    return "Finish " .. name .. (progress ~= "" and (": " .. progress) or "")
  end
  local giver = questID and quest.Giver and quest.Giver(questID) or nil
  local zone = (giver and giver.zone) or fallbackZone
  return "Pick up " .. name .. (giver and giver.name and (" from " .. giver.name) or "") .. (zone and (" in " .. zone) or "")
end

-- The map point for a questline step, when one is recorded.
function Planner.QuestWaypoint(QP, step)
  if not step or not QUEST_STEP[step.type or "Quest"] or not step.questID or not QP.Waypoint then return nil end
  return QP.Waypoint(step.questID)
end

-- Items the open quests of a line (or one quest) still ask for:
-- { { itemID, quantity, name, questName } }, the same item summed across quests.
function Planner.QuestlineItems(QP, line, questID)
  local out, byItem, seenQuest = {}, {}, {}
  if not QP.RequiredItems then return out end
  local function add(qid, qname)
    if seenQuest[qid] then return end
    seenQuest[qid] = true
    for _, item in ipairs(QP.RequiredItems(qid)) do
      if item.itemID then
        local row = byItem[item.itemID]
        if not row then
          row = { itemID = item.itemID, quantity = 0, name = item.name, questName = qname }
          byItem[item.itemID] = row
          out[#out + 1] = row
        end
        row.quantity = row.quantity + (item.count or 1)
      end
    end
  end
  if line then
    for _, step in ipairs(line.steps) do
      if QUEST_STEP[step.type] and step.questID and not step.done and not (step.questState and step.questState.completed) then
        add(step.questID, step.name)
      end
    end
  elseif questID then
    add(questID, QP.Name(questID))
  end
  return out
end

-- The quest that rewards an item (for this faction) and the chain that
-- leads to it: { quest = entry, line }, or nil. Classic-db quests only
-- count for items that cannot be bought (bind on pickup, quest items) or
-- that have no other route (opts.noRoute): a potion some old quest also
-- rewards is still bought, not quested for.
function Planner.RewardQuestline(itemID, deps, opts)
  local QP = deps.quest
  if not (QP and QP.IsAvailable and QP.IsAvailable() and QP.QuestsRewarding) then return nil end
  local faction = QP.Faction and QP.Faction() or nil
  local first
  local classicOK
  local function allowClassic()
    if classicOK == nil then
      local bind = Planner.BindType(itemID, deps)
      classicOK = (bind == 1 or bind == 4) or (opts and opts.noRoute) or false
    end
    return classicOK
  end
  for _, entry in ipairs(QP.QuestsRewarding(itemID)) do
    if entry.classic and not allowClassic() then
      -- skipped: buyable, and something else sells or drops it
    elseif not faction or not entry.faction or entry.faction == "Both" or entry.faction == faction then
      local line = QP.Questline and QP.Questline(entry.id) or nil
      if line then return { quest = entry, line = line } end
      first = first or { quest = entry }
    end
  end
  return first
end

local function lowerFirst(text)
  return text:sub(1, 1):lower() .. text:sub(2)
end

-- Quest goals: the chain to do (journal prerequisites, then the quest) with
-- each quest's live state. Progress counts completed quests in the chain
-- plus the objectives of the one in the log. The view carries
-- `quest = { entry, state, chain, next, levelBlocked, playerLevel }`.
function Planner.EvaluateQuest(view, goal, deps)
  local QP = deps.quest
  local target = goal.target
  local questID = target.questID
  view.item = { name = target.name or ("Quest " .. tostring(questID)), icon = target.icon or (QP and QP.ICON) or nil, quality = 1, loaded = true, exists = true }
  if not QP or not QP.IsAvailable() then
    view.readiness = Readiness.PROVIDER_UNAVAILABLE
    view.message = "This client does not expose the quest API ForeverPath needs (C_QuestLog)."
    return view
  end
  local entry = QP.Get(questID)
  local name = QP.Name(questID)
  view.item.name = name
  local chain, nextStep = QP.Chain(questID)
  local line = QP.Questline and QP.Questline(questID) or nil
  local state = chain[#chain].state
  local playerLevel = QP.PlayerLevel()
  local requires = entry and entry.requires or nil
  local quest = {
    questID = questID, entry = entry, state = state, chain = chain, next = nextStep, playerLevel = playerLevel,
    levelBlocked = requires ~= nil and requires > playerLevel, requires = requires,
    stateKey = QP.StateKey(state, entry, playerLevel), line = line,
  }
  view.quest = quest
  if state.ready then view.item.icon = QP.ICON_READY end
  -- Attune's chain knows what the journal does not: an earlier step still blocks this one.
  if line and line.next and line.next ~= line.target and quest.stateKey == QuestStates.AVAILABLE then
    quest.stateKey = QuestStates.LOCKED
  end
  quest.label = QP.StateText(quest.stateKey)

  -- Progress: the chain's steps when Attune knows it, else the journal chain.
  if line then
    view.progress = { percent = line.percent, ownedUnits = line.done, requiredUnits = line.total, materialsHave = line.done, materialsTotal = line.total }
  else
    local done, partial = 0, 0
    for _, step in ipairs(chain) do
      if step.state.completed then done = done + 1
      elseif step == nextStep and step.state.inLog then partial = step.state.fraction end
    end
    local percent = #chain > 0 and math.floor((done + partial) * 100 / #chain + 0.5) or 0
    view.progress = { percent = percent, ownedUnits = done, requiredUnits = #chain, materialsHave = done, materialsTotal = #chain }
  end
  if state.completed then view.progress.percent = 100 end

  -- What the open quests of the chain ask for, laid out like reagents so the
  -- requirement rows, the tree and the shopping list carry them.
  local items = (not state.completed) and Planner.QuestlineItems(QP, line, questID) or {}
  local ctx = inventoryContext(deps)
  local tree = DependencyResolver.Resolve({ key = "quest:" .. tostring(questID),
    step = { kind = Steps.QUEST, questID = questID, name = name, icon = view.item.icon, items = items } }, ctx.resolverOpts(goal.routes))
  view.tree = tree
  view.plan = Planner.StepItemsPlan(tree, state.completed)
  view.inventoryNote = Planner.DescribeInventory(ctx.bankCounts, ctx.includeBank, ctx.includeAlts)
  quest.items = items

  local function where(step)
    local e = step.entry
    if not e then return nil end
    if e.pickup then return e.pickup end
    if e.start and e.start.label then return e.start.label end
    return e.location
  end
  local lineStep = line and line.next or nil
  if state.completed then
    view.message = string.format("%s is completed.", name)
    view.nextStep = "Mark the goal complete"
  elseif quest.levelBlocked then
    view.message = string.format("Needs level %d; you are %d.", requires, playerLevel)
    view.nextStep = string.format("Reach level %d", requires)
  elseif lineStep then
    local text = Planner.QuestStepText(QP, lineStep)
    view.nextStep = text
    view.waypoint = Planner.QuestWaypoint(QP, lineStep)
    if lineStep == line.target then
      view.message = text .. "."
    else
      view.message = string.format("First %s (step %d of %d of %s, before %s).", lowerFirst(text), math.min(line.done + 1, line.total), line.total, line.attune.name, name)
    end
  elseif nextStep and nextStep ~= chain[#chain] then
    local s = nextStep.state
    if s.ready then
      view.message = string.format("First turn in %s%s.", nextStep.name, nextStep.entry and nextStep.entry.turnin and (" at " .. nextStep.entry.turnin) or "")
      view.nextStep = "Turn in " .. nextStep.name
    elseif s.inLog then
      local progress = QP.ObjectiveText(s)
      view.message = string.format("First finish %s%s.", nextStep.name, progress ~= "" and (": " .. progress) or "")
      view.nextStep = "Finish " .. nextStep.name
    else
      local pickup = where(nextStep)
      view.message = string.format("First pick up %s%s (required before %s).", nextStep.name, pickup and (" from " .. pickup) or "", name)
      view.nextStep = "Pick up " .. nextStep.name
    end
  elseif state.ready then
    local turnin = (entry and entry.turnin) or (QP.Turnin and QP.Turnin(questID) or nil)
    local at = type(turnin) == "table" and turnin.label or turnin
    view.message = string.format("Ready to turn in%s.", at and (" at " .. at) or "")
    view.nextStep = "Turn in " .. name
    view.waypoint = Planner.QuestWaypoint(QP, { type = "Quest", questID = questID })
  elseif state.inLog then
    local progress = QP.ObjectiveText(state)
    view.message = string.format("In your log%s.", progress ~= "" and (": " .. progress) or (entry and entry.objective and (": " .. entry.objective) or ""))
    view.nextStep = "Finish " .. name
  else
    local pickup = where(chain[#chain])
    if pickup then
      view.message = string.format("Pick up %s from %s.", name, pickup)
      view.nextStep = "Pick up " .. name
    else
      -- No journal text: the recorded giver (quest facts) names the place.
      local text = Planner.QuestStepText(QP, { type = "Quest", questID = questID, name = name, questState = state })
      view.message = text .. "."
      view.nextStep = text
    end
    if entry and entry.objective then view.message = view.message .. " " .. entry.objective end
    view.waypoint = Planner.QuestWaypoint(QP, { type = "Quest", questID = questID })
  end
  return view
end

-- Reputation goals: progress is the standing itself (anchored at the value
-- when the goal was made); the view carries `reputation = { record,
-- progress, quests, rewards }` and names the first open quest that gives
-- reputation as the next step.
function Planner.EvaluateReputation(view, goal, deps)
  local RP = deps.reputation
  local target = goal.target
  view.item = { name = target.name or ("Faction " .. tostring(target.factionID)), icon = target.icon or (RP and RP.ICON) or nil, quality = 1, loaded = true, exists = true }
  if not RP or not RP.IsAvailable() then
    view.readiness = Readiness.PROVIDER_UNAVAILABLE
    view.message = "This client does not expose the faction API ForeverPath needs."
    return view
  end
  local progress = RP.Progress(target.factionID, target.standing, target.startValue)
  if not progress then
    view.readiness = Readiness.ITEM_INVALID
    view.message = string.format("%s is not in your reputation list yet.", target.name or ("Faction " .. tostring(target.factionID)))
    return view
  end
  local record = progress.record
  view.item.name = record.name
  local quests = RP.QuestsFor(record.name, record.factionID or goal.target.factionID)
  local rewards = RP.Rewards(target.factionID)
  view.reputation = { record = record, progress = progress, quests = quests, rewards = rewards, targetLabel = progress.targetLabel }
  view.progress = { percent = progress.percent, ownedUnits = math.max(0, (record.value or 0) - progress.start), requiredUnits = math.max(0, progress.targetMin - progress.start), materialsHave = 0, materialsTotal = 0 }
  view.plan = Planner.StepPlan(progress.reached)
  if progress.reached then
    view.message = string.format("%s with %s reached.", progress.targetLabel, record.name)
    view.nextStep = "Mark the goal complete"
    return view
  end
  local openQuest
  for _, quest in ipairs(quests) do
    if not quest.state.completed and not openQuest then openQuest = quest end
  end
  view.message = string.format("%d more reputation to %s with %s (you are %s, %d / %d into it%s).", progress.remaining, progress.targetLabel, record.name,
    record.standingLabel, record.into or 0, record.span or 0, record.unmet and "; not met yet" or "")
  if openQuest then
    view.message = view.message .. string.format(" Quest %s gives +%d.", openQuest.name, openQuest.amount)
    view.nextStep = string.format("%s (+%d)", openQuest.name, openQuest.amount)
  else
    view.nextStep = string.format("Earn %d reputation with %s", progress.remaining, record.name)
  end
  return view
end
