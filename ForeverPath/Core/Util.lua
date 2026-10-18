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

-- "12g 34s 56c" without textures (chat and messages; the UI has Widgets.Money).
function Util.FormatMoney(copper)
  copper = tonumber(copper) or 0
  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  local bronze = copper % 100
  if gold > 0 then return string.format("%dg %ds", gold, silver) end
  if silver > 0 then return string.format("%ds %dc", silver, bronze) end
  return string.format("%dc", bronze)
end

function Util.Join(list, separator)
  local parts = {}
  for i = 1, #list do
    parts[i] = tostring(list[i])
  end
  return table.concat(parts, separator or ", ")
end
