local H = require("harness")
local Mock = H.Mock

describe("Compat", function()
  local ns, Compat
  before_each(function()
    ns = H.fresh()
    Compat = ns.Compat
  end)

  -- A client without the modern namespaces, set up before the addon loads.
  local function legacyClient(setup)
    ns = H.fresh({ setup = function()
      _G.C_Container = nil
      _G.C_MerchantFrame = nil
      _G.C_Timer = nil
      _G.C_AddOns = nil
      if setup then setup() end
    end })
    return ns.Compat
  end

  it("detects the Forever client from the build info", function()
    assert_true(Compat.client.isForever)
    assert_eq(Compat.client.interface, 16001)
    assert_eq(Compat.client.build, "70450")
    ns = H.fresh({ setup = function() _G.GetBuildInfo = nil end })
    assert_eq(ns.Compat.client.version, "unknown")
    assert_eq(ns.Compat.client.interface, 0)
    assert_false(ns.Compat.client.isForever)
  end)

  it("reads container slots through the legacy multiple-return API", function()
    Compat = legacyClient(function()
      _G.GetContainerItemInfo = function(bag, slot)
        if bag == 0 and slot == 1 then return nil, 7, nil, nil, nil, nil, nil, nil, nil, 2589 end
        if bag == 0 and slot == 2 then return nil, nil, nil, nil, nil, nil, nil, nil, nil, 2996 end
        return nil
      end
    end)
    local itemID, count = Compat.GetContainerSlot(0, 1)
    assert_eq(itemID, 2589)
    assert_eq(count, 7)
    itemID, count = Compat.GetContainerSlot(0, 2)
    assert_eq(itemID, 2996)
    assert_eq(count, 1, "a slot with no count is one item")
    assert_nil(Compat.GetContainerSlot(0, 3))
  end)

  it("has no container reader when neither API exists", function()
    Compat = legacyClient()
    assert_nil(Compat.GetContainerSlot)
    local described = {}
    for _, row in ipairs(Compat.Capabilities()) do described[row[1]] = row[2] end
    assert_eq(described["Container API"], "missing")
    assert_eq(described["Forever client"], "yes")
  end)

  it("reads merchant items through the legacy API", function()
    Compat = legacyClient(function()
      _G.GetMerchantItemInfo = function(index)
        if index ~= 1 then return nil end
        return "Coarse Thread", nil, 10, 5, -1, true, nil, false
      end
    end)
    assert_deep_eq(Compat.GetMerchantItem(1), { name = "Coarse Thread", price = 10, stack = 5, numAvailable = -1, hasExtendedCost = false, isPurchasable = true })
    assert_nil(Compat.GetMerchantItem(2))
  end)

  it("runs After at once and says so when the client has no timer", function()
    Compat = legacyClient()
    assert_false(Compat.hasTimer)
    local ran = false
    Compat.After(30, function() ran = true end)
    assert_true(ran)
  end)

  it("reads the player's map position and degrades when the map API is partial", function()
    Mock.position = { mapID = 1441, x = 0.5, y = 0.25 }
    local mapID, x, y = Compat.PlayerPosition()
    assert_eq(mapID, 1441)
    assert_eq(x, 0.5)
    assert_eq(y, 0.25)
    _G.C_Map.GetPlayerMapPosition = function() return nil end
    mapID, x = Compat.PlayerPosition()
    assert_eq(mapID, 1441, "the map is known even when the position is not")
    assert_nil(x)
    _G.C_Map.GetBestMapForUnit = function() error("not in the world") end
    assert_nil(Compat.PlayerPosition())
    _G.C_Map = nil
    assert_nil(Compat.PlayerPosition())
  end)

  it("explains why a waypoint cannot be set", function()
    assert_true(Compat.SetWaypoint(1441, 0.5, 0.5))
    assert_eq(Mock.waypoint.uiMapID, 1441)
    assert_true(Mock.superTracked)
    local ok, reason = Compat.SetWaypoint(1441, nil, 0.5)
    assert_false(ok)
    assert_match(reason, "No map position")
    Mock.waypointMaps = { [1441] = true }
    ok, reason = Compat.SetWaypoint(1429, 0.5, 0.5)
    assert_false(ok)
    assert_match(reason, "does not allow waypoints")
    _G.C_Map.SetUserWaypoint = function() error("blocked") end
    ok, reason = Compat.SetWaypoint(1441, 0.5, 0.5)
    assert_false(ok)
    assert_match(reason, "blocked")
    _G.UiMapPoint = nil
    assert_false(Compat.HasWaypoints())
    ok, reason = Compat.SetWaypoint(1441, 0.5, 0.5)
    assert_false(ok)
    assert_match(reason, "no map waypoints")
  end)

  it("reads item stats from the legacy out-table API", function()
    _G.C_Item.GetItemStats = nil
    _G.GetItemStats = function(_, out) out.ITEM_MOD_STAMINA_SHORT = 7 end
    assert_deep_eq(Compat.GetItemStats(2996), { ITEM_MOD_STAMINA_SHORT = 7 })
    _G.GetItemStats = function() end
    assert_nil(Compat.GetItemStats(2996), "an empty answer is no stats")
    _G.GetItemStats = nil
    assert_nil(Compat.GetItemStats(2996))
  end)

  it("reads the character at call time and answers nil while the unit is not ready", function()
    Mock.character.faction = "Horde"
    Mock.character.classFile = "shaman"
    Mock.character.classID = 7
    Mock.character.level = 42
    assert_eq(Compat.PlayerFaction(), "Horde")
    Mock.character.class = "Shaman"
    local classFile, classID, className = Compat.PlayerClass()
    assert_eq(classFile, "SHAMAN")
    assert_eq(classID, 7)
    assert_eq(className, "Shaman")
    assert_eq(Compat.PlayerLevel(), 42)
    _G.UnitFactionGroup = function() return nil end
    _G.UnitClass = function() return nil, "", nil end
    _G.UnitLevel = nil
    assert_nil(Compat.PlayerFaction())
    assert_nil((Compat.PlayerClass()))
    assert_eq(Compat.PlayerLevel(), 0)
  end)
end)
