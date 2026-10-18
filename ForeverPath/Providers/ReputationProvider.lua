-- Reputations: the player's standing with every faction (C_Reputation, or
-- the legacy GetFactionInfo), the standing thresholds, and the ways to earn
-- it that other addons know: dungeon quests that reward reputation
-- (ForeverDungeonJournal's reward texts) and the items each standing unlocks
-- (AtlasLootClassic_Factions, loaded on demand). Factions the character has
-- not met yet come from the client's own faction table in the catalogue
-- (Data/RecipeCatalogue.lua), at the starting standing for the character's
-- race and class.
local _, ns = ...

local Util = ns.Util
local Log = ns.Log
local Events = ns.Events

local ReputationProvider = { cache = nil, atlas = { state = "idle", tiers = {}, byItem = nil }, MODULE = "AtlasLootClassic_Factions" }
ns.ReputationProvider = ReputationProvider

ReputationProvider.ICON = "Interface\\Icons\\Achievement_Reputation_01"
ReputationProvider.Labels = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
-- Absolute reputation at which each standing starts, and the top of Exalted.
ReputationProvider.StandingMin = { [1] = -42000, [2] = -6000, [3] = -3000, [4] = 0, [5] = 3000, [6] = 9000, [7] = 21000, [8] = 42000 }
ReputationProvider.StandingMax = { [1] = -6000, [2] = -3000, [3] = 0, [4] = 3000, [5] = 9000, [6] = 21000, [7] = 42000, [8] = 42999 }
ReputationProvider.StandingColor = { [1] = "missing", [2] = "missing", [3] = "partial", [4] = "text2", [5] = "ok", [6] = "info", [7] = "gold", [8] = "goldLight" }

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n = pcall(fn, ...)
  if ok then return a, b, c, d, e, f, g, h, i, j, k, l, m, n end
  return nil
end

local function cRep()
  return type(C_Reputation) == "table" and C_Reputation or nil
end

function ReputationProvider.IsAvailable()
  local c = cRep()
  return (c and type(c.GetFactionDataByIndex) == "function") or type(_G.GetFactionInfo) == "function"
end

function ReputationProvider.StandingLabel(standing)
  standing = tonumber(standing)
  if not standing then return "?" end
  local global = _G["FACTION_STANDING_LABEL" .. standing]
  if type(global) == "string" and global ~= "" then return global end
  return ReputationProvider.Labels[standing] or ("Standing " .. standing)
end

-- 1..8 from a standing name (prefix, case-insensitive), or nil.
function ReputationProvider.StandingByName(text)
  if type(text) ~= "string" then return nil end
  local wanted = string.lower(Util.Trim(text))
  if wanted == "" then return nil end
  for standing = 1, 8 do
    local names = { string.lower(ReputationProvider.Labels[standing]), string.lower(ReputationProvider.StandingLabel(standing)) }
    for _, name in ipairs(names) do
      if name == wanted or name:sub(1, #wanted) == wanted then return standing end
    end
  end
  return nil
end

-- Standing (1..8) for an absolute reputation value.
function ReputationProvider.StandingFor(value)
  value = tonumber(value) or 0
  local standing = 1
  for s = 1, 8 do
    if value >= ReputationProvider.StandingMin[s] then standing = s end
  end
  return standing
end

-- Normalises one faction row from either API.
local function normalize(data, legacy)
  local record
  if type(data) == "table" then
    record = {
      name = data.name, factionID = tonumber(data.factionID), standing = tonumber(data.reaction) or tonumber(data.standingID),
      value = tonumber(data.currentStanding) or tonumber(data.barValue), min = tonumber(data.currentReactionThreshold) or tonumber(data.barMin),
      max = tonumber(data.nextReactionThreshold) or tonumber(data.barMax), isHeader = data.isHeader == true, isCollapsed = data.isCollapsed == true,
      hasRep = data.isHeaderWithRep == true or data.hasRep == true, atWar = data.atWarWith == true or data.atWar == true, isWatched = data.isWatched == true,
      description = data.description,
    }
  elseif type(legacy) == "table" then
    local name, description, standingID, barMin, barMax, barValue, atWar, _, isHeader, isCollapsed, hasRep, isWatched, _, factionID = unpack(legacy)
    record = { name = name, factionID = tonumber(factionID), standing = tonumber(standingID), value = tonumber(barValue), min = tonumber(barMin), max = tonumber(barMax),
      isHeader = isHeader == true, isCollapsed = isCollapsed == true, hasRep = hasRep == true, atWar = atWar == true, isWatched = isWatched == true, description = description }
  end
  if not record or type(record.name) ~= "string" then return nil end
  if not record.standing and record.value then record.standing = ReputationProvider.StandingFor(record.value) end
  record.standing = record.standing or 4
  record.value = record.value or ReputationProvider.StandingMin[record.standing]
  record.min = record.min or ReputationProvider.StandingMin[record.standing]
  record.max = record.max or ReputationProvider.StandingMax[record.standing]
  record.standingLabel = ReputationProvider.StandingLabel(record.standing)
  local span = (record.max or 0) - (record.min or 0)
  record.into = (record.value or 0) - (record.min or 0)
  record.span = span
  record.percentWithin = span > 0 and math.floor(math.max(0, math.min(1, record.into / span)) * 100 + 0.5) or 100
  return record
end

local function readIndex(i)
  local c = cRep()
  if c and type(c.GetFactionDataByIndex) == "function" then
    return normalize(call(c.GetFactionDataByIndex, i))
  end
  if type(_G.GetFactionInfo) == "function" then
    local results = { call(_G.GetFactionInfo, i) }
    if results[1] ~= nil then return normalize(nil, results) end
  end
  return nil
end

local function countFactions()
  local c = cRep()
  local n = c and call(c.GetNumFactions) or nil
  if not tonumber(n) and type(_G.GetNumFactions) == "function" then n = call(_G.GetNumFactions) end
  return tonumber(n) or 0
end

-- Every faction with a standing, in the client's order, each with its
-- header (group) name: { factionID, name, standing, standingLabel, value,
-- min, max, into, span, percentWithin, header, atWar, isWatched }.
function ReputationProvider.List()
  if ReputationProvider.cache then return ReputationProvider.cache end
  local list, header = {}, nil
  for i = 1, countFactions() do
    local record = readIndex(i)
    if record then
      if record.isHeader and not record.hasRep then
        header = record.name
      else
        if record.isHeader then header = record.name end
        record.header = header
        if record.factionID or record.value then list[#list + 1] = record end
      end
    end
  end
  ReputationProvider.cache = list
  return list
end

function ReputationProvider.Invalidate()
  ReputationProvider.cache = nil
end

---------------------------------------------------------------------------
-- Unmet factions: the client's faction table
---------------------------------------------------------------------------
local function catalogueFactions()
  local c = ns.Data and ns.Data.Catalogue
  return c and type(c.factions) == "table" and c.factions or nil
end

-- Bit `index` (0-based) of a 64-bit mask stored as two 32-bit halves.
local function hasBit(low, high, index)
  local word, bitIndex = tonumber(low) or 0, index
  if index >= 32 then word, bitIndex = tonumber(high) or 0, index - 32 end
  return math.floor(word / 2 ^ bitIndex) % 2 == 1
end

-- The character's race and class ids (the third returns of UnitRace / UnitClass).
function ReputationProvider.PlayerIDs()
  local raceID = select(3, call(_G.UnitRace, "player"))
  local classID = select(3, call(_G.UnitClass, "player"))
  return tonumber(raceID), tonumber(classID)
end

-- Starting reputation with a catalogue faction row for a race and class:
-- the first slot whose race mask includes the race and whose class mask is
-- 0 or includes the class (the client's own rule); 0 when none matches.
function ReputationProvider.StartingValue(row, raceID, classID)
  local slots = type(row) == "table" and row[5] or {}
  for i = 1, #slots, 4 do
    local low, high, classMask, base = slots[i], slots[i + 1], slots[i + 2], slots[i + 3]
    local raceOK = raceID ~= nil and hasBit(low, high, raceID - 1)
    local classOK = (tonumber(classMask) or 0) == 0 or (classID ~= nil and hasBit(classMask, 0, classID - 1))
    if raceOK and classOK then return tonumber(base) or 0 end
  end
  return 0
end

function ReputationProvider.CatalogueCount()
  local count = 0
  for _ in pairs(catalogueFactions() or {}) do count = count + 1 end
  return count
end

-- A faction the character has not met, from the catalogue: a record at its
-- starting standing with `unmet = true`; nil when the table lacks it.
function ReputationProvider.Unmet(factionID)
  local rows = catalogueFactions()
  factionID = tonumber(factionID)
  local row = rows and factionID and rows[factionID] or nil
  if not row then return nil end
  local raceID, classID = ReputationProvider.PlayerIDs()
  local base = ReputationProvider.StartingValue(row, raceID, classID)
  local standing = ReputationProvider.StandingFor(base)
  local record = normalize({ name = row[1], factionID = factionID, reaction = standing, currentStanding = base,
    currentReactionThreshold = ReputationProvider.StandingMin[standing], nextReactionThreshold = ReputationProvider.StandingMax[standing] })
  if not record then return nil end
  record.unmet = true
  local parent = rows[row[2] or 0]
  record.header = parent and parent[1] or nil
  return record
end

-- One faction by id: the by-id API first, else the list.
function ReputationProvider.Get(factionID)
  factionID = tonumber(factionID)
  if not factionID then return nil end
  local c = cRep()
  if c and type(c.GetFactionDataByID) == "function" then
    local record = normalize(call(c.GetFactionDataByID, factionID))
    if record then
      record.factionID = record.factionID or factionID
      for _, listed in ipairs(ReputationProvider.List()) do
        if listed.factionID == factionID then record.header = listed.header end
      end
      return record
    end
  elseif type(_G.GetFactionInfoByID) == "function" then
    local results = { call(_G.GetFactionInfoByID, factionID) }
    if results[1] ~= nil then
      local record = normalize(nil, results)
      if record then record.factionID = record.factionID or factionID return record end
    end
  end
  for _, listed in ipairs(ReputationProvider.List()) do
    if listed.factionID == factionID then return listed end
  end
  return ReputationProvider.Unmet(factionID)
end

-- Factions by name: exact, then prefix, then substring.
function ReputationProvider.Search(text, limit)
  if type(text) ~= "string" then return {} end
  local needle = string.lower(Util.Trim(text))
  if needle == "" then return {} end
  local hits, seen = {}, {}
  for _, record in ipairs(ReputationProvider.List()) do
    local lower = string.lower(record.name)
    local position = lower:find(needle, 1, true)
    if position then
      hits[#hits + 1] = { factionID = record.factionID, name = record.name, record = record, rank = lower == needle and 0 or (position == 1 and 1 or 2) }
      if record.factionID then seen[record.factionID] = true end
    end
  end
  -- Factions not met yet, from the client's table.
  for factionID, row in pairs(catalogueFactions() or {}) do
    if not seen[factionID] and type(row[1]) == "string" then
      local lower = string.lower(row[1])
      local position = lower:find(needle, 1, true)
      if position then
        hits[#hits + 1] = { factionID = factionID, name = row[1], unmet = true, rank = lower == needle and 0 or (position == 1 and 1 or 2) }
      end
    end
  end
  table.sort(hits, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if (a.unmet or false) ~= (b.unmet or false) then return not a.unmet end
    return a.name < b.name
  end)
  if limit and #hits > limit then
    for i = #hits, limit + 1, -1 do hits[i] = nil end
  end
  return hits
end

-- Progress towards a standing: { record, target, targetLabel, targetMin, remaining, reached, percent }.
-- startValue (the value when the goal was made) anchors the percentage.
function ReputationProvider.Progress(factionID, target, startValue)
  local record = ReputationProvider.Get(factionID)
  if not record then return nil end
  target = tonumber(target) or 8
  local targetMin = ReputationProvider.StandingMin[target] or 42000
  local value = record.value or 0
  local reached = record.standing >= target or value >= targetMin
  local start = tonumber(startValue) or value
  if start > value then start = value end
  local percent
  if reached then percent = 100
  elseif targetMin > start then percent = math.floor(math.max(0, value - start) * 100 / (targetMin - start) + 0.5)
  else percent = 0 end
  return { record = record, target = target, targetLabel = ReputationProvider.StandingLabel(target), targetMin = targetMin,
    remaining = math.max(0, targetMin - value), reached = reached, percent = percent, start = start }
end

-- The next standing above the current one (Exalted at most).
function ReputationProvider.NextStanding(record)
  if not record then return 5 end
  return math.min(8, (record.standing or 4) + 1)
end

---------------------------------------------------------------------------
-- Ways to earn: quests (journal reward texts) and rewards (AtlasLoot factions)
---------------------------------------------------------------------------
-- { [factionName] = { { questID, amount, entry } } } from the journal's reward summaries.
function ReputationProvider.QuestRewards()
  if ReputationProvider.questRewards then return ReputationProvider.questRewards end
  local out = {}
  local QP = ns.QuestProvider
  if QP and QP.Index then
    for _, entry in pairs(QP.Index()) do
      local text = entry.rewardSummary or entry.rewardText or ""
      for faction, amount in tostring(text):gmatch("([%a' ]+) %+(%d+)") do
        faction = Util.Trim(faction)
        if faction ~= "" then
          local list = out[faction]
          if not list then list = {} out[faction] = list end
          list[#list + 1] = { questID = entry.id, amount = tonumber(amount), entry = entry }
        end
      end
    end
    for _, list in pairs(out) do
      table.sort(list, function(a, b)
        if a.amount ~= b.amount then return a.amount > b.amount end
        return a.questID < b.questID
      end)
    end
  end
  ReputationProvider.questRewards = out
  return out
end

-- Quests that reward reputation with a faction, each with its live state.
function ReputationProvider.QuestsFor(factionName)
  local list = ReputationProvider.QuestRewards()[factionName] or {}
  local QP = ns.QuestProvider
  local out = {}
  for _, source in ipairs(list) do
    local state = QP and QP.State(source.questID) or { completed = false, inLog = false }
    out[#out + 1] = { questID = source.questID, amount = source.amount, entry = source.entry, name = source.entry.name, state = state,
      label = QP and QP.StateLabel(state, source.entry) or "?" }
  end
  return out
end

function ReputationProvider.HasAtlasLoot()
  local atlas = _G.AtlasLoot
  return type(atlas) == "table" and type(atlas.ItemDB) == "table" and type(atlas.ItemDB.Storage) == "table"
end

local function tierStanding(name, position, count)
  for standing = 8, 1, -1 do
    local label = string.lower(ReputationProvider.StandingLabel(standing))
    if type(name) == "string" and string.lower(name) == label then return standing end
    if type(name) == "string" and string.lower(name) == string.lower(ReputationProvider.Labels[standing]) then return standing end
  end
  -- AtlasLoot lists tiers from Exalted downwards.
  return math.max(1, 8 - (position - 1))
end

-- Reads the loaded factions module into tiers[factionID] = { { standing, label, items } } and byItem.
function ReputationProvider.IndexAtlas()
  local storage = ReputationProvider.HasAtlasLoot() and _G.AtlasLoot.ItemDB.Storage[ReputationProvider.MODULE] or nil
  if type(storage) ~= "table" then return 0 end
  local tiers, byItem, added = {}, {}, 0
  for key, content in pairs(storage) do
    if type(key) == "string" and key ~= "__atlaslootdata" and type(content) == "table" and type(content.items) == "table" then
      local factionID = tonumber(content.FactionID)
      if factionID then
        local list = {}
        for position, tier in ipairs(content.items) do
          if type(tier) == "table" then
            local standing = tierStanding(tier.name, position, #content.items)
            local items = {}
            for dif, entries in pairs(tier) do
              if type(dif) == "number" and type(entries) == "table" then
                for _, entry in ipairs(entries) do
                  local itemID = type(entry) == "table" and entry[2] or nil
                  if type(itemID) == "number" and itemID > 0 then
                    items[#items + 1] = itemID
                    local list2 = byItem[itemID]
                    if not list2 then list2 = {} byItem[itemID] = list2 end
                    list2[#list2 + 1] = { factionID = factionID, standing = standing }
                    added = added + 1
                  end
                end
              end
            end
            list[#list + 1] = { standing = standing, label = ReputationProvider.StandingLabel(standing), items = items }
          end
        end
        table.sort(list, function(a, b) return a.standing < b.standing end)
        tiers[factionID] = list
      end
    end
  end
  ReputationProvider.atlas.tiers = tiers
  ReputationProvider.atlas.byItem = byItem
  return added
end

-- Loads the factions module once per session (on demand).
function ReputationProvider.EnsureAtlas()
  local atlas = ReputationProvider.atlas
  if atlas.state ~= "idle" or not ReputationProvider.HasAtlasLoot() then return atlas.state end
  atlas.state = "loading"
  local function finish()
    local ok, added = pcall(ReputationProvider.IndexAtlas)
    Log.Debug("Indexed AtlasLoot factions: %s", ok and tostring(added) or tostring(added))
    atlas.state = "ready"
    Events.Fire("FP_REPUTATION_UPDATED", "atlasloot")
  end
  local loader = _G.AtlasLoot.Loader
  local result
  if type(loader) == "table" and type(loader.LoadModule) == "function" then
    local ok, state = pcall(loader.LoadModule, loader, ReputationProvider.MODULE, finish, true)
    result = ok and state or nil
  end
  if result ~= true and result ~= "InCombat" then
    if type(_G.AtlasLoot.ItemDB.Storage[ReputationProvider.MODULE]) == "table" then finish() else atlas.state = "missing" end
  end
  return atlas.state
end

-- Rewards per standing for a faction: { { standing, label, items = { itemID } } } (ascending).
function ReputationProvider.Rewards(factionID)
  ReputationProvider.EnsureAtlas()
  return ReputationProvider.atlas.tiers[tonumber(factionID) or 0] or {}
end

-- Factions (and standings) that sell an item: { { factionID, standing } }.
function ReputationProvider.SoldBy(itemID)
  ReputationProvider.EnsureAtlas()
  return ReputationProvider.atlas.byItem and ReputationProvider.atlas.byItem[itemID] or {}
end

-- Resolver hints for an item sold by a reputation vendor: a vendor option
-- that is unavailable until the standing is reached.
function ReputationProvider.Hints(itemID)
  local out = {}
  for _, sale in ipairs(ReputationProvider.SoldBy(itemID)) do
    local record = ReputationProvider.Get(sale.factionID)
    local faction = record and record.name or ("faction " .. sale.factionID)
    local label = ReputationProvider.StandingLabel(sale.standing)
    local hint = { kind = "vendor", name = faction .. " quartermaster", label = "Reputation reward: " .. faction .. " (" .. label .. ")",
      detail = "Sold at " .. label .. " with " .. faction, faction = faction, factionID = sale.factionID, standing = sale.standing, reputation = true }
    if not record or (record.standing or 0) < sale.standing then
      hint.unavailable = true
      hint.reason = string.format("needs %s with %s%s", label, faction, record and ("; you are " .. record.standingLabel) or "")
      hint.detail = hint.detail .. " - " .. hint.reason
    end
    out[#out + 1] = hint
  end
  return out
end

function ReputationProvider.Status()
  if not ReputationProvider.IsAvailable() then
    return "Reputations: the faction API is unavailable on this client."
  end
  local list = ReputationProvider.List()
  local quests = 0
  for _, entries in pairs(ReputationProvider.QuestRewards()) do quests = quests + #entries end
  return string.format("Reputations: %d faction%s listed, %d in the client's faction table; %d quest reward%s known; faction rewards %s.", #list, #list == 1 and "" or "s",
    ReputationProvider.CatalogueCount(), quests, quests == 1 and "" or "s",
    ReputationProvider.HasAtlasLoot() and "from AtlasLoot" or "unavailable (AtlasLoot Factions not installed)")
end

-- Chat lines for one faction.
function ReputationProvider.Describe(factionID, nameOf)
  nameOf = nameOf or function(id) return "Item " .. tostring(id) end
  local record = ReputationProvider.Get(factionID)
  if not record then return { "Unknown faction " .. tostring(factionID) } end
  local lines = { string.format("%s: %s (%d / %d into it)", record.name, record.standingLabel, record.into or 0, record.span or 0) }
  for _, quest in ipairs(ReputationProvider.QuestsFor(record.name)) do
    lines[#lines + 1] = string.format("  Quest %s: +%d [%s]", quest.name, quest.amount, quest.label)
  end
  for _, tier in ipairs(ReputationProvider.Rewards(factionID)) do
    local names = {}
    for i, itemID in ipairs(tier.items) do
      if i > 4 then names[#names + 1] = string.format("+%d more", #tier.items - 4) break end
      names[#names + 1] = nameOf(itemID)
    end
    lines[#lines + 1] = string.format("  %s unlocks: %s", tier.label, table.concat(names, ", "))
  end
  return lines
end

local function changed(reason)
  ReputationProvider.cache = nil
  Events.Debounce("reputation-updated", 0.5, function()
    Events.Fire("FP_REPUTATION_UPDATED", reason)
  end)
end

function ReputationProvider.Init()
  if not ReputationProvider.IsAvailable() then
    Log.Debug("Faction API missing; reputation provider disabled")
    return
  end
  Events.RegisterWoW("UPDATE_FACTION", function() changed("faction") end)
  Events.On("FP_QUESTS_UPDATED", function() ReputationProvider.questRewards = nil end)
  Events.On("FP_READY", function() ReputationProvider.cache = nil ReputationProvider.questRewards = nil end)
end
