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

-- The export string and Share.Counts of what it carries (shown by the
-- share window), or nil, error.
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

local cleanEntry

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

-- Longest imported string kept (names, zones, labels), and the range an
-- imported number must fall in (counts, prices, coordinates, timestamps are
-- never negative); anything else is dropped rather than summed into the
-- learners' own data.
Share.MAX_STRING = 120
Share.MAX_NUMBER = 2147483647

-- Bumped whenever sanitizing gets stricter; stored imports made under an
-- older version are cleaned again on load (Share.Init).
Share.SANITIZER = 3

-- The shape AuthorToken makes: 16 hex digits.
local AUTHOR_PATTERN = "^" .. string.rep("%x", 16) .. "$"

-- An imported string as plain text: WoW chat codes (colours, links,
-- textures, atlases) are removed so a crafted export cannot show fake links
-- or icons wherever its text is printed, and the length is capped.
function Share.CleanString(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|", "")
  return text:sub(1, Share.MAX_STRING)
end

local function sanitize(value, spec)
  if spec == "number" then
    local n = tonumber(value)
    if not n or n ~= n or n < 0 or n > Share.MAX_NUMBER then return nil end
    return n
  end
  if spec == "string" then return Share.CleanString(value) end
  if type(spec) == "string" then return type(value) == spec and value or nil end
  if type(value) ~= "table" then return nil end
  local out = {}
  if spec.each then
    for key, item in pairs(value) do
      if spec.keys == "number" then key = sanitize(key, "number")
      elseif type(key) ~= "string" or not key:match(spec.keys) then key = nil
      else key = Share.CleanString(key) end
      if key ~= nil then out[key] = sanitize(item, spec.each) end
    end
  elseif spec.list then
    for _, item in ipairs(value) do out[#out + 1] = sanitize(item, spec.list) end
  else
    for field, fieldSpec in pairs(spec) do out[field] = sanitize(value[field], fieldSpec) end
  end
  return out
end

-- An import entry from a payload (or a stored entry): label, time, addon
-- version and every kind reduced to Share.SCHEMAS.
cleanEntry = function(source)
  local label = Share.CleanString(source.label)
  local entry = { label = (label and label ~= "") and label or "someone", at = sanitize(source.at, "number"),
    addon = Share.CleanString(source.addon), sanitizer = Share.SANITIZER }
  for _, kind in ipairs(Share.KINDS) do
    entry[kind] = validTable(source[kind]) and sanitize(source[kind] or {}, Share.SCHEMAS[kind]) or {}
  end
  return entry
end

-- Imports a string. Returns ok, message.
function Share.Import(text)
  local d = db()
  if not d then return false, "ForeverPath is still loading." end
  local payload, err = ns.Codec.Unpack(text)
  if not payload then return false, err end
  if type(payload) ~= "table" or payload.v ~= Share.VERSION then
    return false, "not a ForeverPath export of this version"
  end
  if type(payload.author) ~= "string" or not payload.author:match(AUTHOR_PATTERN) then
    return false, "damaged export (author)"
  end
  for _, kind in ipairs(Share.KINDS) do
    if not validTable(payload[kind]) then return false, "damaged export (" .. kind .. ")" end
  end
  if payload.author == Share.AuthorToken() then
    return false, "that export came from this account; your own data is already used"
  end
  d.imported = d.imported or {}
  local previous = d.imported[payload.author]
  local entry = cleanEntry(payload)
  entry.importedAt = Util.Now()
  d.imported[payload.author] = entry
  Events.Fire("FP_SHARED_DATA_CHANGED")
  local counts = Share.CountsLabel(Share.Counts(entry))
  if previous and previous.label ~= entry.label then
    return true, string.format("Updated %s's data (it replaces the import labelled %s): %s.", entry.label, tostring(previous.label), counts)
  end
  return true, string.format("%s %s's data: %s.", previous and "Updated" or "Imported", entry.label, counts)
end

-- Cleans every stored import made under an older sanitizer, so a tighter
-- rule also reaches data imported before it existed. Runs at load, before
-- the learners read the imports.
function Share.Init()
  local d = db()
  local cleaned = 0
  for author, entry in pairs(d and d.imported or {}) do
    if type(author) ~= "string" or not author:match(AUTHOR_PATTERN) or type(entry) ~= "table" then
      d.imported[author] = nil
      cleaned = cleaned + 1
    elseif (tonumber(entry.sanitizer) or 1) < Share.SANITIZER then
      local fresh = cleanEntry(entry)
      fresh.importedAt = tonumber(entry.importedAt)
      d.imported[author] = fresh
      cleaned = cleaned + 1
    end
  end
  if cleaned > 0 then Log.Debug("Re-checked %d stored import(s)", cleaned) end
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
  -- Modules holding derived data (the loot index, decoded recipes) drop it.
  Events.Fire("FP_SHARED_DATA_CHANGED")
  return true
end

function Share.StatusLine()
  local list = Share.List()
  if #list == 0 then return "Shared data: none imported (/fp export, /fp import)." end
  local names = {}
  for _, e in ipairs(list) do names[#names + 1] = e.label end
  return string.format("Shared data: imported from %d %s (%s).", #list, #list == 1 and "player" or "players", table.concat(names, ", "))
end
