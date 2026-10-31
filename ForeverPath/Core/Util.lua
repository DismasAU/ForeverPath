-- Pure helper functions. No WoW API dependencies beyond the optional `time` global.
local _, ns = ...

local Util = {}
ns.Util = Util

-- Current time in seconds. WoW exposes `time()`; plain Lua has os.time().
function Util.Now()
  if type(time) == "function" then
    return time()
  end
  if os and os.time then
    return os.time()
  end
  return 0
end

-- Parses an integer from a number or string. Returns nil for anything else
-- (including fractional numbers and strings with trailing garbage).
function Util.ParseInt(value)
  if type(value) == "number" then
    if value ~= math.floor(value) then
      return nil
    end
    return value
  end
  if type(value) ~= "string" then
    return nil
  end
  local digits = value:match("^%s*(%-?%d+)%s*$")
  if not digits then
    return nil
  end
  return tonumber(digits)
end

local function passResults(ok, ...)
  if ok then return ... end
  if ns.Log then ns.Log.Debug("Client call failed: %s", tostring((...))) end
  return nil
end

-- Calls `fn` when it is a function and returns all of its results; returns
-- nil when `fn` is missing or raises (a raise shows in debug mode only). For
-- client APIs that may be absent or throw on some builds.
function Util.SafeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  return passResults(pcall(fn, ...))
end

-- A name table whose unknown names raise, so a misspelt name fails where it
-- is written instead of comparing false. names: a list (t.UPPER == "value")
-- or a set keyed by the names themselves (t.NAME == "NAME").
function Util.StrictNames(names, what)
  local t = setmetatable({}, {
    __index = function(_, name) error("unknown " .. what .. " " .. tostring(name), 2) end,
  })
  if names[1] ~= nil then
    for _, value in ipairs(names) do rawset(t, string.upper(value), value) end
  else
    for name in pairs(names) do rawset(t, name, name) end
  end
  return t
end

function Util.IsPositiveInt(value)
  return type(value) == "number" and value > 0 and value == math.floor(value)
end

function Util.Trim(s)
  s = tostring(s or "")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Util.Clamp(value, lo, hi)
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

function Util.Count(t)
  local n = 0
  if type(t) == "table" then
    for _ in pairs(t) do n = n + 1 end
  end
  return n
end

function Util.DeepCopy(value, seen)
  if type(value) ~= "table" then
    return value
  end
  seen = seen or {}
  if seen[value] then
    return seen[value]
  end
  local copy = {}
  seen[value] = copy
  for k, v in pairs(value) do
    copy[Util.DeepCopy(k, seen)] = Util.DeepCopy(v, seen)
  end
  return copy
end

-- Recursively fills keys missing from `target` with copies of `defaults`.
-- Existing values are never overwritten, so user settings survive upgrades.
function Util.ApplyDefaults(target, defaults)
  if type(target) ~= "table" then
    target = {}
  end
  for key, value in pairs(defaults) do
    if type(value) == "table" then
      if type(target[key]) ~= "table" then
        target[key] = {}
      end
      Util.ApplyDefaults(target[key], value)
    elseif target[key] == nil then
      target[key] = value
    end
  end
  return target
end

function Util.SortedKeys(t, comparator)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys, comparator)
  return keys
end

-- Rank of a name against a lower-cased needle: 0 exact, 1 starts with it,
-- 2 a word starts with it ("Mace of the Storms" for "storm"), 3 anywhere
-- inside a word ("Thunderstorm Blade"); nil when it does not match. Every
-- type-ahead search sorts by it, so all categories rank alike.
function Util.MatchRank(name, needle)
  if type(name) ~= "string" then return nil end
  local lower = name:lower()
  if lower == needle then return 0 end
  local position = lower:find(needle, 1, true)
  if not position then return nil end
  if position == 1 then return 1 end
  local before = lower:sub(position - 1, position - 1)
  if before == " " or before == "-" or before == "'" or before == ":" or before == "(" or before == "/" then return 2 end
  return 3
end

-- Sorts type-ahead hits { rank, name, [idField] } best first (rank, then
-- tieBreak(a, b) when given and it decides, then name, then id) and cuts
-- the list to limit. Returns hits.
function Util.SortRankedHits(hits, idField, limit, tieBreak)
  table.sort(hits, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    local decided = tieBreak and tieBreak(a, b)
    if decided ~= nil then return decided end
    if a.name ~= b.name and a.name and b.name then return a.name < b.name end
    return a[idField] < b[idField]
  end)
  if limit then
    for i = #hits, limit + 1, -1 do hits[i] = nil end
  end
  return hits
end

-- Human readable "how long ago" text.
function Util.FormatAgo(timestamp, now)
  if type(timestamp) ~= "number" then
    return "never"
  end
  now = now or Util.Now()
  local delta = now - timestamp
  if delta < 0 then delta = 0 end
  if delta < 60 then return "just now" end
  if delta < 3600 then return string.format("%dm ago", math.floor(delta / 60)) end
  if delta < 86400 then return string.format("%dh ago", math.floor(delta / 3600)) end
  return string.format("%dd ago", math.floor(delta / 86400))
end

-- True when a value only contains data the SavedVariables writer can persist.
function Util.IsPlainData(value, seen)
  local t = type(value)
  if t == "string" or t == "number" or t == "boolean" or t == "nil" then
    return true
  end
  if t ~= "table" then
    return false
  end
  seen = seen or {}
  if seen[value] then
    return false -- cycles cannot be serialized
  end
  seen[value] = true
  if getmetatable(value) ~= nil then
    return false
  end
  for k, v in pairs(value) do
    local kt = type(k)
    if kt ~= "string" and kt ~= "number" then
      return false
    end
    if not Util.IsPlainData(v, seen) then
      return false
    end
  end
  seen[value] = nil
  return true
end

-- The two largest units as plain text, "12g 34s", "34s 56c" or "56c" (no
-- textures or colour). Util.Money renders through the UI when it can.
function Util.PlainMoney(copper)
  copper = tonumber(copper) or 0
  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  local bronze = copper % 100
  if gold > 0 then return string.format("%dg %ds", gold, silver) end
  if silver > 0 then return string.format("%ds %dc", silver, bronze) end
  return string.format("%dc", bronze)
end

-- Money text for hints, chat and messages: Util.PlainMoney until the UI
-- installs its coin-coloured renderer (Widgets.Money) through
-- Util.SetMoneyRenderer, so lower layers never reach up into the UI.
local moneyRenderer
function Util.Money(copper)
  if moneyRenderer then return moneyRenderer(copper) end
  return Util.PlainMoney(copper)
end

function Util.SetMoneyRenderer(fn)
  moneyRenderer = fn
end

function Util.Join(list, separator)
  local parts = {}
  for i = 1, #list do
    parts[i] = tostring(list[i])
  end
  return table.concat(parts, separator or ", ")
end
