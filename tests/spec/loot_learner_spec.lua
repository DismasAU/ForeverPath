local H = require("harness")
local Mock = H.Mock

local LEATHER, HIDE, LINEN, CLAM_MEAT, PEACEBLOOM = 2318, 783, 2589, 5503, 2447
local RAGE = 280604

describe("LootLearner", function()
  local ns, LL
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    LL = ns.LootLearner
    Mock.AddItem(LEATHER, { name = "Light Leather" })
    Mock.AddItem(HIDE, { name = "Light Hide" })
    Mock.AddItem(LINEN, { name = "Linen Cloth" })
    Mock.AddItem(CLAM_MEAT, { name = "Clam Meat" })
    Mock.AddItem(PEACEBLOOM, { name = "Peacebloom" })
  end)

  it("parses loot source GUIDs", function()
    assert_eq(select(1, LL.ParseGUID("Creature-0-1-2-3-116-0000ABCD")), "creature")
    assert_eq(select(2, LL.ParseGUID("Creature-0-1-2-3-116-0000ABCD")), 116)
    assert_eq(select(2, LL.ParseGUID("Vehicle-0-1-2-3-200-01")), 200)
    assert_eq(select(1, LL.ParseGUID("GameObject-0-1-2-3-1618-01")), "object")
    assert_nil(LL.ParseGUID("Player-1-0000ABCD"))
    assert_nil(LL.ParseGUID(nil))
  end)

  it("records corpses, items, skinning, objects and fishing, once per loot", function()
    assert_true(LL.IsAvailable())
    assert_match(LL.Status(), "^Loot learner: 0 items seen from 0 ")
    local wolf1 = Mock.CreatureGUID(525, 1)
    Mock.targetGUID, Mock.targetName = wolf1, "Mangy Wolf"
    Mock.OpenLoot({ { itemID = LINEN, quantity = 2, sources = { wolf1, 2 } } })
    -- LOOT_READY and LOOT_OPENED both fired: counted once.
    local entry = ns.db.lootSeen["c:525"]
    assert_eq(entry.name, "Mangy Wolf")
    assert_eq(entry.kind, "creature")
    assert_eq(entry.looted, 1)
    assert_eq(entry.items[LINEN].times, 1)
    assert_eq(entry.items[LINEN].quantity, 2)
    Mock.CloseLoot()
    -- The same corpse again: skinning.
    Mock.OpenLoot({ { itemID = LEATHER, quantity = 1, sources = { wolf1, 1 } } })
    Mock.CloseLoot()
    assert_eq(entry.looted, 1, "a second loot of one corpse is not another kill")
    assert_eq(entry.skinned[LEATHER].times, 1)
    assert_nil(entry.items[LEATHER])
    -- A second wolf without linen; area loot from two wolves in one window.
    local wolf2, wolf3 = Mock.CreatureGUID(525, 2), Mock.CreatureGUID(525, 3)
    Mock.targetGUID = nil
    Mock.OpenLoot({ { itemID = HIDE, quantity = 1, sources = { wolf2, 1 } }, { itemID = LINEN, quantity = 3, sources = { wolf2, 1, wolf3, 2 } } })
    Mock.CloseLoot()
    assert_eq(entry.looted, 3)
    assert_eq(entry.items[LINEN].times, 3)
    assert_eq(entry.items[LINEN].quantity, 5)
    assert_eq(entry.items[HIDE].times, 1)
    -- An object (a herb node) and fishing.
    Mock.OpenLoot({ { itemID = PEACEBLOOM, quantity = 2, sources = { Mock.ObjectGUID(1618, 9), 2 } } })
    Mock.CloseLoot()
    local node = ns.db.lootSeen["o:1618"]
    assert_eq(node.kind, "object")
    assert_eq(node.items[PEACEBLOOM].quantity, 2)
    Mock.zone = "Westfall"
    Mock.OpenLoot({ { itemID = CLAM_MEAT, quantity = 1 } }, { fishing = true })
    Mock.CloseLoot()
    assert_eq(ns.db.lootSeen["f:Westfall"].kind, "fishing")
    assert_eq(ns.db.lootSeen["f:Westfall"].name, "Westfall")
    assert_match(LL.Status(), "^Loot learner: 5 items seen from 3 ")
    -- Hints: likeliest first, chance from what was seen.
    local hints = LL.ItemHints(LINEN)
    assert_eq(#hints, 1)
    assert_eq(hints[1].label, "Dropped by Mangy Wolf")
    assert_eq(hints[1].kind, "drop")
    assert_true(hints[1].learned)
    assert_eq(hints[1].chance, 10000, "every wolf looted had linen")
    assert_eq(hints[1].detail, "Durotar - seen 3 times in 3 loots on Forever")
    assert_eq(LL.ItemHints(HIDE)[1].chance, 3333)
    assert_eq(LL.ItemHints(LEATHER)[1].label, "Skinned from Mangy Wolf")
    assert_eq(LL.ItemHints(LEATHER)[1].skill, "Skinning")
    assert_eq(LL.ItemHints(PEACEBLOOM)[1].label, "Looted from Object 1618", "no classic data to name it")
    assert_eq(LL.ItemHints(CLAM_MEAT)[1].label, "Fished in Westfall")
    -- SourceProvider: learned first, skinning qualified by who can skin.
    local sources = ns.SourceProvider.Sources(LINEN)
    assert_eq(sources[1].label, "Dropped by Mangy Wolf")
    local skin = ns.SourceProvider.Sources(LEATHER)[1]
    assert_eq(skin.label, "Skinned from Mangy Wolf")
    assert_true(skin.unavailable, "nobody skins")
    -- The planner routes the item to the observed drop.
    local goal = ns.GoalService.AddObtainGoal(HIDE, 2)
    local view = ns.Planner.Evaluate(goal)
    assert_eq(view.tree.root.route, "drop")
    assert_eq(view.sourceText, "Dropped by Mangy Wolf - Durotar - seen 1 time in 3 loots on Forever")
  end)

  it("puts what was looted on Forever ahead of classic data for the same creature", function()
    local data = {
      meta = { source = "CMaNGOS classic-db", commit = "abc" }, zones = { [1411] = "Durotar" }, instances = {}, quests = {},
      npcs = { [525] = { "Mangy Wolf", nil, 1, 2, 0, { 1411, 500, 500 }, 3 }, [526] = { "Other Wolf", nil, 3, 4, 0, { 1411, 600, 600 }, 3 } },
      objects = {},
      drops = { [LINEN] = { 2, 525, 1500, 526, 1200 } },
      itemRanges = { 1, 100000 },
    }
    Mock.addOnLoaders.ForeverPath_ClassicDB = function() ns.ClassicData = data end
    ns.ClassicDB.loadTried = false
    ns.ClassicDB.Init()
    local before = ns.SourceProvider.Sources(LINEN)
    assert_eq(before[1].label, "Dropped by Mangy Wolf")
    assert_true(before[1].classic)
    local wolf = Mock.CreatureGUID(525, 1)
    Mock.OpenLoot({ { itemID = LINEN, quantity = 1, sources = { wolf, 1 } } })
    Mock.CloseLoot()
    local after = ns.SourceProvider.Sources(LINEN)
    assert_eq(after[1].label, "Dropped by Mangy Wolf")
    assert_true(after[1].learned, "the observation comes first")
    assert_eq(after[2].label, "Dropped by Other Wolf", "the classic Mangy Wolf drop is not listed twice")
    assert_true(after[2].classic)
    assert_eq(ns.LootLearner.ItemHints(LINEN)[1].label, "Dropped by Mangy Wolf", "named from classic data when no target was selected")
    -- New in Forever: the client lists it, classic-db does not.
    assert_true(ns.ClassicDB.KnowsItem(LINEN))
    assert_false(ns.ClassicDB.KnowsItem(RAGE))
    assert_true(ns.ClassicDB.IsNewInForever(RAGE))
    assert_false(ns.ClassicDB.IsNewInForever(LINEN))
    local fresh = ns.SourceProvider.Sources(RAGE)
    assert_eq(#fresh, 1)
    assert_eq(fresh[1].label, "New in Forever")
    assert_true(fresh[1].unavailable)
    -- Once looted, the observation replaces the note.
    Mock.OpenLoot({ { itemID = RAGE, quantity = 1, sources = { Mock.CreatureGUID(525, 7), 1 } } })
    Mock.CloseLoot()
    assert_eq(ns.SourceProvider.Sources(RAGE)[1].label, "Dropped by Mangy Wolf")
  end)
end)

describe("Item index (client)", function()
  it("names, ranks and binds every searchable item, not just recipe items", function()
    local ns = H.fresh()
    H.login(ns)
    local R = ns.Data.Recipes
    assert_eq(R.ItemName(19019), "Thunderfury, Blessed Blade of the Windseeker")
    assert_eq(R.ItemQuality(19019), 5)
    assert_eq(R.ItemBind(19019), 1)
    assert_true(R.IsSoulbound(19019))
    assert_eq(R.IndexedItem(280604)[1], "Rage of the Storm")
    assert_eq(R.IndexedItem(280604)[6], 40, "item level")
    assert_eq(ns.ItemProvider.GetCachedName(280604), "Rage of the Storm")
    local hits = ns.ItemProvider.SearchByName("thunderfury", 5)
    assert_eq(hits[1].itemID, 19019)
    assert_eq(ns.ItemProvider.SearchByName("sulfuras, hand", 1)[1].itemID, 17182, "the real item before its TEST copy")
    assert_gt(ns.Util.Count(ns.Data.ItemIndex), 11000)
  end)
end)
