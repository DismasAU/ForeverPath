-- Which quests and equipment slots serve which goals. Pure builders over
-- data the caller gathers (GoalService passes the open goals, their views
-- and provider lookups), like Overview and ShoppingList.
local _, ns = ...

local GoalModel = ns.GoalModel
local Util = ns.Util

local GoalAttribution = {}
ns.GoalAttribution = GoalAttribution

-- Which quests feed the goals: { [questID] = { entry, goals = { { goal, name,
-- itemID, count } | { goal, name, reputation, faction } } } }, from the
-- missing leaves of each goal's tree (quest rewards) and, for reputation
-- goals, every open quest that gives reputation with the faction.
-- entries = { { goal, view, name } }
-- deps.questsRewarding(itemID) -> quest entries
-- deps.reputationQuests(goal) -> { { entry, amount, state } } when the view has none
function GoalAttribution.QuestFeeds(entries, deps)
  local feeds = {}
  local function feedFor(entry)
    local feed = feeds[entry.id]
    if not feed then
      feed = { entry = entry, goals = {} }
      feeds[entry.id] = feed
    end
    return feed
  end
  for _, e in ipairs(entries) do
    local goal, view, name = e.goal, e.view, e.name
    if goal.type == GoalModel.TypeIDs.REACH_REPUTATION then
      local quests = view and view.reputation and view.reputation.quests or deps.reputationQuests(goal)
      for _, quest in ipairs(quests or {}) do
        if quest.entry and not (quest.state and quest.state.completed) then
          local feed = feedFor(quest.entry)
          feed.goals[#feed.goals + 1] = { goal = goal, name = name, reputation = quest.amount, faction = goal.target.name }
        end
      end
    else
      for _, leaf in ipairs(view and view.tree and view.tree.summary.missingLeaves or {}) do
        if leaf.itemID then
          for _, entry in ipairs(deps.questsRewarding(leaf.itemID)) do
            local feed = feedFor(entry)
            feed.goals[#feed.goals + 1] = { goal = goal, name = name, itemID = leaf.itemID, count = leaf.count }
          end
        end
      end
    end
  end
  return feeds
end

-- The Quests screen's board for a tab ("zone", "goal" or "completed"):
-- { groups = { { key, label, rows = { { questID, name, level, label, kind,
-- stateKey, state, entry, feeds = { goal names }, feed, goal } } } }, feeds,
-- feedCount, total, questGoals }. Zone groups are instances or log zones;
-- goal groups are named after the goals a quest serves, journal and
-- quest-log quests alike. feedOnly keeps only quests that serve a goal on
-- the zone tab.
-- data = { quests (index entries), logEntries, feeds, questGoals = { [questID] = goal },
--          nameOf(goal), state(questID), stateLabel(state, entry) -> label, kind, key,
--          questName(questID), get(questID) }
function GoalAttribution.QuestBoard(tab, feedOnly, data)
  local feeds, questGoals = data.feeds, data.questGoals
  -- The goals a quest serves, its own quest goal first.
  local function servedGoals(questID)
    local names = {}
    if questGoals[questID] then names[1] = data.nameOf(questGoals[questID]) end
    for _, f in ipairs(feeds[questID] and feeds[questID].goals or {}) do names[#names + 1] = f.name end
    return names
  end
  local groups, byLabel, seen = {}, {}, {}
  local function add(groupLabel, questID, name, level, state, entry)
    if seen[questID] then return end
    seen[questID] = true
    local g = byLabel[groupLabel]
    if not g then
      g = { key = groupLabel, label = groupLabel, rows = {} }
      byLabel[groupLabel] = g
      groups[#groups + 1] = g
    end
    local label, kind, key = data.stateLabel(state, entry)
    local goal = questGoals[questID]
    local feedNames = servedGoals(questID)
    if goal then feedNames[1] = "goal: " .. feedNames[1] end
    g.rows[#g.rows + 1] = {
      questID = questID, name = name, level = level, label = label, kind = kind, stateKey = key, state = state, entry = entry,
      feeds = feedNames, feed = feeds[questID], goal = goal,
    }
  end
  local function serves(questID) return feeds[questID] ~= nil or questGoals[questID] ~= nil end
  local function groupFor(questID, zone)
    return tab == "goal" and table.concat(servedGoals(questID), ", ") or zone
  end
  for _, entry in ipairs(data.quests) do
    local state = data.state(entry.id)
    local include
    if tab == "completed" then include = state.completed
    elseif tab == "goal" then include = serves(entry.id) and not state.completed
    else include = not state.completed and (not feedOnly or serves(entry.id)) end
    if include then add(groupFor(entry.id, entry.instance or "?"), entry.id, entry.name, entry.level, state, entry) end
  end
  if tab ~= "completed" then
    for _, log in ipairs(data.logEntries) do
      local wanted = tab == "goal" and serves(log.questID) or (tab ~= "goal" and (not feedOnly or serves(log.questID)))
      if not seen[log.questID] and wanted then
        add(groupFor(log.questID, log.zone or "Quest log"), log.questID, log.title or data.questName(log.questID), log.level,
          data.state(log.questID), data.get(log.questID))
      end
    end
  end
  table.sort(groups, function(a, b) return tostring(a.label) < tostring(b.label) end)
  local total = 0
  for _, g in ipairs(groups) do
    table.sort(g.rows, function(a, b)
      if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
      if a.name ~= b.name then return tostring(a.name) < tostring(b.name) end
      return a.questID < b.questID
    end)
    total = total + #g.rows
  end
  return { groups = groups, feeds = feeds, feedCount = Util.Count(feeds), total = total, questGoals = questGoals }
end

-- Places item goals on the equipment slots their items fit, first come
-- first served (goals in priority order). slotKeysFor(itemID) -> slot keys.
-- Returns goalSlots = { [slotKey] = goal } and tracked (item goals that are
-- gear, placed or not).
function GoalAttribution.PlaceOnSlots(goals, slotKeysFor)
  local goalSlots, tracked = {}, 0
  for _, goal in ipairs(goals) do
    if GoalModel.Types[goal.type].targetKind == "item" then
      local keys = slotKeysFor(goal.target.itemID)
      if #keys > 0 then
        tracked = tracked + 1
        for _, key in ipairs(keys) do
          if not goalSlots[key] then
            goalSlots[key] = goal
            break
          end
        end
      end
    end
  end
  return goalSlots, tracked
end
