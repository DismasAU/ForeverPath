-- Plain-data serialisation for sharing: no loadstring, nothing executed.
--
-- Serialize(value) writes nil / booleans / numbers / strings / tables of
-- those as a compact token stream (length-prefixed strings, so any byte is
-- safe); Deserialize reads it back with explicit bounds checks and a depth
-- limit. Pack / Unpack wrap that in "FPX1:" strings safe to paste into an
-- edit box: base64 (pure Lua), or the client's C_EncodingUtil compression
-- when it exists ("FPX1:z:" vs "FPX1:b:").
local _, ns = ...

local Codec = {}
ns.Codec = Codec

Codec.PREFIX = "FPX1:"
Codec.MAX_DEPTH = 20

---------------------------------------------------------------------------
-- Token stream
---------------------------------------------------------------------------
local function write(value, out, depth)
  local t = type(value)
  if value == nil then
    out[#out + 1] = "z"
  elseif t == "boolean" then
    out[#out + 1] = value and "T" or "F"
  elseif t == "number" then
    if value ~= value or value == math.huge or value == -math.huge then error("number out of range") end
    if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
      -- %.0f, not %d: %d is 32-bit in some Lua 5.1 builds.
      out[#out + 1] = "i" .. string.format("%.0f", value) .. ";"
    else
      out[#out + 1] = "n" .. string.format("%.17g", value) .. ";"
    end
  elseif t == "string" then
    out[#out + 1] = "s" .. #value .. ":" .. value
  elseif t == "table" then
    if depth > Codec.MAX_DEPTH then error("too deeply nested") end
    out[#out + 1] = "{"
    -- Stable order: numbers first, then strings.
    local keys = {}
    for k in pairs(value) do
      if type(k) == "number" or type(k) == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b)
      if type(a) ~= type(b) then return type(a) == "number" end
      return a < b
    end)
    for _, k in ipairs(keys) do
      write(k, out, depth + 1)
      write(value[k], out, depth + 1)
    end
    out[#out + 1] = "}"
  else
    error("cannot serialise a " .. t)
  end
end

function Codec.Serialize(value)
  local out = {}
  local ok, err = pcall(write, value, out, 0)
  if not ok then return nil, tostring(err) end
  return table.concat(out)
end

-- Returns value or nil, error.
function Codec.Deserialize(text)
  if type(text) ~= "string" then return nil, "not a string" end
  local pos = 1
  local len = #text
  local read
  local function number(prefix)
    local stop = text:find(";", pos, true)
    if not stop then error("unterminated number") end
    local n = tonumber(text:sub(pos, stop - 1))
    if not n then error("bad number") end
    pos = stop + 1
    if prefix == "i" and n ~= math.floor(n) then error("bad integer") end
    return n
  end
  read = function(depth)
    if pos > len then error("unexpected end") end
    local tag = text:sub(pos, pos)
    pos = pos + 1
    if tag == "z" then return nil
    elseif tag == "T" then return true
    elseif tag == "F" then return false
    elseif tag == "i" or tag == "n" then return number(tag)
    elseif tag == "s" then
      local colon = text:find(":", pos, true)
      local size = colon and tonumber(text:sub(pos, colon - 1))
      if not size or size < 0 or colon + size > len then error("bad string") end
      local s = text:sub(colon + 1, colon + size)
      pos = colon + size + 1
      return s
    elseif tag == "{" then
      if depth > Codec.MAX_DEPTH then error("too deeply nested") end
      local t = {}
      while true do
        if pos > len then error("unterminated table") end
        if text:sub(pos, pos) == "}" then pos = pos + 1 return t end
        local k = read(depth + 1)
        if type(k) ~= "string" and type(k) ~= "number" then error("bad key") end
        t[k] = read(depth + 1)
      end
    end
    error("bad tag " .. tag)
  end
  local ok, value = pcall(read, 0)
  if not ok then return nil, tostring(value):gsub("^.-:%d+: ", "") end
  if pos <= len then return nil, "trailing data" end
  return value
end

---------------------------------------------------------------------------
-- Base64 (pure Lua 5.1, no bit library)
---------------------------------------------------------------------------
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DECODE = {}
for i = 1, #ALPHABET do DECODE[ALPHABET:sub(i, i)] = i - 1 end

function Codec.Base64Encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    out[#out + 1] = ALPHABET:sub(c1 + 1, c1 + 1) .. ALPHABET:sub(c2 + 1, c2 + 1)
      .. (b and ALPHABET:sub(c3 + 1, c3 + 1) or "=") .. (c and ALPHABET:sub(c4 + 1, c4 + 1) or "=")
  end
  return table.concat(out)
end

function Codec.Base64Decode(text)
  text = text:gsub("%s", "")
  if #text % 4 ~= 0 then return nil, "bad length" end
  local out = {}
  for i = 1, #text, 4 do
    local chunk = text:sub(i, i + 3)
    local n, pad = 0, 0
    for j = 1, 4 do
      local ch = chunk:sub(j, j)
      local v
      if ch == "=" then v = 0 pad = pad + 1 else v = DECODE[ch] end
      if v == nil then return nil, "bad character" end
      n = n * 64 + v
    end
    local a, b, c = math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
    out[#out + 1] = string.char(a)
    if pad < 2 then out[#out + 1] = string.char(b) end
    if pad < 1 then out[#out + 1] = string.char(c) end
  end
  return table.concat(out)
end

---------------------------------------------------------------------------
-- Paste-safe strings
---------------------------------------------------------------------------
local function encoding()
  local e = _G.C_EncodingUtil
  if type(e) == "table" and type(e.CompressString) == "function" and type(e.DecompressString) == "function"
    and type(e.EncodeBase64) == "function" and type(e.DecodeBase64) == "function" then
    return e
  end
  return nil
end

function Codec.Pack(value)
  local text, err = Codec.Serialize(value)
  if not text then return nil, err end
  local e = encoding()
  if e then
    local ok, packed = pcall(function() return e.EncodeBase64(e.CompressString(text)) end)
    if ok and type(packed) == "string" then return Codec.PREFIX .. "z:" .. packed end
  end
  return Codec.PREFIX .. "b:" .. Codec.Base64Encode(text)
end

function Codec.Unpack(text)
  if type(text) ~= "string" then return nil, "nothing to import" end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  local mode, body = text:match("^FPX1:(%a):(.+)$")
  if not mode then return nil, "not a ForeverPath export (it starts with FPX1:)" end
  local raw
  if mode == "b" then
    local err
    raw, err = Codec.Base64Decode(body)
    if not raw then return nil, "damaged export (" .. err .. ")" end
  elseif mode == "z" then
    local e = encoding()
    if not e then return nil, "this export is compressed and this client cannot decompress it" end
    local ok, result = pcall(function() return e.DecompressString(e.DecodeBase64(body)) end)
    if not ok or type(result) ~= "string" then return nil, "damaged export" end
    raw = result
  else
    return nil, "unknown export format"
  end
  local value, err = Codec.Deserialize(raw)
  if err then return nil, "damaged export (" .. err .. ")" end
  return value
end
