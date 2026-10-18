-- Test runner. Run with a native Lua 5.1 interpreter:
--   lua5.1 tests/runner.lua [repo root]
-- or through Python + lupa:
--   python tests/run_tests.py
local root = rawget(_G, "FP_TEST_ROOT") or (arg and arg[1]) or "."
root = root:gsub("\\", "/"):gsub("/$", "")

package.path = root .. "/tests/?.lua;" .. root .. "/tests/?/init.lua;" .. package.path

local Harness = require("harness")
Harness.root = root
Harness.Mock.reset()

local specs = dofile(root .. "/tests/spec_list.lua")
for _, name in ipairs(specs) do
  dofile(root .. "/tests/spec/" .. name .. ".lua")
end

local failures = Harness.run()
if not rawget(_G, "FP_TEST_EMBEDDED") then
  os.exit(failures == 0 and 0 or 1)
end
return failures
