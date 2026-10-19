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
-- Classic-era quests (CMaNGOS classic-db, Providers/ClassicDBProvider.lua)
-- are the baseline under all of it: Get() falls back to them, and givers,
-- turn-ins, required items, rewards and prerequisite chains come from them
-- when nothing Forever-specific knows the quest.
-- Questlines (the chain of steps that leads to a quest) come from Attune's
-- attunement and class-quest chains, else the classic prerequisites; quest givers, turn-ins and the items a
-- quest asks for from Providers/QuestFactsProvider.lua (shipped catalogue +
-- what this account has learned at quest windows).
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
  if ns.ReputationProvider then ns.ReputationProvider.questRewards = nil end
end

-- The curated entry (journal, Attune), else the classic one.
function QuestProvider.Get(questID)
  questID = tonumber(questID) or 0
  local entry = QuestProvider.Index()[questID]
  if entry then return entry end
  local CDB = ns.ClassicDB
  return CDB and CDB.Quest(questID) or nil
end

function QuestProvider.Classic(questID)
  local CDB = ns.ClassicDB
  return CDB and CDB.Quest(tonumber(questID) or 0) or nil
end

-- Can this character take the quest? Curated entries check their faction;
-- classic entries also their class.
function QuestProvider.Eligible(entry)
  if not entry then return false end
  local faction = QuestProvider.Faction()
  if entry.faction and entry.faction ~= "Both" and faction and entry.faction ~= faction then return false end
  if entry.classic and ns.ClassicDB then return ns.ClassicDB.Eligible(entry.id) end
  return true
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
  local out, seen = {}, {}
  for _, entry in pairs(QuestProvider.Index()) do
    for _, reward in ipairs(entry.rewards or {}) do
      if reward.itemID == itemID then out[#out + 1] = entry seen[entry.id] = true break end
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  -- Classic quests (this character's faction and class) after the curated ones.
  local CDB = ns.ClassicDB
  if CDB and CDB.IsAvailable() then
    for _, entry in ipairs(CDB.QuestsRewarding(itemID)) do
      if not seen[entry.id] then out[#out + 1] = entry end
    end
  end
  return out
end

-- Which quests feed open goals: { [questID] = { entry, goals = { { goal, name,
-- itemID, count } | { goal, name, reputation, faction } } } }, from the
-- missing leaves of each goal's tree (quest rewards) and, for reputation
-- goals, every open quest that gives reputation with the faction.
-- views: goalID -> view.
function QuestProvider.FeedsGoals(goals, views, nameOf)
  local feeds = {}
  local function feedFor(entry)
    local feed = feeds[entry.id]
    if not feed then
      feed = { entry = entry, goals = {} }
      feeds[entry.id] = feed
    end
    return feed
  end
  for _, goal in ipairs(goals or {}) do
    local view = views and views[goal.id]
    local name = nameOf and nameOf(goal) or goal.id
    if goal.type == "REACH_REPUTATION" and goal.target then
      local quests = view and view.reputation and view.reputation.quests
      if not quests and ns.ReputationProvider and ns.ReputationProvider.QuestsFor then
        local ok, list = pcall(ns.ReputationProvider.QuestsFor, goal.target.name, goal.target.factionID)
        quests = ok and list or nil
      end
      for _, quest in ipairs(quests or {}) do
        if quest.entry and not (quest.state and quest.state.completed) then
          local feed = feedFor(quest.entry)
          feed.goals[#feed.goals + 1] = { goal = goal, name = name, reputation = quest.amount, faction = goal.target.name }
        end
      end
    else
      local leaves = view and view.tree and view.tree.summary and view.tree.summary.missingLeaves or {}
      for _, leaf in ipairs(leaves) do
        if leaf.itemID then
          for _, entry in ipairs(QuestProvider.QuestsRewarding(leaf.itemID)) do
            local feed = feedFor(entry)
            feed.goals[#feed.goals + 1] = { goal = goal, name = name, itemID = leaf.itemID, count = leaf.count }
          end
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
  local CDB = ns.ClassicDB
  if CDB and CDB.IsAvailable() then
    for _, questID in ipairs(CDB.Search(needle)) do
      if not seen[questID] then
        local entry = CDB.Quest(questID)
        consider(questID, entry.name, (entry.location or "Classic") .. (entry.level and (" - level " .. entry.level) or ""))
      end
    end
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
  -- Classic prerequisites: every group needs one completed member.
  for _, group in ipairs(entry and entry.prerequisites or {}) do
    local met = false
    for _, id in ipairs(group) do
      if QuestProvider.State(id).completed then met = true break end
    end
    if not met then return "Locked", "text" end
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
  local QF = ns.QuestFactsProvider
  local CDB = ns.ClassicDB
  local classic = CDB and CDB.IsAvailable() and select(1, CDB.Counts()) or 0
  return string.format("Quests: %d known from %s%s; quest log %d / %d; givers and items recorded for %d quests.", QuestProvider.Count(),
    #sources > 0 and table.concat(sources, " and ") or "no data addon", classic > 0 and string.format(", plus %d classic quests", classic) or "",
    numQuests, max, QF and (QF.Count() + QF.ShippedCount()) or 0)
end

---------------------------------------------------------------------------
-- Questlines, givers and required items
---------------------------------------------------------------------------
local QUEST_STEP = { Quest = true, ["Pick Up"] = true, ["Turn In"] = true }
QuestProvider.QUEST_STEP = QUEST_STEP

local function firstQuestID(step)
  return tonumber(string.match(tostring(step.wowheadID or ""), "^(%d+)"))
end

-- The attunement or class-quest chain (Attune) that leads to questID for
-- this faction and class, each quest step carrying its entry and live
-- state: { attune, steps, target, next, done, total, percent, complete }.
-- nil when no chain includes the quest.
-- The chain of classic prerequisites that leads to questID, in the same
-- shape as an Attune questline; nil when the quest has none.
function QuestProvider.ClassicQuestline(questID)
  local CDB = ns.ClassicDB
  questID = tonumber(questID)
  if not (CDB and CDB.IsAvailable() and questID and CDB.Quest(questID)) then return nil end
  local order, follows = CDB.ChainTo(questID, function(id) return QuestProvider.State(id).completed end)
  if #order < 2 then return nil end
  local target = CDB.Quest(questID)
  local line = { attune = { id = "classic:" .. questID, name = target.name .. " chain", classic = true }, steps = {}, done = 0, total = #order, classic = true }
  local done = {}
  for index, id in ipairs(order) do
    local entry = QuestProvider.Get(id)
    local state = QuestProvider.State(id)
    local giver = QuestProvider.Giver(id)
    local step = {
      key = "classic-" .. id, id = tostring(id), attuneID = line.attune.id, type = "Quest", typeLabel = "Quest",
      name = entry and entry.name or QuestProvider.Name(id), location = (giver and giver.zone) or (entry and entry.location) or nil,
      wowheadID = tostring(id), icon = QuestProvider.ICON, follows = {}, stage = index, count = 1, side = false,
      questID = id, entry = entry, questState = state, done = state.completed, classic = true,
    }
    for _, f in ipairs(follows[id] or {}) do step.follows[#step.follows + 1] = tostring(f) end
    done[id] = step.done
    line.steps[index] = step
    if step.done then line.done = line.done + 1 end
  end
  for _, step in ipairs(line.steps) do
    if step.done then
      step.state = "done"
    else
      local ready = true
      for _, f in ipairs(follows[step.questID] or {}) do
        if not done[f] then ready = false end
      end
      step.state = ready and "current" or "locked"
      if ready and not line.next then line.next = step end
    end
  end
  line.target = line.steps[#line.steps]
  line.complete = line.target.done
  line.percent = line.total > 0 and math.floor(line.done * 100 / line.total + 0.5) or 0
  if line.complete then line.percent = 100 end
  return line
end

function QuestProvider.Questline(questID)
  local AP = ns.AttuneProvider
  local line
  if AP and AP.IsAvailable and AP.IsAvailable() and AP.QuestlineFor then
    local ok, result = pcall(AP.QuestlineFor, tonumber(questID))
    if ok and type(result) == "table" then line = result end
  end
  if not line then
    -- A journal chain is Forever-curated: it wins over the classic one.
    local entry = QuestProvider.Index()[tonumber(questID) or 0]
    if entry and entry.chain then return nil end
    return QuestProvider.ClassicQuestline(questID)
  end
  for _, step in ipairs(line.steps) do
    if QUEST_STEP[step.type] then
      step.questID = firstQuestID(step)
      if step.questID then
        step.entry = QuestProvider.Get(step.questID)
        step.questState = QuestProvider.State(step.questID)
      end
    end
  end
  return line
end

function QuestProvider.Facts(questID)
  local QF = ns.QuestFactsProvider
  return QF and QF.Get(questID) or nil
end

-- Map coordinates arrive as 0-1 fractions (journal, learned) or percent (Attune).
local function fraction(v)
  v = tonumber(v)
  if not v then return nil end
  if v > 1 then return v / 100 end
  return v
end

local function placeOf(p)
  return { name = p.name, mapID = p.mapID, x = fraction(p.x), y = fraction(p.y), zone = p.zone, subzone = p.subzone,
    label = p.name .. (p.zone and (" - " .. p.zone) or "") }
end

-- Where a quest starts: { name, mapID, x, y, zone, label } from learned or
-- shipped facts, else the journal/Attune start pin, else the pickup text.
function QuestProvider.Giver(questID)
  local facts = QuestProvider.Facts(questID)
  if facts and facts.giver and facts.giver.name then return placeOf(facts.giver) end
  local entry = QuestProvider.Get(questID)
  if entry and entry.start then
    local s = entry.start
    local name = s.target or (s.label and (s.label:match("^([^%-]+)") or s.label):gsub("%s+$", "")) or entry.pickup
    return { name = name, mapID = s.mapID, x = fraction(s.x), y = fraction(s.y), zone = entry.location, label = s.label or name }
  end
  local CDB = ns.ClassicDB
  local classic = CDB and CDB.IsAvailable() and CDB.Giver(questID) or nil
  if entry and entry.pickup and not entry.classic then
    local name = entry.pickup:match("^([^,]+)") or entry.pickup
    -- The journal names the giver; the classic spawn gives the position when it is the same NPC.
    if classic and classic.mapID and string.lower(classic.name or "") == string.lower(name) then
      classic.label = entry.pickup
      return classic
    end
    return { name = name, zone = entry.location, label = entry.pickup }
  end
  return classic
end

function QuestProvider.Turnin(questID)
  local facts = QuestProvider.Facts(questID)
  if facts and facts.turnin and facts.turnin.name then return placeOf(facts.turnin) end
  local entry = QuestProvider.Get(questID)
  local CDB = ns.ClassicDB
  local classic = CDB and CDB.IsAvailable() and CDB.Turnin(questID) or nil
  if entry and entry.turnin and not entry.classic then
    local name = entry.turnin:match("^([^,]+)") or entry.turnin
    if classic and classic.mapID and string.lower(classic.name or "") == string.lower(name) then
      classic.label = entry.turnin
      return classic
    end
    return { name = name, zone = entry.location, label = entry.turnin }
  end
  return classic
end

-- Items a quest asks for: live objectives while it is in the log, else the
-- recorded facts. { { name, count, have, itemID } }
function QuestProvider.RequiredItems(questID)
  local QF = ns.QuestFactsProvider
  local state = QuestProvider.State(questID)
  if state.inLog and QF then
    local live = QF.LiveItems(questID)
    if #live > 0 then return live end
  end
  local facts = QuestProvider.Facts(questID)
  local out = {}
  for _, item in ipairs(facts and facts.items or {}) do
    out[#out + 1] = { name = item.name, count = item.count or 1, have = 0, itemID = item.itemID, source = item.source }
  end
  if #out == 0 and not (facts and facts.items and #facts.items == 0 and facts.learned) then
    local CDB = ns.ClassicDB
    for _, item in ipairs(CDB and CDB.IsAvailable() and CDB.RequiredItems(questID) or {}) do
      out[#out + 1] = { count = item.count or 1, have = 0, itemID = item.itemID, classic = true }
    end
  end
  return out
end

-- The place to go next for a quest: its turn-in once it is ready, its
-- giver while it is not yet taken; nil while objectives are in progress or
-- when no map position is recorded. { mapID, x, y, label, name, zone }
function QuestProvider.Waypoint(questID)
  local state = QuestProvider.State(questID)
  if state.completed then return nil end
  local where
  if state.ready then where = QuestProvider.Turnin(questID)
  elseif not state.inLog then where = QuestProvider.Giver(questID) end
  if where and where.mapID and where.x and where.y then return where end
  return nil
end

-- Places the client's map waypoint at a recorded position. Returns ok, message.
function QuestProvider.SetWaypoint(point)
  if type(point) ~= "table" then return false, "No map position recorded for this step yet." end
  local ok, reason = Compat.SetWaypoint(point.mapID, point.x, point.y)
  if ok then return true, string.format("Waypoint set: %s.", point.label or point.name or "quest") end
  return false, reason
end

-- Chat lines for one quest.
function QuestProvider.Describe(questID, nameOf)
  nameOf = nameOf or function(id) return "Item " .. tostring(id) end
  local entry = QuestProvider.Get(questID)
  local state = QuestProvider.State(questID)
  local lines = {}
  local label = QuestProvider.StateLabel(state, entry)
  lines[#lines + 1] = string.format("%s [%s]%s%s%s", QuestProvider.Name(questID), label,
    entry and entry.level and (" - level " .. entry.level) or "", entry and entry.instance and (" - " .. entry.instance) or "",
    entry and entry.classic and " (classic data)" or "")
  if entry and entry.pickup then lines[#lines + 1] = "  Pick up: " .. entry.pickup end
  if entry and entry.turnin then lines[#lines + 1] = "  Turn in: " .. entry.turnin end
  if entry and entry.objective then lines[#lines + 1] = "  " .. entry.objective end
  if state.inLog and #state.objectives > 0 then lines[#lines + 1] = "  Progress: " .. QuestProvider.ObjectiveText(state) end
  for _, link in ipairs(entry and entry.chain or {}) do
    local id = tonumber(link.id)
    lines[#lines + 1] = string.format("  Requires: %s%s", link.name or ("quest " .. tostring(link.id)), id and QuestProvider.State(id).completed and " (done)" or "")
  end
  local giver = QuestProvider.Giver(questID)
  if giver and not (entry and entry.pickup) then lines[#lines + 1] = "  Pick up: " .. giver.label end
  local turnin = QuestProvider.Turnin(questID)
  if turnin and not (entry and entry.turnin) then lines[#lines + 1] = "  Turn in: " .. turnin.label end
  for _, item in ipairs(QuestProvider.RequiredItems(questID)) do
    lines[#lines + 1] = string.format("  Needs: %d x %s%s", item.count, item.name or (item.itemID and nameOf(item.itemID)) or "?", item.have > 0 and string.format(" (%d/%d)", item.have, item.count) or "")
  end
  local line = QuestProvider.Questline(questID)
  if line then
    lines[#lines + 1] = string.format("  Chain: %s - %d of %d steps done", line.attune.name, line.done, line.total)
    for index, step in ipairs(line.steps) do
      lines[#lines + 1] = string.format("    %d. [%s] %s: %s%s", index, step.done and "x" or (step.state == "current" and ">" or " "), step.typeLabel, step.name,
        step.location and (" - " .. step.location) or "")
    end
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
