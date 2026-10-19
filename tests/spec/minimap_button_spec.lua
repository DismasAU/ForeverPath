local H = require("harness")
local Mock = H.Mock

describe("Minimap button", function()
  local ns, MB
  before_each(function()
    _G.LibStub = nil
    ns = H.fresh()
    H.login(ns)
    MB = ns.UI.MinimapButton
  end)

  local function near(a, b) return math.abs(a - b) < 0.01 end

  it("shows the ForeverPath mark on the minimap edge", function()
    local button = MB.button
    assert_not_nil(button, "created at login")
    assert_true(button:IsShown())
    assert_eq(button.icon.texture or button.icon:GetTexture(), ns.UI.LOGO)
    assert_eq(ns.db.minimap.minimapPos, 225)
    local point, relativeTo, _, x, y = button:GetPoint(1)
    assert_eq(point, "CENTER")
    assert_eq(relativeTo, _G.Minimap)
    -- 225 degrees on a round 140 px minimap: 75 px out, lower left.
    assert_true(near(x, -75 * math.sqrt(0.5)) and near(y, -75 * math.sqrt(0.5)))
  end)

  it("pushes the button to the corner on a square minimap", function()
    local x, y = MB.Offset(45, 140, 140, "SQUARE")
    local round = 75 * math.sqrt(0.5)
    assert_true(x > round + 10 and y > round + 10 and x <= 75 and y <= 75, "out towards the corner, inside the square")
    x, y = MB.Offset(45, 140, 140, "CORNER-TOPRIGHT")
    assert_true(near(x, 75 * math.sqrt(0.5)), "the rounded corner keeps the circle")
  end)

  it("opens the window, toggles the tracker and moves when dragged", function()
    local button = MB.button
    assert_false(ns.UI.MainFrame.frame and ns.UI.MainFrame.frame:IsShown() or false)
    button:Fire("OnClick", "LeftButton")
    assert_true(ns.UI.MainFrame.frame:IsShown())
    button:Fire("OnClick", "LeftButton")
    assert_false(ns.UI.MainFrame.frame:IsShown())
    local hidden = ns.chardb.tracker.hidden
    button:Fire("OnClick", "RightButton")
    assert_eq(ns.chardb.tracker.hidden, not hidden)
    -- Drag to straight above the minimap.
    button:Fire("OnDragStart")
    Mock.cursor = { 1000, 700 }
    button:Fire("OnUpdate", 0.1)
    button:Fire("OnDragStop")
    assert_true(near(ns.db.minimap.minimapPos, 90))
    local _, _, _, x, y = button:GetPoint(1)
    assert_true(near(x, 0) and near(y, 75))
    assert_nil(button:GetScript("OnUpdate"), "stops following the cursor")
    -- The tooltip names the addon and the clicks.
    button:Fire("OnEnter")
    assert_true(GameTooltip:IsShown())
  end)

  it("hides, shows and resets from slash commands", function()
    ns.Commands.Dispatch("minimap hide")
    assert_true(ns.db.minimap.hide)
    assert_false(MB.button:IsShown())
    ns.Commands.Dispatch("minimap")
    assert_false(ns.db.minimap.hide)
    assert_true(MB.button:IsShown())
    ns.db.minimap.minimapPos = 10
    ns.Commands.Dispatch("reset window")
    assert_eq(ns.db.minimap.minimapPos, 225)
  end)
end)

describe("Minimap button through LibDBIcon", function()
  -- LibStub with LibDataBroker-1.1 and LibDBIcon-1.0, as another addon would load them.
  local function installLibs()
    local objects, icons = {}, { registered = {}, shown = {} }
    local ldb = {
      NewDataObject = function(_, name, data) objects[name] = data return data end,
      GetDataObjectByName = function(_, name) return objects[name] end,
    }
    function icons:Register(name, object, db)
      self.registered[name] = { object = object, db = db }
      self.shown[name] = not db.hide
      self.button = CreateFrame("Button", "LibDBIcon10_" .. name, Minimap)
    end
    function icons:Show(name) self.shown[name] = true end
    function icons:Hide(name) self.shown[name] = false end
    function icons:Refresh(name, db) self.refreshed = db.minimapPos end
    function icons:GetMinimapButton() return self.button end
    local libs = { ["LibDataBroker-1.1"] = ldb, ["LibDBIcon-1.0"] = icons }
    _G.LibStub = { GetLibrary = function(_, name) return libs[name] end }
    return icons
  end

  before_each(function() _G.LibStub = nil end)

  it("registers a launcher with the mark instead of drawing its own button", function()
    local ns = H.fresh()
    local icons = installLibs()
    _G.ForeverPathMinimapButton = nil -- left by the native-button tests
    H.login(ns)
    local MB = ns.UI.MinimapButton
    local entry = icons.registered.ForeverPath
    assert_not_nil(entry, "registered with LibDBIcon")
    assert_eq(entry.object.type, "launcher")
    assert_eq(entry.object.icon, ns.UI.LOGO)
    assert_eq(entry.db, ns.db.minimap, "LibDBIcon keeps its position in our saved settings")
    assert_eq(entry.db.minimapPos, 225)
    assert_eq(MB.button, icons.button)
    assert_nil(_G.ForeverPathMinimapButton, "no native button")
    -- Clicks and tooltip come from the data object.
    entry.object.OnClick(nil, "LeftButton")
    assert_true(ns.UI.MainFrame.frame:IsShown())
    local lines = {}
    entry.object.OnTooltipShow({ AddLine = function(_, text) lines[#lines + 1] = text end })
    assert_match(lines[1], "^ForeverPath ")
    -- Hide, show and reset go through the library.
    ns.Commands.Dispatch("minimap hide")
    assert_false(icons.shown.ForeverPath)
    ns.Commands.Dispatch("minimap show")
    assert_true(icons.shown.ForeverPath)
    ns.db.minimap.minimapPos = 10
    ns.Commands.Dispatch("reset window")
    assert_eq(icons.refreshed, 225)
    _G.LibStub = nil
  end)

  it("carries the 0.24.0 angle over to minimapPos", function()
    local ns = H.fresh()
    H.login(ns)
    ns.db.minimap.angle = 90
    ns.db.minimap.minimapPos = 225
    ns.UI.MinimapButton.UpdatePosition()
    assert_eq(ns.db.minimap.minimapPos, 90)
    assert_nil(ns.db.minimap.angle)
  end)
end)
