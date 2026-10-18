-- Quest facts: who gives a quest, where, who takes it back, and which items
-- it asks for. The client only hands addons a quest's text while it is in
-- the log or its giver window is open, and never says where an unaccepted
-- quest starts, so two sources fill the gap:
--   * Data/QuestCatalogue.lua, shipped with the addon (curated chains).
--   * ForeverPathDB.questFacts, learned on this account: the giver's name
--     and the player's map position when a quest window opens (QUEST_DETAIL),
--     the item objectives when it is accepted (QUEST_ACCEPTED), and the
--     turn-in NPC at the reward window (QUEST_COMPLETE). Shared by every
--     character on the account.
-- Facts: { giver = { name, mapID, x, y, zone, subzone, seenAt },
--          turnin = { name, mapID, x, y, zone, subzone, seenAt },
--          items = { { name, count, itemID } }, itemsAt }
-- Map positions are 0-1 fractions of the zone map (uiMapID).
local _, ns = ...

local Compat = ns.Compat
local Log = ns.Log
local Events = ns.Events

local QuestFacts = { pending = {}, learnedThisSession = 0 }
ns.QuestFactsProvider = QuestFacts

QuestFacts.RETRY_LIMIT = 20

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
  return nil
end

function QuestFacts.Store()
  if not ns.db then return nil end
  ns.db.questFacts = ns.db.questFacts or {}
  return ns.db.questFacts
end

function QuestFacts.Shipped(questID)
  local catalogue = ns.Data and ns.Data.QuestCatalogue
  if type(catalogue) ~= "table" then return nil end
  local entry = catalogue[tonumber(questID) or 0]
  return type(entry) == "table" and entry or nil
end

function QuestFacts.Learned(questID)
  local store = QuestFacts.Store()
  local entry = store and store[tonumber(questID) or 0]
  return type(entry) == "table" and entry or nil
end

local function copyPlace(place)
  if type(place) ~= "table" then return nil end
  return { name = place.name, mapID = tonumber(place.mapID), x = tonumber(place.x), y = tonumber(place.y), zone = place.zone, subzone = place.subzone, seenAt = place.seenAt }
end

local function allResolved(items)
  if type(items) ~= "table" or #items == 0 then return false end
  for _, item in ipairs(items) do
    if not tonumber(item.itemID) then return false end
  end
  return true
end

-- Shipped and learned facts merged: a learned position wins (it was seen on
-- this build), item lists prefer whichever has every item id resolved.
function QuestFacts.Get(questID)
  local shipped, learned = QuestFacts.Shipped(questID), QuestFacts.Learned(questID)
  if not shipped and not learned then return nil end
  local out = {}
  out.giver = copyPlace(learned and learned.giver) or copyPlace(shipped and shipped.giver)
  out.turnin = copyPlace(learned and learned.turnin) or copyPlace(shipped and shipped.turnin)
  local items
  if learned and allResolved(learned.items) then items = learned.items
  elseif shipped and type(shipped.items) == "table" and #shipped.items > 0 then items = shipped.items
  elseif learned and type(learned.items) == "table" then items = learned.items end
  out.items = {}
  for _, item in ipairs(items or {}) do
    out.items[#out.items + 1] = { name = item.name, count = tonumber(item.count) or 1, itemID = tonumber(item.itemID), source = item.source }
  end
  out.note = (learned and learned.note) or (shipped and shipped.note) or nil
  out.learned = learned ~= nil
  out.shipped = shipped ~= nil
  return out
end

-- Where the catalogue says a quest item comes from, as source hints for
-- the resolver: { { kind = "drop", label, detail, questID, quest } }.
local hintIndex
function QuestFacts.ItemHints(itemID)
  itemID = tonumber(itemID)
  if not itemID then return {} end
  if not hintIndex then
    hintIndex = {}
    local catalogue = ns.Data and ns.Data.QuestCatalogue
    for questID, row in pairs(type(catalogue) == "table" and catalogue or {}) do
      for _, item in ipairs(type(row.items) == "table" and row.items or {}) do
        local id = tonumber(item.itemID)
        if id and type(item.source) == "string" and item.source ~= "" then
          hintIndex[id] = hintIndex[id] or {}
          local list = hintIndex[id]
          -- One hint per source text, attributed to the lowest quest id (both factions share the totems).
          local existing
          for _, e in ipairs(list) do
            if e.source == item.source then existing = e end
          end
          if existing then
            if questID < existing.questID then existing.questID = questID end
          else
            list[#list + 1] = { source = item.source, questID = questID }
          end
        end
      end
    end
  end
  local out = {}
  for _, entry in ipairs(hintIndex[itemID] or {}) do
    local QP = ns.QuestProvider
    local questName = QP and QP.Name and QP.Name(entry.questID) or ("Quest " .. tostring(entry.questID))
    out[#out + 1] = {
      kind = "drop", questItem = true, questID = entry.questID, quest = questName,
      label = "Drop: " .. entry.source,
      short = "Drop: " .. (entry.source:match("^([^,]+)") or entry.source),
      detail = entry.source .. " - for " .. questName .. " (quest catalogue)",
    }
  end
  return out
end

---------------------------------------------------------------------------
-- Objective parsing
---------------------------------------------------------------------------
-- "Twisted Fire Totem: 0/5", "0/5 Twisted Fire Totem" or "Deviate Dreadfang
-- slain: 0/7" -> name, have, need, kill. Pure.
function QuestFacts.ParseObjective(text)
  if type(text) ~= "string" then return nil end
  local name, have, need
  local a, b, rest = text:match("^%s*(%d+)%s*/%s*(%d+)%s+(.-)%s*$")
  if a then
    have, need, name = tonumber(a), tonumber(b), rest
  else
    local head, c, d = text:match("^(.-)%s*:%s*(%d+)%s*/%s*(%d+)%s*$")
    if head then
      name, have, need = head, tonumber(c), tonumber(d)
    else
      name = text:match("^%s*(.-)%s*$")
    end
  end
  if not name or name == "" then return nil end
  local kill = false
  local stripped = name:gsub("%s+[Ss]lain$", ""):gsub("%s+[Kk]illed$", "")
  if stripped ~= name then kill = true name = stripped end
  return name, have, need, kill
end

-- The item id for a name the client has shown us (exact match only).
function QuestFacts.ItemIDByName(name)
  local IP = ns.ItemProvider
  if not IP or not IP.SearchByName or type(name) ~= "string" then return nil end
  local ok, hits = pcall(IP.SearchByName, name, 3)
  if not ok or type(hits) ~= "table" then return nil end
  for _, hit in ipairs(hits) do
    if hit.rank == 0 then return hit.itemID end
  end
  return nil
end

-- Asks the client for the name of everything in the bags, so objective
-- names resolve to ids once the item has dropped.
function QuestFacts.ScanBagNames()
  local IP = ns.ItemProvider
  if not (IP and Compat.GetContainerNumSlots and Compat.GetContainerSlot) then return 0 end
  local seen = 0
  for bag = 0, (Compat.numBagSlots or 4) + (Compat.numReagentBagSlots or 0) do
    local slots = call(Compat.GetContainerNumSlots, bag)
    for slot = 1, tonumber(slots) or 0 do
      local itemID = call(Compat.GetContainerSlot, bag, slot)
      if itemID then
        IP.GetItem(itemID)
        seen = seen + 1
      end
    end
  end
  return seen
end

-- Item objectives of a quest in the log: { { name, count, have, itemID } }.
-- Objectives the client types as items count; untyped ones only when the
-- name is a known item (kill counters never are).
function QuestFacts.LiveItems(questID)
  local ql = _G.C_QuestLog
  local objectives = ql and call(ql.GetQuestObjectives, questID) or nil
  local out = {}
  for _, o in ipairs(type(objectives) == "table" and objectives or {}) do
    if type(o) == "table" and (tonumber(o.numRequired) or 0) > 0 and (o.type == nil or o.type == "item") then
      local name, _, _, kill = QuestFacts.ParseObjective(o.text)
      if name and not kill then
        local itemID = QuestFacts.ItemIDByName(name)
        if o.type == "item" or itemID then
          out[#out + 1] = { name = name, count = tonumber(o.numRequired) or 1, have = tonumber(o.numFulfilled) or 0, itemID = itemID }
        end
      end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Learning
---------------------------------------------------------------------------
local function place(name)
  local mapID, x, y = Compat.PlayerPosition()
  local zone = call(_G.GetZoneText)
  local sub = call(_G.GetSubZoneText)
  return {
    name = name, mapID = mapID, x = x and math.floor(x * 10000 + 0.5) / 10000 or nil, y = y and math.floor(y * 10000 + 0.5) / 10000 or nil,
    zone = type(zone) == "string" and zone ~= "" and zone or nil, subzone = type(sub) == "string" and sub ~= "" and sub or nil,
    seenAt = ns.Util.Now(),
  }
end

local function npcName()
  local name = call(_G.UnitName, "questnpc")
  if type(name) ~= "string" or name == "" then name = call(_G.UnitName, "npc") end
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

local function entryFor(questID)
  local store = QuestFacts.Store()
  if not store then return nil end
  store[questID] = store[questID] or {}
  return store[questID]
end

local function changed()
  QuestFacts.learnedThisSession = QuestFacts.learnedThisSession + 1
  Events.Debounce("quest-facts", 0.5, function() Events.Fire("FP_QUEST_FACTS_UPDATED") end)
end

function QuestFacts.RecordGiver(questID, name)
  questID = tonumber(questID)
  if not questID or questID <= 0 or not name then return false end
  local entry = entryFor(questID)
  if not entry then return false end
  entry.giver = place(name)
  Log.Debug("Quest %d is given by %s at %s %.2f,%.2f", questID, name, tostring(entry.giver.mapID), (entry.giver.x or 0) * 100, (entry.giver.y or 0) * 100)
  changed()
  return true
end

function QuestFacts.RecordTurnin(questID, name)
  questID = tonumber(questID)
  if not questID or questID <= 0 or not name then return false end
  local entry = entryFor(questID)
  if not entry then return false end
  entry.turnin = place(name)
  changed()
  return true
end

-- Records the item objectives of a quest in the log; retried while names
-- are still unresolved (the item may only become known once it drops).
function QuestFacts.RecordItems(questID)
  questID = tonumber(questID)
  if not questID or questID <= 0 then return false end
  QuestFacts.ScanBagNames()
  local items = QuestFacts.LiveItems(questID)
  local entry = entryFor(questID)
  if not entry then return false end
  if #items == 0 then
    if type(entry.items) ~= "table" then entry.items = {} entry.itemsAt = ns.Util.Now() end
    QuestFacts.pending[questID] = nil
    return true
  end
  local stored = {}
  local unresolved = false
  for _, item in ipairs(items) do
    stored[#stored + 1] = { name = item.name, count = item.count, itemID = item.itemID }
    if not item.itemID then unresolved = true end
  end
  entry.items, entry.itemsAt = stored, ns.Util.Now()
  if unresolved then
    local tries = (QuestFacts.pending[questID] or 0) + 1
    QuestFacts.pending[questID] = tries <= QuestFacts.RETRY_LIMIT and tries or nil
  else
    QuestFacts.pending[questID] = nil
  end
  changed()
  return true
end

local function retryPending()
  for questID in pairs(QuestFacts.pending) do
    local ql = _G.C_QuestLog
    if ql and call(ql.IsOnQuest, questID) then
      QuestFacts.RecordItems(questID)
    else
      QuestFacts.pending[questID] = nil
    end
  end
end

function QuestFacts.Count()
  local n = 0
  for _ in pairs(QuestFacts.Store() or {}) do n = n + 1 end
  return n
end

function QuestFacts.ShippedCount()
  local catalogue = ns.Data and ns.Data.QuestCatalogue
  local n = 0
  for _ in pairs(type(catalogue) == "table" and catalogue or {}) do n = n + 1 end
  return n
end

function QuestFacts.Status()
  return string.format("Quest facts: %d quests shipped, %d learned at quest windows on this account.", QuestFacts.ShippedCount(), QuestFacts.Count())
end

function QuestFacts.Init()
  Events.RegisterWoW("QUEST_DETAIL", function()
    local questID = call(_G.GetQuestID)
    QuestFacts.RecordGiver(questID, npcName())
  end)
  Events.RegisterWoW("QUEST_ACCEPTED", function(questID)
    QuestFacts.RecordItems(questID)
  end)
  Events.RegisterWoW("QUEST_COMPLETE", function()
    local questID = call(_G.GetQuestID)
    QuestFacts.RecordTurnin(questID, npcName())
  end)
  Events.RegisterWoW("QUEST_TURNED_IN", function(questID)
    local entry = QuestFacts.Learned(questID)
    if not (entry and entry.turnin) then
      local name = npcName()
      if name then QuestFacts.RecordTurnin(questID, name) end
    end
    QuestFacts.pending[tonumber(questID) or 0] = nil
  end)
  for _, event in ipairs({ "QUEST_LOG_UPDATE", "BAG_UPDATE_DELAYED" }) do
    Events.RegisterWoW(event, function()
      if next(QuestFacts.pending) then Events.Debounce("quest-facts-retry", 1, retryPending) end
    end)
  end
  Log.Debug("%s", QuestFacts.Status())
end
