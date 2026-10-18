local H = require("harness")

describe("TOC manifest", function()
  local addonDir = H.root .. "/ForeverPath"

  it("targets Forever first and keeps both manifests identical", function()
    local main = H.readFile(addonDir .. "/ForeverPath.toc")
    local camelot = H.readFile(addonDir .. "/ForeverPath_Camelot.toc")
    assert_not_nil(main, "ForeverPath.toc missing")
    assert_not_nil(camelot, "ForeverPath_Camelot.toc missing")
    assert_eq(camelot, main, "the Camelot manifest must mirror the main manifest")
    assert_match(main, "^## Interface: 16001")
    assert_match(main, "## SavedVariables: ForeverPathDB")
    assert_match(main, "## SavedVariablesPerCharacter: ForeverPathCharDB")
  end)

  it("lists files that exist and compile under this Lua", function()
    local files = H.tocFiles(addonDir .. "/ForeverPath.toc")
    assert_gt(#files, 10)
    for _, rel in ipairs(files) do
      local path = addonDir .. "/" .. rel
      local content = H.readFile(path)
      assert_not_nil(content, "missing file " .. rel)
      local chunk, err = loadfile(path)
      assert_not_nil(chunk, "compile error in " .. rel .. ": " .. tostring(err))
    end
  end)

  it("loads every file in order and leaves a single global", function()
    local ns = H.fresh()
    assert_eq(_G.ForeverPath, ns)
    assert_not_nil(ns.Util)
    assert_not_nil(ns.Planner)
    assert_not_nil(ns.UI.MainFrame)
    assert_eq(type(_G.ForeverPath_OnAddonCompartmentClick), "function")
  end)
end)
