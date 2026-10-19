local H = require("harness")
local Mock = H.Mock

describe("Minimap button", function()
  local ns, MB
  before_each(function()
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
    assert_eq(ns.db.minimap.angle, 225)
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
    assert_true(near(ns.db.minimap.angle, 90))
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
    ns.db.minimap.angle = 10
    ns.Commands.Dispatch("reset window")
    assert_eq(ns.db.minimap.angle, 225)
  end)
end)
