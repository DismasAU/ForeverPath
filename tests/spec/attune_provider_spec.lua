local H = require("harness")
local Mock = H.Mock

-- A trimmed Onyxia (Alliance, id 40) chain plus a Horde dungeon chain.
local function installAttune()
  Mock.InstallAttune({
    attunes = {
      { ID = "40", NAME = "Onyxia's Lair", GROUP = "RAIDS", FACTION = "Alliance", ICON = "Interface\\Icons\\inv_misc_head_dragon_01", GROUPSIZE = 40 },
      { ID = "30", NAME = "Onyxia's Lair", GROUP = "RAIDS", FACTION = "Horde", ICON = "Interface\\Icons\\inv_misc_head_dragon_01", GROUPSIZE = 40 },
      { ID = "163", NAME = "The Hall of Thanes", GROUP = "DUNGEONS", FACTION = "Alliance", LEVELS = "13-15", ICON = "Interface\\Icons\\inv_misc_statue_07", GROUPSIZE = 5 },
      { ID = "275", NAME = "The Drowned City", GROUP = "DUNGEONS", FACTION = "Both", LEVELS = "35-38", ICON = "x", GROUPSIZE = 5 },
    },
    steps = {
      { ID_ATTUNE = "40", ID = "10", TYPE = "Level", STEP = "Reach level 48", LOCATION = "", ID_WOWHEAD = "48", ICON = "lvl", FOLLOWS = "0", STAGE = "1" },
      { ID_ATTUNE = "40", ID = "20", TYPE = "Quest", STEP = "", LOCATION = "Burning Steppes", ID_WOWHEAD = "4182", ICON = "q", FOLLOWS = "10", STAGE = "2" },
      { ID_ATTUNE = "40", ID = "30", TYPE = "Quest", STEP = "", LOCATION = "Burning Steppes", ID_WOWHEAD = "4183", ICON = "q", FOLLOWS = "20", STAGE = "3" },
      { ID_ATTUNE = "40", ID = "35", TYPE = "Spacer", STEP = "Spacer", LOCATION = "", ID_WOWHEAD = "", ICON = "", FOLLOWS = "30", STAGE = "3" },
      { ID_ATTUNE = "40", ID = "110", TYPE = "Item", STEP = "", LOCATION = "Blackrock Depths", ID_WOWHEAD = "11446", ICON = "i", FOLLOWS = "30", STAGE = "4" },
      { ID_ATTUNE = "40", ID = "130", TYPE = "Pick Up", STEP = "", LOCATION = "Blackrock Depths", ID_WOWHEAD = "4282", ICON = "q", FOLLOWS = "110", STAGE = "5" },
      { ID_ATTUNE = "40", ID = "140", TYPE = "Kill", STEP = "", LOCATION = "Blackrock Depths", ID_WOWHEAD = "8983", ICON = "k", FOLLOWS = "130", STAGE = "6" },
      { ID_ATTUNE = "40", ID = "150", TYPE = "Kill", STEP = "", LOCATION = "Blackrock Depths", ID_WOWHEAD = "9033", ICON = "k", FOLLOWS = "130", STAGE = "6" },
      { ID_ATTUNE = "40", ID = "175", TYPE = "Turn In", STEP = "", LOCATION = "Blackrock Depths", ID_WOWHEAD = "4282", ICON = "q", FOLLOWS = "140&150", STAGE = "7" },
      { ID_ATTUNE = "40", ID = "180", TYPE = "Quest", STEP = "", LOCATION = "Blackrock Depths", ID_WOWHEAD = "4322", ICON = "q", FOLLOWS = "175", STAGE = "8" },
      { ID_ATTUNE = "40", ID = "270", TYPE = "End", STEP = "Attuned", LOCATION = "", ID_WOWHEAD = "0", ICON = "e", FOLLOWS = "180", STAGE = "9" },
      { ID_ATTUNE = "163", ID = "10", TYPE = "Level", STEP = "Reach level 10", LOCATION = "", ID_WOWHEAD = "10", ICON = "lvl", FOLLOWS = "0", STAGE = "10" },
      { ID_ATTUNE = "163", ID = "120", TYPE = "Pick Up", STEP = "", LOCATION = "Ironforge", ID_WOWHEAD = "96403", ICON = "q", FOLLOWS = "10", STAGE = "20" },
      { ID_ATTUNE = "163", ID = "130", TYPE = "Item", STEP = "", LOCATION = "The Hall of Thanes", ID_WOWHEAD = "274289", ICON = "i", FOLLOWS = "120", STAGE = "30", COUNT = 8 },
      { ID_ATTUNE = "163", ID = "140", TYPE = "Turn In", STEP = "", LOCATION = "Ironforge", ID_WOWHEAD = "96403", ICON = "q", FOLLOWS = "130", STAGE = "40" },
      { ID_ATTUNE = "163", ID = "420", TYPE = "Quest", STEP = "", LOCATION = "The Hall of Thanes", ID_WOWHEAD = "96395", ICON = "q", FOLLOWS = "0", STAGE = "50", SIDE = true },
      { ID_ATTUNE = "163", ID = "360", TYPE = "End", STEP = "Attuned", LOCATION = "", ID_WOWHEAD = "0", ICON = "e", FOLLOWS = "140&420", STAGE = "60" },
    },
    quests = { [4182] = { 48, 2 }, [4183] = { 48, 1 }, [4282] = { 50, 5 }, [4322] = { 50, 5 }, [96403] = { 10, 1 }, [96395] = { 10, 5 } },
    npcs = { [8983] = { "56", "Elite", "Golem Lord Argelmach" }, [9033] = { "57", "Elite", "General Angerforge" } },
  }, { lang = { Q1_4182 = "Dragonkin Menace", Q1_4183 = "The True Masters", Q1_4282 = "A Shred of Hope", Q1_4322 = "Jail Break!", Q1_96403 = "Important Heirlooms", Q1_96395 = "An Ancient Grudge" } })
end

describe("AttuneProvider", function()
  local ns, AP
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    AP = ns.AttuneProvider
    Mock.AddItem(11446, { name = "A Crumpled Up Note" })
    Mock.AddItem(274289, { name = "Dwarven Heirloom" })
  end)

  it("lists attunements for the player's faction, raids first, and resolves step names", function()
    assert_false(AP.IsAvailable())
    assert_eq(#AP.List(), 0)
    assert_eq(AP.Status(), "Attune not installed")
    installAttune()
    assert_true(AP.IsAvailable())
    local list = AP.List()
    assert_eq(#list, 3, "Alliance plus Both; the Horde Onyxia is left out")
    assert_eq(list[1].name, "Onyxia's Lair")
    assert_eq(list[1].id, "40")
    assert_eq(list[2].name, "The Hall of Thanes", "dungeons after raids, by level")
    assert_eq(list[3].name, "The Drowned City")
    assert_eq(#AP.List("Horde"), 2)
    assert_eq(AP.Find("onyxia").id, "40")
    assert_eq(AP.Find("hall of thanes").id, "163")
    assert_nil(AP.Find("zzz"))
    local steps = AP.Steps("40")
    assert_eq(#steps, 10, "spacers dropped")
    assert_eq(steps[1].name, "Reach level 48")
    assert_eq(steps[2].name, "Dragonkin Menace")
    assert_eq(steps[2].typeLabel, "Quest")
    assert_eq(steps[2].questLevel, 48)
    assert_eq(steps[2].groupSize, 2)
    assert_eq(steps[4].name, "A Crumpled Up Note")
    assert_eq(steps[5].typeLabel, "Pick up")
    assert_eq(steps[6].name, "Golem Lord Argelmach")
    assert_deep_eq(steps[8].follows, { "140", "150" })
    assert_eq(steps[10].type, "End")
    assert_match(AP.Status(), "3 attunements for Alliance")
  end)

  it("works out progress from quest flags, the log, level, bags, Attune's survey and inference", function()
    installAttune()
    Mock.character.level = 47
    local p = AP.Progress("40")
    assert_eq(p.total, 9)
    assert_eq(p.done, 0)
    assert_eq(p.percent, 0)
    assert_eq(p.next.name, "Reach level 48")
    assert_eq(p.steps[1].state, "current")
    assert_eq(p.steps[2].state, "locked")
    Mock.character.level = 50
    Mock.quests.completed[4182] = true
    p = AP.Progress("40")
    assert_eq(p.done, 2)
    assert_eq(p.next.name, "The True Masters")
    assert_eq(AP.StepText(p.next), "Quest: The True Masters - Burning Steppes")
    -- A later quest done implies everything before it.
    Mock.quests.completed[4282] = true
    p = AP.Progress("40")
    assert_true(p.steps[3].done, "The True Masters inferred")
    assert_true(p.steps[4].done, "the note too")
    assert_true(p.steps[6].done and p.steps[7].done, "both kills inferred from the turn-in")
    assert_eq(p.done, 8)
    assert_eq(p.next.name, "Jail Break!")
    assert_eq(p.percent, 89)
    -- The last quest in the log shows as current and in log, not done.
    Mock.quests.log[4322] = true
    p = AP.Progress("40")
    assert_true(p.steps[9].inLog)
    assert_eq(p.steps[9].state, "current")
    assert_false(p.complete)
    Mock.quests.completed[4322] = true
    p = AP.Progress("40")
    assert_true(p.complete)
    assert_eq(p.percent, 100)
    assert_nil(p.next)
    assert_eq(#p.current, 0)
    -- Kills come from Attune's survey when nothing later is done.
    Mock.quests = { completed = { [4182] = true, [4183] = true }, log = {} }
    Mock.SetBag(0, 16, { { 11446, 1 } })
    Mock.FireEvent("BAG_UPDATE_DELAYED")
    Mock.RunTimers()
    Mock.quests.log[4282] = true
    _G.Attune_DB = { toons = { ["Thandrel Stormhold"] = { done = { ["40-140"] = 1 } } } }
    p = AP.Progress("40")
    assert_true(p.steps[4].done, "note in bags")
    assert_true(p.steps[5].done, "pick-up counts once the quest is in the log")
    assert_true(p.steps[6].done, "Argelmach from Attune's survey")
    assert_false(p.steps[7].done)
    assert_eq(p.next.name, "General Angerforge")
    assert_eq(#p.current, 1)
  end)

  it("handles side quests, item counts and a chain with several ends", function()
    installAttune()
    Mock.character.level = 12
    Mock.quests.log[96403] = true
    Mock.SetBag(0, 16, { { 274289, 5 } })
    Mock.FireEvent("BAG_UPDATE_DELAYED")
    Mock.RunTimers()
    local p = AP.Progress("163")
    assert_eq(p.total, 5)
    assert_eq(p.done, 2)
    assert_eq(p.next.name, "Dwarven Heirloom", "5 of 8 collected")
    assert_eq(AP.StepText(p.next), "Item: Dwarven Heirloom x8 - The Hall of Thanes")
    assert_eq(#p.current, 2, "the side quest is open from the start")
    assert_true(p.current[2].side)
    Mock.quests.completed[96403] = true
    Mock.quests.completed[96395] = true
    p = AP.Progress("163")
    assert_true(p.complete)
    assert_eq(p.done, 5)
    assert_nil((AP.Progress("999")))
  end)
end)
