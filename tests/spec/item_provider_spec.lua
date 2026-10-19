local H = require("harness")
local Mock = H.Mock

describe("ItemProvider", function()
  local ns, Items
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    Items = ns.ItemProvider
  end)

  it("parses ids, links and names", function()
    assert_deep_eq(Items.ParseInput("2996"), { kind = "id", itemID = 2996 })
    assert_deep_eq(Items.ParseInput(" 2996 "), { kind = "id", itemID = 2996 })
    assert_deep_eq(Items.ParseInput(2996), { kind = "id", itemID = 2996 })
    assert_deep_eq(Items.ParseInput("item:2996"), { kind = "id", itemID = 2996 })
    local link = "|cffffffff|Hitem:2996::::::::60:::::|h[Bolt of Linen Cloth]|h|r"
    local parsed = Items.ParseInput(link)
    assert_eq(parsed.kind, "link")
    assert_eq(parsed.itemID, 2996)
    assert_eq(parsed.name, "Bolt of Linen Cloth")
    assert_deep_eq(Items.ParseInput("Linen Cloth"), { kind = "name", name = "Linen Cloth" })
    assert_nil(Items.ParseInput(""))
    assert_nil(Items.ParseInput("   "))
    assert_nil(Items.ParseInput("0"))
    assert_nil(Items.ParseInput("-5"))
    assert_nil(Items.ParseInput(4.5))
    assert_nil(Items.ParseInput(nil))
  end)

  it("reports invalid item ids", function()
    local info = Items.GetItem(999999)
    assert_eq(info.exists, false)
    assert_eq(Items.Exists(0), false)
    assert_eq(Items.Exists(-1), false)
    assert_eq(#Mock.loadRequests, 0)
  end)

  it("returns loaded item data and caches the name", function()
    Mock.AddItem(2589, { name = "Linen Cloth", quality = 1 })
    local info = Items.GetItem(2589)
    assert_true(info.loaded)
    assert_eq(info.name, "Linen Cloth")
    assert_eq(info.quality, 1)
    assert_not_nil(info.icon)
    assert_eq(ns.db.itemNames[2589], "Linen Cloth")
    assert_eq(Items.GetName(2589), "Linen Cloth")
  end)

  it("requests unloaded items once and announces arrival", function()
    Mock.AddItem(2996, { name = "Bolt of Linen Cloth", loaded = false })
    local fired = {}
    ns.Events.On("FP_ITEM_LOADED", function(id, ok) fired[#fired + 1] = { id, ok } end)
    local info = Items.GetItem(2996)
    assert_false(info.loaded)
    assert_eq(info.name, "Bolt of Linen Cloth", "named by the catalogue while the client loads it")
    assert_eq(info.exists, true)
    Items.GetItem(2996)
    assert_eq(#Mock.loadRequests, 1, "only one load request while pending")
    Mock.LoadItem(2996)
    assert_eq(#fired, 1)
    assert_eq(fired[1][1], 2996)
    assert_true(fired[1][2])
    assert_eq(Items.GetItem(2996).name, "Bolt of Linen Cloth")
    assert_eq(ns.db.itemNames[2996], "Bolt of Linen Cloth")
  end)

  it("marks items the server refuses as unavailable", function()
    Mock.AddItem(4000, { name = "Ghost", loaded = false })
    Items.GetItem(4000)
    Mock.LoadItem(4000, false)
    local info = Items.GetItem(4000)
    assert_true(info.unavailable)
    assert_eq(#Mock.loadRequests, 1, "no retry after failure")
  end)

  it("uses the cached name while data is loading", function()
    Mock.AddItem(2996, { name = "Bolt of Linen Cloth", loaded = false })
    Items.RememberName(2996, "Bolt of Linen Cloth")
    assert_eq(Items.GetItem(2996).name, "Bolt of Linen Cloth")
    assert_eq(Items.GetName(123456789), "Item 123456789")
  end)

  it("searches names from the cache and scanned recipes", function()
    Items.RememberName(2589, "Linen Cloth")
    Items.RememberName(2996, "Bolt of Linen Cloth")
    Items.RememberName(4306, "Silk Cloth")
    ns.db.recipes[1] = { recipeID = 1, name = "Linen Bag", outputItemID = 4238 }
    local hits = Items.SearchByName("linen cloth")
    assert_eq(hits[1].itemID, 2589, "exact match first")
    assert_eq(hits[2].itemID, 2996, "substring match second")
    hits = Items.SearchByName("Linen", 20)
    assert_gt(#hits, 3, "the catalogue adds its own linen items")
    assert_eq(hits[1].name, "Linen Bag", "prefix matches sorted by name")
    assert_eq(hits[2].name, "Linen Bandage")
    assert_eq(#Items.SearchByName(""), 0)
    assert_eq(#Items.SearchByName("zzz"), 0)
    assert_eq(#Items.SearchByName("l", 2), 2)
  end)

  it("ranks word-start and inner matches and keeps room for them in a short list", function()
    assert_eq(Items.MatchRank("Storm Gauntlets", "storm"), 1)
    assert_eq(Items.MatchRank("Mace of the Storms", "storm"), 2)
    assert_eq(Items.MatchRank("Hand-Stormer", "storm"), 2)
    assert_eq(Items.MatchRank("Thunderstorm Blade", "storm"), 3)
    assert_eq(Items.MatchRank("storm", "storm"), 0)
    assert_nil(Items.MatchRank("Linen Cloth", "storm"))
    Items.RememberName(99001, "Mace of the Storms")
    Items.RememberName(99002, "Thunderstorm Blade")
    -- The catalogue has many "Storm..." items; a short list still shows the others.
    local hits = Items.SearchByName("storm", 5)
    assert_eq(#hits, 5)
    assert_eq(hits[1].rank, 1)
    assert_eq(hits[3].rank, 1, "three slots for names starting with it")
    assert_true(hits[4].rank >= 2, "two slots kept for later groups")
    assert_true(hits[5].rank >= 2)
    assert_eq(Items.SearchByName("mace of the storms", 5)[1].rank, 0)
    hits = Items.SearchByName("storm", 500)
    local sawMace, sawBlade, lastRank = false, false, 0
    for _, hit in ipairs(hits) do
      assert_true(hit.rank >= lastRank, "ordered by rank")
      lastRank = hit.rank
      if hit.name == "Mace of the Storms" then sawMace = true end
      if hit.name == "Thunderstorm Blade" then sawBlade = true end
    end
    assert_true(sawMace and sawBlade)
    -- A single result is always the best match, never a reserved one.
    assert_eq(Items.SearchByName("storm", 1)[1].rank, 1)
    -- Nothing is reserved when the earlier groups already fit.
    hits = Items.SearchByName("mace of the", 3)
    assert_eq(hits[1].name, "Mace of the Storms")
  end)

  it("searches names from the dungeon journal and GearQuest facts", function()
    ns = H.fresh()
    Mock.InstallDungeonJournal({
      ["Wailing Caverns"] = {
        bosses = { { name = "Kresh", npcID = 3653, loot = { { 10411, "Footpads of the Fang", "Feet, Leather", 3 } } } },
        quests = { { id = 96395, name = "An Ancient Grudge", faction = "Both", rewardItems = { { 279899, "Catacomb Cloak", 3 } } } },
      },
    }, { ["Wailing Caverns"] = { Kresh = { { 252512, "Brawler's Leather Helm", "Head, Leather", 3 } } } })
    Mock.InstallGearQuest({ entries = {}, facts = { [11111] = { name = "Zephras Watch Leggings", sourceType = "vendor" } } })
    H.login(ns)
    Items = ns.ItemProvider
    assert_eq(Items.SearchByName("footpads of the fang", 5)[1].itemID, 10411)
    assert_eq(Items.SearchByName("catacomb", 5)[1].itemID, 279899)
    assert_eq(Items.SearchByName("brawler's leather helm", 5)[1].itemID, 252512)
    assert_eq(Items.SearchByName("zephras watch legg", 5)[1].itemID, 11111)
    local names = ns.SourceProvider.JournalNames()
    assert_eq(names[10411], "Footpads of the Fang")
    assert_eq(ns.SourceProvider.JournalNames(), names, "built once")
  end)
end)
