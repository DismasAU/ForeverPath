-- Minimal test harness: describe / it / before_each plus assertions.
-- Loads the addon exactly as the client would: files in TOC order, each
-- called with (addonName, namespace).
local Mock = require("mocks.wow_api")

local Harness = {
  suites = {},
  root = ".",
  passed = 0,
  failed = 0,
  failures = {},
  Mock = Mock,
}

local current

function _G.describe(name, fn)
  local suite = { name = name, tests = {}, before = nil }
  table.insert(Harness.suites, suite)
  local previous = current
  current = suite
  fn()
  current = previous
end

function _G.before_each(fn)
  current.before = fn
end

function _G.it(name, fn)
  table.insert(current.tests, { name = name, fn = fn })
end

local function dump(value, depth)
  depth = depth or 0
  if type(value) == "string" then
    return string.format("%q", value)
  end
  if type(value) ~= "table" then
    return tostring(value)
  end
  if depth > 2 then
    return "{...}"
  end
  local parts = {}
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    parts[#parts + 1] = tostring(k) .. "=" .. dump(value[k], depth + 1)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end
Harness.dump = dump

local function fail(msg, level)
  error(msg, (level or 1) + 2)
end

function _G.assert_eq(actual, expected, msg)
  if actual ~= expected then
    fail(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", dump(expected), dump(actual)))
  end
end

function _G.assert_ne(actual, unexpected, msg)
  if actual == unexpected then
    fail(string.format("%sexpected something other than %s", msg and (msg .. ": ") or "", dump(unexpected)))
  end
end

-- Truthiness assertions.
function _G.assert_true(value, msg)
  if not value then
    fail((msg and (msg .. ": ") or "") .. "expected truthy, got " .. dump(value))
  end
end

function _G.assert_false(value, msg)
  if value then
    fail((msg and (msg .. ": ") or "") .. "expected falsy, got " .. dump(value))
  end
end

function _G.assert_nil(value, msg)
  if value ~= nil then
    fail((msg and (msg .. ": ") or "") .. "expected nil, got " .. dump(value))
  end
end

function _G.assert_not_nil(value, msg)
  if value == nil then
    fail((msg and (msg .. ": ") or "") .. "expected a value, got nil")
  end
end

function _G.assert_gt(a, b, msg)
  if not (a > b) then
    fail(string.format("%sexpected %s > %s", msg and (msg .. ": ") or "", dump(a), dump(b)))
  end
end

function _G.assert_match(text, pattern, msg)
  if type(text) ~= "string" or not text:match(pattern) then
    fail(string.format("%sexpected %s to match %q", msg and (msg .. ": ") or "", dump(text), pattern))
  end
end

function _G.assert_error(fn, pattern)
  local ok, err = pcall(fn)
  if ok then
    fail("expected an error" .. (pattern and (" matching " .. pattern) or ""))
  end
  if pattern and not tostring(err):match(pattern) then
    fail(string.format("expected error matching %q, got %s", pattern, tostring(err)))
  end
end

local function deepEqual(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if not deepEqual(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

function _G.assert_deep_eq(actual, expected, msg)
  if not deepEqual(actual, expected) then
    fail(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", dump(expected), dump(actual)))
  end
end

-- True when any captured chat line matches the pattern.
function _G.assert_output(pattern)
  for _, line in ipairs(Mock.output) do
    if line:match(pattern) then
      return true
    end
  end
  fail("no chat output matched " .. string.format("%q", pattern) .. "\n  output: " .. dump(Mock.output))
end

function Harness.readFile(path)
  local handle, err = io.open(path, "r")
  if not handle then
    return nil, err
  end
  local content = handle:read("*a")
  handle:close()
  return content
end

-- Files listed in a TOC, in order, with forward slashes.
function Harness.tocFiles(path)
  local content, err = Harness.readFile(path)
  if not content then
    error("cannot read TOC " .. path .. ": " .. tostring(err))
  end
  local files = {}
  for line in (content .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
      files[#files + 1] = (trimmed:gsub("\\", "/"))
    end
  end
  return files
end

function Harness.loadAddon(root)
  local addonDir = root .. "/ForeverPath"
  local ns = {}
  for _, rel in ipairs(Harness.tocFiles(addonDir .. "/ForeverPath.toc")) do
    local path = addonDir .. "/" .. rel
    local chunk, err = loadfile(path)
    if not chunk then
      error("compile error in " .. rel .. ": " .. tostring(err))
    end
    chunk("ForeverPath", ns)
  end
  return ns
end

-- Runs the ForeverPath_ClassicDB files (as the client would on LoadAddOn).
function Harness.loadClassicDB(root)
  local addonDir = (root or Harness.root) .. "/ForeverPath_ClassicDB"
  for _, rel in ipairs(Harness.tocFiles(addonDir .. "/ForeverPath_ClassicDB.toc")) do
    local chunk, err = loadfile(addonDir .. "/" .. rel)
    if not chunk then error("compile error in ForeverPath_ClassicDB/" .. rel .. ": " .. tostring(err)) end
    chunk("ForeverPath_ClassicDB", {})
  end
end

-- Fresh client state plus a freshly loaded addon. opts.setup runs after the
-- mock reset and before the addon files execute (to remove APIs, seed data).
function Harness.fresh(opts)
  Mock.reset()
  if opts and opts.setup then
    opts.setup(Mock)
  end
  return Harness.loadAddon(Harness.root)
end

-- Simulates the login sequence the client performs.
function Harness.login(ns)
  Mock.FireEvent("ADDON_LOADED", "ForeverPath")
  Mock.FireEvent("PLAYER_LOGIN")
  Mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  Mock.RunTimers()
  return ns
end

function Harness.run()
  for _, suite in ipairs(Harness.suites) do
    print(suite.name)
    for _, test in ipairs(suite.tests) do
      local ok, err = true, nil
      if suite.before then
        ok, err = xpcall(suite.before, debug.traceback)
      end
      if ok then
        ok, err = xpcall(test.fn, debug.traceback)
      end
      if ok then
        Harness.passed = Harness.passed + 1
        print("  [ok]   " .. test.name)
      else
        Harness.failed = Harness.failed + 1
        table.insert(Harness.failures, suite.name .. " / " .. test.name)
        print("  [FAIL] " .. test.name)
        print("         " .. tostring(err):gsub("\n", "\n         "))
      end
    end
  end
  print(string.format("\n%d passed, %d failed (%s)", Harness.passed, Harness.failed, _VERSION))
  if Harness.failed > 0 then
    print("Failures:")
    for _, name in ipairs(Harness.failures) do
      print("  - " .. name)
    end
  end
  return Harness.failed
end

return Harness
