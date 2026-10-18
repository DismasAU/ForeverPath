-- Chat output, debug logging and protected calls with error capture.
local _, ns = ...

local Log = {}
ns.Log = Log

Log.debugEnabled = false
Log.errors = {}
local MAX_ERRORS = 50
local unpack = unpack or table.unpack

local function output(text)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(text)
  elseif type(print) == "function" then
    print(text)
  end
end
Log.output = output -- tests replace this to capture chat output

function Log.Format(fmt, ...)
  if select("#", ...) == 0 then
    return tostring(fmt)
  end
  local ok, text = pcall(string.format, tostring(fmt), ...)
  if ok then
    return text
  end
  local parts = { tostring(fmt) }
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring((select(i, ...)))
  end
  return table.concat(parts, " ")
end

function Log.Print(fmt, ...)
  Log.output(ns.PREFIX .. ": " .. Log.Format(fmt, ...))
end

function Log.Debug(fmt, ...)
  if Log.debugEnabled then
    Log.output("|cff888888FP debug|r: " .. Log.Format(fmt, ...))
  end
end

function Log.SetDebug(enabled)
  Log.debugEnabled = enabled and true or false
  if ns.db and ns.db.settings then
    ns.db.settings.debug = Log.debugEnabled
  end
end

-- Records an error and shows its first line. Repeated identical messages are
-- counted instead of spamming chat; the full text stays in Log.errors (/fp errors).
local lastMessage, lastTime, repeatCount = nil, 0, 0
function Log.Error(fmt, ...)
  local message = Log.Format(fmt, ...)
  local now = ns.Util.Now()
  table.insert(Log.errors, { time = now, message = message })
  while #Log.errors > MAX_ERRORS do
    table.remove(Log.errors, 1)
  end
  local firstLine = message:match("^([^\n]*)") or message
  if message == lastMessage and now - lastTime < 5 then
    repeatCount = repeatCount + 1
    if repeatCount == 1 then
      Log.output("|cffff4040ForeverPath error|r: repeated error suppressed, see /fp errors")
    end
  else
    repeatCount = 0
    Log.output("|cffff4040ForeverPath error|r: " .. firstLine)
  end
  lastMessage, lastTime = message, now
end

local function traceback(err)
  local stack = ""
  if type(debugstack) == "function" then
    stack = debugstack(2) or ""
  elseif debug and debug.traceback then
    stack = debug.traceback("", 2) or ""
  end
  return tostring(err) .. "\n" .. stack
end

-- Runs fn(...) in protected mode. Errors are logged, never swallowed silently.
function Log.Call(fn, ...)
  local n = select("#", ...)
  local args = { ... }
  local ok, result = xpcall(function()
    return fn(unpack(args, 1, n))
  end, traceback)
  if not ok then
    Log.Error("%s", result)
  end
  return ok, result
end
