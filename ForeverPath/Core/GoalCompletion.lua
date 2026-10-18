-- Completes goals automatically when the item lands in your bags, and
-- celebrates it (toast, sound, chat line).
--
-- Crafting goals count what you gained since the goal was made: the bag and
-- bank count when the goal was added is stored as target.baseline and the
-- best gain seen as target.peak, so crafting two bolts and using them straight
-- away still completes "Craft 2x Bolt". Obtain goals complete when you hold
-- the quantity. Goals saved before this version get their baseline on the
-- first check, so an upgrade never completes a goal by itself.
--
-- Settings (account): autoComplete, toasts, completeSound.
local _, ns = ...

local Events = ns.Events
local Log = ns.Log
local GoalModel = ns.GoalModel

local GoalCompletion = { lastStatus = {} }
ns.GoalCompletion = GoalCompletion

GoalCompletion.SOUND = 888 -- SOUNDKIT.LEVELUP: the level-up fanfare

local function setting(key, default)
  local settings = ns.db and ns.db.settings
  if settings and settings[key] ~= nil then return settings[key] end
  return default
end

-- Bags plus bank (when the bank is known and counted) for this character.
function GoalCompletion.Count(itemID)
  local provider = ns.InventoryProvider
  if not provider then return 0 end
  if provider.bags and provider.bags.dirty and provider.ScanBags then
    provider.ScanBags()
  end
  local counts = provider.GetCounts(itemID)
  if type(counts) == "number" then return counts end
  if type(counts) ~= "table" then return 0 end
  local total = tonumber(counts.bags) or 0
  if setting("includeBank", true) and tonumber(counts.bank) then
    total = total + counts.bank
  end
  return total
end

local function itemGoal(goal)
  local def = goal and GoalModel.Types[goal.type]
  return def and def.targetKind == "item" and goal.target and goal.target.itemID ~= nil
end

-- Records the starting count for a goal (once).
function GoalCompletion.Baseline(goal, force)
  if not itemGoal(goal) then return end
  if force or goal.target.baseline == nil then
    goal.target.baseline = GoalCompletion.Count(goal.target.itemID)
    goal.target.peak = 0
  end
end

-- Progress for one goal: { count, gained, peak, needed, done }
function GoalCompletion.Progress(goal)
  if not itemGoal(goal) then return nil end
  local count = GoalCompletion.Count(goal.target.itemID)
  local quantity = goal.target.quantity or 1
  if goal.type == "OBTAIN_ITEM" then
    return { count = count, needed = quantity, done = count >= quantity }
  end
  local baseline = goal.target.baseline
  if baseline == nil then
    return { count = count, needed = quantity, done = false, unbased = true }
  end
  local gained = math.max(0, count - baseline)
  local peak = math.max(tonumber(goal.target.peak) or 0, gained)
  goal.target.peak = peak
  return { count = count, gained = gained, peak = peak, needed = quantity, done = peak >= quantity }
end

-- This character's current skill in a profession, or nil without it.
function GoalCompletion.SkillLevel(target)
  local planner = ns.Planner
  if not planner or not planner.CurrentSkill then return nil end
  local standing = planner.CurrentSkill(planner.DefaultDeps(), target.professionName, target.professionID)
  return standing and standing.skillLevel or nil
end

-- Checks every open goal; completes and celebrates the finished ones.
-- Returns the list of goals completed by this call.
function GoalCompletion.Check(reason)
  local completed = {}
  if not setting("autoComplete", true) then return completed end
  local store = ns.GoalService and ns.GoalService.Store()
  if not store then return completed end
  local function finish(goal, info)
    local ok = ns.GoalService.SetStatus(goal.id, GoalModel.Statuses.COMPLETED)
    if ok then
      goal.target.completedBy = "auto"
      completed[#completed + 1] = goal
      GoalCompletion.Celebrate(goal, info)
    end
  end
  for _, goal in ipairs(ns.GoalService.List({ open = true })) do
    if goal.type == "COMPLETE_ATTUNEMENT" and ns.AttuneProvider and ns.AttuneProvider.IsAvailable() then
      local progress = ns.AttuneProvider.Progress(goal.target.attuneID)
      if progress and progress.complete then
        finish(goal, progress)
      end
    elseif goal.type == "COMPLETE_QUEST" then
      if ns.QuestProvider and ns.QuestProvider.IsAvailable() and ns.QuestProvider.State(goal.target.questID).completed then
        finish(goal, { quest = true })
      end
    elseif goal.type == "REACH_REPUTATION" then
      local RP = ns.ReputationProvider
      local progress = RP and RP.IsAvailable() and RP.Progress(goal.target.factionID, goal.target.standing, goal.target.startValue) or nil
      if progress and progress.reached then
        finish(goal, { reputation = true })
      end
    elseif goal.type == "LEARN_RECIPE" then
      if ns.ProfessionProvider and ns.ProfessionProvider.IsLearned(goal.target.spellID) then
        finish(goal, { learned = true })
      end
    elseif goal.type == "REACH_SKILL" then
      local level = GoalCompletion.SkillLevel(goal.target)
      if level and level >= (goal.target.rank or 0) then
        finish(goal, { skillLevel = level })
      end
    elseif itemGoal(goal) then
      if goal.target.baseline == nil and goal.type ~= "OBTAIN_ITEM" then
        GoalCompletion.Baseline(goal)
      else
        local progress = GoalCompletion.Progress(goal)
        if progress and progress.done then
          finish(goal, progress)
        end
      end
    end
  end
  if #completed > 0 then
    Log.Debug("Auto-completed %d goal(s) (%s)", #completed, tostring(reason))
  end
  return completed
end

-- Toast + sound + chat line. info = Progress() result (optional).
function GoalCompletion.Celebrate(goal, info)
  local name = ns.GoalService.Name(goal)
  local quantity = goal.target and goal.target.quantity or 1
  local verb = goal.type == "OBTAIN_ITEM" and "Obtained" or "Crafted"
  local doneCount = ns.GoalService.Count({ status = GoalModel.Statuses.COMPLETED })
  local detail
  if goal.type == "COMPLETE_ATTUNEMENT" then
    detail = "Attuned: " .. name
  elseif goal.type == "LEARN_RECIPE" then
    detail = "Learned: " .. name
  elseif goal.type == "REACH_SKILL" then
    detail = name .. " reached"
  elseif goal.type == "COMPLETE_QUEST" then
    detail = "Quest done: " .. name
  elseif goal.type == "REACH_REPUTATION" then
    detail = name .. " reached"
  else
    detail = string.format("%s %dx %s", verb, quantity, name)
  end
  local TITLES = { COMPLETE_ATTUNEMENT = "Attunement complete", LEARN_RECIPE = "Recipe learned", REACH_SKILL = "Skill reached", COMPLETE_QUEST = "Quest complete", REACH_REPUTATION = "Reputation reached" }
  Log.Print("Goal complete: %s. %d goal%s done.", detail, doneCount, doneCount == 1 and "" or "s")
  if setting("completeSound", true) and type(PlaySound) == "function" then
    local kit = (type(SOUNDKIT) == "table" and SOUNDKIT.LEVELUP) or GoalCompletion.SOUND
    pcall(PlaySound, kit, "Master")
  end
  if setting("toasts", true) and ns.UI and ns.UI.Toast then
    local item = goal.target.itemID and ns.ItemProvider and ns.ItemProvider.GetItem(goal.target.itemID) or { icon = goal.target.icon, quality = 1 }
    ns.UI.Toast.Show({
      title = TITLES[goal.type] or "Goal complete",
      name = name,
      quality = item.quality,
      icon = item.icon,
      detail = detail,
      sub = string.format("%d goal%s done", doneCount, doneCount == 1 and "" or "s"),
      goalID = goal.id,
    })
  end
end

function GoalCompletion.Init()
  Events.On("FP_GOALS_CHANGED", function(event, goal)
    if not goal then return end
    if event == "added" then
      GoalCompletion.Baseline(goal, true)
    elseif event == "updated" and itemGoal(goal) then
      local last = GoalCompletion.lastStatus[goal.id]
      if last == GoalModel.Statuses.COMPLETED and GoalModel.IsOpen(goal) then
        -- Reopened: start counting again from what is in the bags now.
        GoalCompletion.Baseline(goal, true)
      end
    end
    GoalCompletion.lastStatus[goal.id] = goal.status
  end)
  Events.On("FP_INVENTORY_UPDATED", function()
    GoalCompletion.Check("inventory")
  end)
  -- Recipes learned and skill-ups complete learn-recipe and reach-skill goals.
  Events.On("FP_RECIPES_UPDATED", function()
    Events.Debounce("recipe-goal-check", 0.5, function() GoalCompletion.Check("recipes") end)
  end)
  Events.RegisterWoW("SKILL_LINES_CHANGED", function()
    Events.Debounce("skill-goal-check", 1, function()
      GoalCompletion.Check("skill")
      if ns.UI and ns.UI.MainFrame then ns.UI.MainFrame.RequestRefresh() end
    end)
  end)
  Events.RegisterWoW("UPDATE_FACTION", function()
    Events.Debounce("reputation-goal-check", 1, function()
      GoalCompletion.Check("reputation")
    end)
  end)
  -- Attunement steps and quest goals move on quests and levels.
  for _, event in ipairs({ "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP", "QUEST_ACCEPTED" }) do
    Events.RegisterWoW(event, function()
      Events.Debounce("attunement-check", 1, function()
        GoalCompletion.Check("quest")
        if ns.UI and ns.UI.MainFrame then ns.UI.MainFrame.RequestRefresh() end
      end)
    end)
  end
  Events.RegisterWoW("PLAYER_ENTERING_WORLD", function()
    -- Remember statuses so a later reopen is noticed, and baseline old goals.
    local store = ns.GoalService and ns.GoalService.Store()
    if not store then return end
    for _, goal in ipairs(ns.GoalService.List()) do
      GoalCompletion.lastStatus[goal.id] = goal.status
    end
    if ns.Compat.After then
      ns.Compat.After(3, function() GoalCompletion.Check("login") end)
    end
  end)
end
