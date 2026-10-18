-- Quests: what the client says about them (log, objectives, completed
-- flags) plus the quest knowledge other Forever addons ship.
--
-- The client cannot enumerate quests it has never seen, so the static index
-- comes from two read-only bridges:
--   ForeverDungeonJournal (_G.ForeverDungeonJournal_NS): DB[dungeon].quests
--     (id, name, level, requires, faction, objective, pickup, turnin,
--     rewards text, rewardItems = { { itemID, name, quality } }, rewardChoice,
--     liveXPFallback), QUEST_PREREQ_CHAINS[questID] = { { id, name } } (the
--     quests required to unlock it, in order), QUEST_START_MAPS[questID] =
--     { mapID, x, y, label, targetName, detail }.
--   Attune (Attune_Data): quests[questID] = { requiredLevel, groupSize },
--     AttuneLang["Q1_<id>"] names, questGivers[questID] = { uiMapID, x, y,
--     giverName }, questRewards[questID] = { choice = { { itemID, count } },
--     fixed = { ... } }, and the attunement whose chain uses the quest.
-- Quests in the player's log are read from C_QuestLog whether or not either
-- addon knows them; titles of other quests are requested from the client
-- (RequestLoadQuestByID) and arrive with QUEST_DATA_LOAD_RESULT.
local _, ns = ...

local Compat = ns.Compat
local Util = ns.Util
local Log = ns.Log
local Events = ns.Events

local QuestProvider = { index = nil, titles = {}, requested = {}, logCache = nil }
ns.QuestProvider = QuestProvider

QuestProvider.ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
QuestProvider.ICON_READY = "Interface\\GossipFrame\\ActiveQuestIcon"
QuestProvider.MAX_LOG = 20

local function questLog()
  return type(C_QuestLog) == "table" and C_QuestLog or nil
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
  return nil
end

function QuestProvider.IsAvailable()
  return Compat.IsQuestFlaggedCompleted ~= nil and Compat.IsOnQuest ~= nil
end

local function journal()
  local j = _G.ForeverDungeonJournal_NS
  if type(j) == "table" and type(j.DB) == "table" then return j end
  return nil
end

local function attune()
  local d = _G.Attune_Data
  if type(d) == "table" and type(d.quests) == "table" then return d end
  return nil
end

function QuestProvider.HasJournal()
  return journal() ~= nil
end

function QuestProvider.HasAttune()
  return attune() ~= nil
end

local function attuneName(questID)
  local l = _G.AttuneLang
  if type(l) ~= "table" then return nil end
  local key = "Q1_" .. tostring(questID)
  local ok, value = pcall(function() return l[key] end)
  if ok and type(value) == "string" and value ~= key then return value end
  return nil
end

local function rewardsFromJournal(quest)
  local items = {}
  for _, reward in ipairs(type(quest.rewardItems) == "table" and quest.rewardItems or {}) do
    if type(reward) == "table" and tonumber(reward[1]) then
      items[#items + 1] = { itemID = tonumber(reward[1]), name = reward[2], quality = reward[3], count = 1 }
    end
  end
  return items
end

local function rewardsFromAttune(record)
  local items = {}
  if type(record) ~= "table" then return items, false end
  for _, entry in ipairs(type(record.fixed) == "table" and record.fixed or {}) do
    if type(entry) == "table" and tonumber(entry[1]) then items[#items + 1] = { itemID = tonumber(entry[1]), count = tonumber(entry[2]) or 1, fixed = true } end
  end
  local choice = false
  for _, entry in ipairs(type(record.choice) == "table" and record.choice or {}) do
    if type(entry) == "table" and tonumber(entry[1]) then
      items[#items + 1] = { itemID = tonumber(entry[1]), count = tonumber(entry[2]) or 1 }
      choice = true
    end
  end
  return items, choice
end

-- Builds the static index once: questID -> entry. Entries carry
--   { id, name, level, requires, faction, instance, location, pickup, turnin, objective,
--     rewardText, rewardSummary, rewards = { { itemID, name, quality, count } }, rewardChoice,
--     xp, source ("journal" | "attune" | "chain"), chain = { { id, name } }, start = { mapID, x, y, label },
--     attunement, groupSize }
function QuestProvider.Index()
  if QuestProvider.index then return QuestProvider.index end
  local index = {}
  local j = journal()
  if j then
    local chains = type(j.QUEST_PREREQ_CHAINS) == "table" and j.QUEST_PREREQ_CHAINS or {}
    local starts = type(j.QUEST_START_MAPS) == "table" and j.QUEST_START_MAPS or {}
    local xp = type(j.FOREVER_QUEST_XP_FALLBACK) == "table" and j.FOREVER_QUEST_XP_FALLBACK or {}
    for dungeonName, dungeon in pairs(j.DB) do
      for _, quest in ipairs(type(dungeon) == "table" and type(dungeon.quests) == "table" and dungeon.quests or {}) do
        local id = type(quest) == "table" and tonumber(quest.id) or nil
        if id and not index[id] then
          local start = starts[id]
          index[id] = {
            id = id, name = quest.name or ("Quest " .. id), level = tonumber(quest.level), requires = tonumber(quest.requires),
            faction = quest.faction or "Both", instance = tostring(dungeonName), location = dungeon.location,
            pickup = quest.pickup, turnin = quest.turnin, objective = quest.objective,
            rewardText = quest.rewards, rewardSummary = quest.rewardSummary, rewards = rewardsFromJournal(quest), rewardChoice = quest.rewardChoice == true,
            xp = tonumber(quest.liveXPFallback) or xp[id], source = "journal",
            chain = type(chains[id]) == "table" and chains[id] or nil,
            start = type(start) == "table" and { mapID = start.mapID, x = start.x, y = start.y, label = start.label, target = start.targetName, detail = start.detail } or nil,
          }
        end
      end
    end
    -- Prerequisites that are not dungeon quests themselves still get an entry.
    for questID, chain in pairs(chains) do
      local owner = index[tonumber(questID)]
      for _, link in ipairs(type(chain) == "table" and chain or {}) do
        local id = type(link) == "table" and tonumber(link.id) or nil
        if id and not index[id] then
          local start = starts[id]
          index[id] = {
            id = id, name = link.name or ("Quest " .. id), faction = owner and owner.faction or "Both",
            instance = owner and owner.instance or "Prerequisites", location = owner and owner.location, source = "chain", prereqOf = tonumber(questID),
            rewards = {}, xp = xp[id],
            start = type(start) == "table" and { mapID = start.mapID, x = start.x, y = start.y, label = start.label, target = start.targetName, detail = start.detail } or nil,
          }
        end
      end
    end
  end
  local a = attune()
  if a then
    local givers = type(a.questGivers) == "table" and a.questGivers or {}
    local rewards = type(a.questRewards) == "table" and a.questRewards or {}
    -- Which attunement and location each quest belongs to.
    local usedBy = {}
    for _, step in ipairs(type(a.steps) == "table" and a.steps or {}) do
      local t = step.TYPE
      if t == "Quest" or t == "Pick Up" or t == "Turn In" then
        for id in tostring(step.ID_WOWHEAD or ""):gmatch("%d+") do
          id = tonumber(id)
          if id and not usedBy[id] then usedBy[id] = { attune = tostring(step.ID_ATTUNE), location = step.LOCATION } end
        end
      end
    end
    local attuneNames = {}
    for _, raw in ipairs(type(a.attunes) == "table" and a.attunes or {}) do
      attuneNames[tostring(raw.ID)] = { name = raw.NAME, faction = raw.FACTION }
    end
    for questID, record in pairs(a.quests) do
      local id = tonumber(questID)
      if id then
        local name = attuneName(id)
        local use = usedBy[id]
        local owner = use and attuneNames[use.attune] or nil
        local entry = index[id]
        if not entry then
          local items, choice = rewardsFromAttune(rewards[id])
          local giver = givers[id]
          entry = {
            id = id, name = name or ("Quest " .. id), requires = type(record) == "table" and tonumber(record[1]) or nil,
            groupSize = type(record) == "table" and tonumber(record[2]) or nil,
            faction = owner and owner.faction or "Both", instance = owner and owner.name or "Attunements", location = use and use.location or nil,
            pickup = type(giver) == "table" and giver[4] or nil, rewards = items, rewardChoice = choice, source = "attune",
            start = type(giver) == "table" and { mapID = giver[1], x = giver[2], y = giver[3], label = giver[4] } or nil,
          }
          index[id] = entry
        else
          entry.groupSize = entry.groupSize or (type(record) == "table" and tonumber(record[2]) or nil)
          entry.requires = entry.requires or (type(record) == "table" and tonumber(record[1]) or nil)
          if not entry.start and type(givers[id]) == "table" then
            local giver = givers[id]
            entry.start = { mapID = giver[1], x = giver[2], y = giver[3], label = giver[4] }
            entry.pickup = entry.pickup or giver[4]
          end
        end
        if owner then entry.attunement = owner.name end
      end
    end
  end
  QuestProvider.index = index
  return index
end

function QuestProvider.Invalidate()
  QuestProvider.index = nil
  QuestProvider.logCache = nil
end

function QuestProvider.Get(questID)
  return QuestProvider.Index()[tonumber(questID) or 0]
end

function QuestProvider.Faction()
  if type(UnitFactionGroup) == "function" then
    local ok, faction = pcall(UnitFactionGroup, "player")
    if ok and type(faction) == "string" then return faction end
  end
  return nil
end

local function factionMatches(entry, faction)
  local f = entry.faction
  return f == nil or f == "Both" or faction == nil or f == faction
end

-- Every indexed quest for a faction (default: the player's), sorted by instance then level then name.
function QuestProvider.List(faction)
  faction = faction or QuestProvider.Faction()
  local out = {}
  for _, entry in pairs(QuestProvider.Index()) do
    if factionMatches(entry, faction) then out[#out + 1] = entry end
  end
  table.sort(out, function(a, b)
    if a.instance ~= b.instance then return tostring(a.instance) < tostring(b.instance) end
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
    if a.name ~= b.name then return tostring(a.name) < tostring(b.name) end
    return a.id < b.id
  end)
  return out
end

function QuestProvider.PlayerLevel()
  local level = call(UnitLevel, "player")
  return tonumber(level) or 0
end

-- "trivial" (grey), "easy" (green), "standard" (yellow), "hard" (orange), "impossible" (red).
function QuestProvider.Difficulty(questLevel, playerLevel)
  questLevel, playerLevel = tonumber(questLevel), tonumber(playerLevel) or 0
  if not questLevel then return "standard" end
  local diff = questLevel - playerLevel
  if diff >= 5 then return "impossible" end
  if diff >= 3 then return "hard" end
  if diff >= -2 then return "standard" end
  local grey
  if playerLevel <= 5 then grey = 0
  elseif playerLevel <= 39 then grey = playerLevel - 5 - math.floor(playerLevel / 10)
  elseif playerLevel <= 59 then grey = playerLevel - 1 - math.floor(playerLevel / 5)
  else grey = playerLevel - 9 end
  if questLevel > grey then return "easy" end
  return "trivial"
end

---------------------------------------------------------------------------
-- Live state
---------------------------------------------------------------------------
local function copyObjectives(list)
  local out = {}
  for _, o in ipairs(type(list) == "table" and list or {}) do
    if type(o) == "table" then
      out[#out + 1] = { text = o.text, type = o.type, finished = o.finished == true, numFulfilled = tonumber(o.numFulfilled) or 0, numRequired = tonumber(o.numRequired) or 0 }
    end
  end
  return out
end

-- The quest log as the client lists it: { { questID, title, level, zone, ready, isHeader } }, plus counts.
function QuestProvider.LogEntries()
  if QuestProvider.logCache then return QuestProvider.logCache end
  local ql = questLog()
  local entries, zone = {}, nil
  local count = ql and call(ql.GetNumQuestLogEntries) or nil
  if ql and type(ql.GetInfo) == "function" and tonumber(count) then
    for i = 1, count do
      local info = call(ql.GetInfo, i)
      if type(info) == "table" then
        if info.isHeader then
          zone = info.title
        elseif tonumber(info.questID) then
          entries[#entries + 1] = { questID = tonumber(info.questID), title = info.title, level = tonumber(info.level), zone = zone, logIndex = i,
            ready = call(ql.IsComplete, info.questID) == true }
        end
      end
    end
  end
  QuestProvider.logCache = entries
  return entries
end

-- numQuests, maxQuests for the log footer.
function QuestProvider.LogCapacity()
  local ql = questLog()
  local _, numQuests = ql and call(ql.GetNumQuestLogEntries) or nil, nil
  if ql then
    local entries, quests = call(ql.GetNumQuestLogEntries)
    numQuests = tonumber(quests) or #QuestProvider.LogEntries()
    local max = call(ql.GetMaxNumQuestsCanAccept)
    return numQuests, tonumber(max) or QuestProvider.MAX_LOG
  end
  return 0, QuestProvider.MAX_LOG
end

-- { completed, inLog, ready, logIndex, title, level, objectives = { { text, finished, numFulfilled, numRequired } }, fraction }
function QuestProvider.State(questID)
  local state = { completed = false, inLog = false, ready = false, objectives = {}, fraction = 0 }
  if not QuestProvider.IsAvailable() then return state end
  local ok, done = pcall(Compat.IsQuestFlaggedCompleted, questID)
  state.completed = ok and done == true
  ok, done = pcall(Compat.IsOnQuest, questID)
  state.inLog = ok and done == true
  local ql = questLog()
  if state.inLog and ql then
    state.ready = call(ql.IsComplete, questID) == true
    local logIndex = call(ql.GetLogIndexForQuestID, questID)
    state.logIndex = tonumber(logIndex)
    if state.logIndex and type(ql.GetInfo) == "function" then
      local info = call(ql.GetInfo, state.logIndex)
      if type(info) == "table" then
        state.title, state.level = info.title, tonumber(info.level)
      end
    end
    state.objectives = copyObjectives(call(ql.GetQuestObjectives, questID))
    local total, got = 0, 0
    for _, o in ipairs(state.objectives) do
      if o.numRequired > 0 then
        total = total + o.numRequired
        got = got + math.min(o.numFulfilled, o.numRequired)
      else
        total = total + 1
        got = got + (o.finished and 1 or 0)
      end
    end
    if state.ready then state.fraction = 1
    elseif total > 0 then state.fraction = got / total end
  end
  if state.completed then state.fraction = 1 end
  return state
end

-- "3/8 Deviate Hides, Mad Magglish slain"
function QuestProvider.ObjectiveText(state)
  local parts = {}
  for _, o in ipairs(state and state.objectives or {}) do
    if o.numRequired > 0 then
      parts[#parts + 1] = string.format("%d/%d %s", o.numFulfilled, o.numRequired, (o.text or ""):gsub("^%d+/%d+%s*", ""))
    elseif o.text and o.text ~= "" then
      parts[#parts + 1] = o.text .. (o.finished and " (done)" or "")
    end
  end
  return table.concat(parts, ", ")
end

-- Name from the index, the log, the title cache, or the client (loaded asynchronously).
function QuestProvider.Name(questID)
  local entry = QuestProvider.Get(questID)
  if entry and entry.name then return entry.name end
  for _, log in ipairs(QuestProvider.LogEntries()) do
    if log.questID == questID and log.title then return log.title end
  end
  if QuestProvider.titles[questID] then return QuestProvider.titles[questID] end
  local ql = questLog()
  if ql then
    local title = call(ql.GetTitleForQuestID, questID)
    if type(title) == "string" and title ~= "" then
      QuestProvider.titles[questID] = title
      return title
    end
    if not QuestProvider.requested[questID] and type(ql.RequestLoadQuestByID) == "function" then
      QuestProvider.requested[questID] = true
      pcall(ql.RequestLoadQuestByID, questID)
    end
  end
  return "Quest " .. tostring(questID)
end

-- The quests to do, in order: prerequisites (journal chain) then the quest
-- itself, each with its live state. `next` is the first one not completed.
function QuestProvider.Chain(questID)
  local entry = QuestProvider.Get(questID)
  local steps = {}
  for _, link in ipairs(entry and entry.chain or {}) do
    local id = tonumber(link.id)
    if id then
      local state = QuestProvider.State(id)
      steps[#steps + 1] = { id = id, name = link.name or QuestProvider.Name(id), state = state, entry = QuestProvider.Get(id), prerequisite = true }
    end
  end
  local state = QuestProvider.State(questID)
  steps[#steps + 1] = { id = questID, name = entry and entry.name or QuestProvider.Name(questID), state = state, entry = entry }
  local nextStep
  for _, step in ipairs(steps) do
    if not step.state.completed and not nextStep then nextStep = step end
  end
  return steps, nextStep
end

-- Quests (indexed) that reward itemID.
function QuestProvider.QuestsRewarding(itemID)
  local out = {}
  for _, entry in pairs(QuestProvider.Index()) do
    for _, reward in ipairs(entry.rewards or {}) do
      if reward.itemID == itemID then out[#out + 1] = entry break end
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- Which quests feed open goals: { [questID] = { entry, goals = { { goal, name, itemID, count } } } },
-- from the missing leaves of each goal's tree. views: goalID -> view.
function QuestProvider.FeedsGoals(goals, views, nameOf)
  local feeds = {}
  for _, goal in ipairs(goals or {}) do
    local view = views and views[goal.id]
    local leaves = view and view.tree and view.tree.summary and view.tree.summary.missingLeaves or {}
    for _, leaf in ipairs(leaves) do
      if leaf.itemID then
        for _, entry in ipairs(QuestProvider.QuestsRewarding(leaf.itemID)) do
          local feed = feeds[entry.id]
          if not feed then
            feed = { entry = entry, goals = {} }
            feeds[entry.id] = feed
          end
          feed.goals[#feed.goals + 1] = { goal = goal, name = nameOf and nameOf(goal) or goal.id, itemID = leaf.itemID, count = leaf.count }
        end
      end
    end
  end
  return feeds
end

-- Quests by name (index and log), exact and prefix matches first.
function QuestProvider.Search(text, limit)
  if type(text) ~= "string" then return {} end
  local needle = string.lower(Util.Trim(text))
  if needle == "" then return {} end
  local hits, seen = {}, {}
  local function consider(id, name, where)
    if seen[id] or type(name) ~= "string" then return end
    local lower = string.lower(name)
    local position = lower:find(needle, 1, true)
    if position then
      seen[id] = true
      hits[#hits + 1] = { questID = id, name = name, where = where, rank = lower == needle and 0 or (position == 1 and 1 or 2) }
    end
  end
  local faction = QuestProvider.Faction()
  for _, entry in pairs(QuestProvider.Index()) do
    if factionMatches(entry, faction) then consider(entry.id, entry.name, entry.instance) end
  end
  for _, log in ipairs(QuestProvider.LogEntries()) do
    consider(log.questID, log.title, log.zone or "Quest log")
  end
  table.sort(hits, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.name ~= b.name then return a.name < b.name end
    return a.questID < b.questID
  end)
  if limit and #hits > limit then
    for i = #hits, limit + 1, -1 do hits[i] = nil end
  end
  return hits
end

-- "Ready", "In log", "Available", "Locked", "Done" for a quest (entry optional).
function QuestProvider.StateLabel(state, entry, playerLevel)
  if state.completed then return "Done", "ok" end
  if state.ready then return "Ready", "ok" end
  if state.inLog then return "In log", "info" end
  playerLevel = playerLevel or QuestProvider.PlayerLevel()
  if entry and entry.requires and entry.requires > playerLevel then return "Locked", "text" end
  if entry and entry.chain then
    for _, link in ipairs(entry.chain) do
      local id = tonumber(link.id)
      if id and not QuestProvider.State(id).completed then return "Locked", "text" end
    end
  end
  return "Available", "partial"
end

function QuestProvider.Count()
  local n = 0
  for _ in pairs(QuestProvider.Index()) do n = n + 1 end
  return n
end

function QuestProvider.Status()
  if not QuestProvider.IsAvailable() then
    return "Quests: the quest API (C_QuestLog) is unavailable on this client."
  end
  local sources = {}
  if QuestProvider.HasJournal() then sources[#sources + 1] = "ForeverDungeonJournal" end
  if QuestProvider.HasAttune() then sources[#sources + 1] = "Attune" end
  local numQuests, max = QuestProvider.LogCapacity()
  return string.format("Quests: %d known from %s; quest log %d / %d.", QuestProvider.Count(), #sources > 0 and table.concat(sources, " and ") or "no data addon", numQuests, max)
end

-- Chat lines for one quest.
function QuestProvider.Describe(questID, nameOf)
  nameOf = nameOf or function(id) return "Item " .. tostring(id) end
  local entry = QuestProvider.Get(questID)
  local state = QuestProvider.State(questID)
  local lines = {}
  local label = QuestProvider.StateLabel(state, entry)
  lines[#lines + 1] = string.format("%s [%s]%s%s", QuestProvider.Name(questID), label,
    entry and entry.level and (" - level " .. entry.level) or "", entry and entry.instance and (" - " .. entry.instance) or "")
  if entry and entry.pickup then lines[#lines + 1] = "  Pick up: " .. entry.pickup end
  if entry and entry.turnin then lines[#lines + 1] = "  Turn in: " .. entry.turnin end
  if entry and entry.objective then lines[#lines + 1] = "  " .. entry.objective end
  if state.inLog and #state.objectives > 0 then lines[#lines + 1] = "  Progress: " .. QuestProvider.ObjectiveText(state) end
  for _, link in ipairs(entry and entry.chain or {}) do
    local id = tonumber(link.id)
    lines[#lines + 1] = string.format("  Requires: %s%s", link.name or ("quest " .. tostring(link.id)), id and QuestProvider.State(id).completed and " (done)" or "")
  end
  if entry and #entry.rewards > 0 then
    local parts = {}
    for _, reward in ipairs(entry.rewards) do parts[#parts + 1] = (reward.count and reward.count > 1 and (reward.count .. " x ") or "") .. (reward.name or nameOf(reward.itemID)) end
    lines[#lines + 1] = string.format("  Reward%s: %s", entry.rewardChoice and " (choose one)" or "s", table.concat(parts, ", "))
  end
  return lines
end

local function changed(reason)
  QuestProvider.logCache = nil
  Events.Debounce("quests-updated", 0.5, function()
    Events.Fire("FP_QUESTS_UPDATED", reason)
  end)
end

function QuestProvider.Init()
  if not QuestProvider.IsAvailable() then
    Log.Debug("C_QuestLog missing; quest provider disabled")
    return
  end
  for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE" }) do
    Events.RegisterWoW(event, function() changed(event) end)
  end
  Events.RegisterWoW("QUEST_DATA_LOAD_RESULT", function(questID, success)
    local ql = questLog()
    if success and ql and tonumber(questID) then
      local title = call(ql.GetTitleForQuestID, questID)
      if type(title) == "string" and title ~= "" then
        QuestProvider.titles[tonumber(questID)] = title
        changed("title")
      end
    end
  end)
  Events.On("FP_READY", function() QuestProvider.Invalidate() end)
end
