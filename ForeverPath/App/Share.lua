-- Sharing what an account has learned on Forever.
--
-- Export packs the account's own observations (ForeverPathDB.lootSeen,
-- questFacts, vendors, trainers, trainerNPCs) into one "FPX1:" string with
-- an author token (random, made once per account), a label (the exporting
-- character) and the time. Import checks the version, reduces each kind to
-- the fields and types the providers write (Share.SCHEMAS) and stores it under
-- ForeverPathDB.imported[author]; importing the same author again replaces
-- the earlier copy, so nothing is ever counted twice. Nothing a goal or
-- character holds is exported.
--
-- The providers read imports behind their own data: the loot learner adds
-- imported loot counts, quest facts use an imported giver / turn-in / item
-- list when this account has none, vendors and trainers fill in NPCs this
-- account has not visited.
local _, ns = ...

local Util = ns.Util
local Log = ns.Log
local Events = ns.Events

local Share = {}
ns.Share = Share

Share.VERSION = 1
Share.KINDS = { "lootSeen", "questFacts", "vendors", "trainers", "trainerNPCs" }

local function db() return ns.db end

function Share.AuthorToken()
  local d = db()
  if not d then return nil end
  if type(d.shareToken) ~= "string" then
    local parts = {}
    for i = 1, 4 do parts[i] = string.format("%04x", math.random(0, 65535)) end
    d.shareToken = table.concat(parts)
  end
  return d.shareToken
end

local function label()
  local name = type(UnitName) == "function" and select(1, UnitName("player")) or nil
  local realm = type(GetRealmName) == "function" and GetRealmName() or nil
  if name and realm and realm ~= "" then return name .. "-" .. realm end
  return name or "someone"
end

local count = ns.Util.Count

-- { lootSeen = n, questFacts = n, vendors = n (items), trainers = n (recipes) }
function Share.Counts(data)
  return { lootSeen = count(data.lootSeen), questFacts = count(data.questFacts), vendors = count(data.vendors), trainers = count(data.trainers) }
end

function Share.CountsLabel(counts)
  return string.format("%d loot sources, %d quests, %d vendor items, %d trainer recipes", counts.lootSeen or 0, counts.questFacts or 0, counts.vendors or 0, counts.trainers or 0)
end

-- The export string, or nil, error.
function Share.Export()
  local d = db()
  if not d then return nil, "ForeverPath is still loading." end
  local payload = { v = Share.VERSION, author = Share.AuthorToken(), label = label(), at = Util.Now(), addon = ns.VERSION }
  for _, kind in ipairs(Share.KINDS) do payload[kind] = d[kind] or {} end
  local text, err = ns.Codec.Pack(payload)
  if not text then return nil, err end
  return text, Share.Counts(payload)
end

local function validTable(t) return t == nil or type(t) == "table" end

-- What each kind may hold, so an import is reduced to the shapes the
-- providers write themselves. A spec is a leaf type ("string", "number" -
-- coerced with tonumber - or "boolean"), a record { field = spec }, a map
-- { each = spec, keys = "number" | pattern } or a list { list = spec }.
local PLACE = { name = "string", mapID = "number", x = "number", y = "number", zone = "string", subzone = "string", seenAt = "number" }
local LOOT_COUNTS = { each = { times = "number", quantity = "number" }, keys = "number" }
Share.SCHEMAS = {
  lootSeen = { keys = "^[cof]:", each = {
    name = "string", kind = "string", zone = "string", mapID = "number", x = "number", y = "number",
    looted = "number", seenAt = "number", items = LOOT_COUNTS, skinned = LOOT_COUNTS,
  } },
  questFacts = { keys = "number", each = {
    giver = PLACE, turnin = PLACE, itemsAt = "number",
    items = { list = { name = "string", count = "number", itemID = "number" } },
  } },
  vendors = { keys = "number", each = { keys = ".", each = {
    price = "number", stack = "number", limited = "boolean", extended = "boolean",
    zone = "string", subzone = "string", seenAt = "number",
  } } },
  trainers = { keys = "number", each = {
    skill = "string", rank = "number", cost = "number", trainer = "string", zone = "string", subzone = "string", seenAt = "number",
  } },
  trainerNPCs = { keys = ".", each = { zone = "string", subzone = "string", recipes = "number", seenAt = "number" } },
}

local function sanitize(value, spec)
  if spec == "number" then return tonumber(value) end
  if type(spec) == "string" then return type(value) == spec and value or nil end
  if type(value) ~= "table" then return nil end
  local out = {}
  if spec.each then
    for key, item in pairs(value) do
      if spec.keys == "number" then key = tonumber(key)
      elseif type(key) ~= "string" or not key:match(spec.keys) then key = nil end
      if key ~= nil then out[key] = sanitize(item, spec.each) end
    end
  elseif spec.list then
    for _, item in ipairs(value) do out[#out + 1] = sanitize(item, spec.list) end
  else
    for field, fieldSpec in pairs(spec) do out[field] = sanitize(value[field], fieldSpec) end
  end
  return out
end

-- Imports a string. Returns ok, message.
function Share.Import(text)
  local d = db()
  if not d then return false, "ForeverPath is still loading." end
  local payload, err = ns.Codec.Unpack(text)
  if not payload then return false, err end
  if type(payload) ~= "table" or payload.v ~= Share.VERSION or type(payload.author) ~= "string" then
    return false, "not a ForeverPath export of this version"
  end
  for _, kind in ipairs(Share.KINDS) do
    if not validTable(payload[kind]) then return false, "damaged export (" .. kind .. ")" end
  end
  if payload.author == Share.AuthorToken() then
    return false, "that export came from this account; your own data is already used"
  end
  d.imported = d.imported or {}
  local replaced = d.imported[payload.author] ~= nil
  local entry = { label = type(payload.label) == "string" and payload.label or "someone", at = tonumber(payload.at), importedAt = Util.Now(), addon = payload.addon }
  for _, kind in ipairs(Share.KINDS) do entry[kind] = sanitize(payload[kind] or {}, Share.SCHEMAS[kind]) end
  d.imported[payload.author] = entry
  Share.Changed()
  local counts = Share.Counts(entry)
  return true, string.format("%s %s's data: %s.", replaced and "Updated" or "Imported", entry.label, Share.CountsLabel(counts))
end

-- { { author, label, at, importedAt, counts } } newest first.
function Share.List()
  local out = {}
  for author, entry in pairs((db() and db().imported) or {}) do
    out[#out + 1] = { author = author, label = entry.label, at = entry.at, importedAt = entry.importedAt, counts = Share.Counts(entry) }
  end
  table.sort(out, function(a, b) return (a.importedAt or 0) > (b.importedAt or 0) end)
  return out
end

function Share.Remove(author)
  local d = db()
  if not d or not d.imported or not d.imported[author] then return false end
  d.imported[author] = nil
  Share.Changed()
  return true
end

-- Modules holding derived data (the loot index, decoded recipes) drop it on
-- FP_SHARED_DATA_CHANGED.
function Share.Changed()
  Events.Fire("FP_SHARED_DATA_CHANGED")
end

function Share.StatusLine()
  local list = Share.List()
  if #list == 0 then return "Shared data: none imported (/fp export, /fp import)." end
  local names = {}
  for _, e in ipairs(list) do names[#names + 1] = e.label end
  return string.format("Shared data: imported from %d %s (%s).", #list, #list == 1 and "player" or "players", table.concat(names, ", "))
end
