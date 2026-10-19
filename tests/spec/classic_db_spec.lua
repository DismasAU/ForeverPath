local H = require("harness")
local Mock = H.Mock

-- A small classic-db in the generated layout (see Providers/ClassicDBProvider.lua):
-- Gather Hides (100) -> Report to Sally (101, Alliance) -> The Final Test (102),
-- which also needs Option A (103) or Option B (104); a Horde-only quest (200)
-- and a shaman-only one (300).
local LEATHER, MEDIUM, SWORD, SHIELD, THREAD = 2318, 2319, 9001, 9002, 2320
local BOB, SALLY, WOLF = 500, 501, 600

local function fixture()
  return {
    meta = { source = "CMaNGOS classic-db", commit = "abcdef1234567890", quests = 6, npcs = 3, objects = 0 },
    zones = { [1429] = "Elwynn Forest", [1453] = "Stormwind City" },
    instances = { [36] = "Deadmines" },
    quests = {
      [100] = { "Gather Hides", 10, 8, 0, 0, 12, { BOB }, nil, nil, { BOB }, nil, { LEATHER, 6 }, nil, nil, { THREAD, 1 }, { 72, 250 }, nil, 101, nil, "Bring 6 Light Leather to Ranger Bob." },
      [101] = { "Report to Sally", 12, 8, 1, 0, 12, { BOB }, nil, nil, { SALLY }, nil, nil, nil, nil, nil, nil, { { 100 } }, 102, nil, "Speak with Sally." },
      [102] = { "The Final Test", 14, 10, 0, 0, 12, { SALLY }, nil, nil, { SALLY }, nil, { MEDIUM, 2 }, { WOLF, 5 }, { SWORD, 1, SHIELD, 1 }, nil, { 72, 500 }, { { 101 }, { 103, 104 } }, nil, nil, "Kill 5 Wolves and bring 2 Medium Leather." },
      [103] = { "Option A", 12, 8, 0, 0, 12, { SALLY }, nil, nil, { SALLY }, nil },
      [104] = { "Option B", 12, 8, 0, 0, 12, { SALLY }, nil, nil, { SALLY }, nil },
      [200] = { "Horde Thing", 12, 8, 2, 0, 14, { BOB }, nil, nil, { BOB }, nil, nil, nil, { SWORD, 1 }, nil, { 76, 100 } },
      [300] = { "Totem Call", 20, 20, 0, 64, -82, { SALLY }, nil, nil, { SALLY }, nil },
    },
    npcs = {
      [BOB] = { "Ranger Bob", nil, 20, 20, 2, { 1429, 420, 655 } },
      [SALLY] = { "Sally", "Quartermaster", 30, 30, 2, { -36, 0, 0, 1453, 500, 500 } },
      [WOLF] = { "Wolf", nil, 5, 6, 0, { 1429, 300, 300, 1429, 320, 310 } },
    },
    objects = {},
  }
end

local function items()
  Mock.AddItem(LEATHER, { name = "Light Leather" })
  Mock.AddItem(MEDIUM, { name = "Medium Leather" })
  Mock.AddItem(SWORD, { name = "Sword of Tests", quality = 3, bind = 1 })
  Mock.AddItem(SHIELD, { name = "Shield of Tests", quality = 3 })
  Mock.AddItem(THREAD, { name = "Coarse Thread" })
end

describe("ClassicDB (generated data)", function()
  it("loads ForeverPath_ClassicDB on demand and decodes the real tables", function()
    local ns = H.fresh()
    Mock.addOnLoaders.ForeverPath_ClassicDB = function() H.loadClassicDB() end
    H.login(ns)
    local CDB = ns.ClassicDB
    assert_true(CDB.IsAvailable())
    local quests, npcs = CDB.Counts()
    assert_gt(quests, 4000)
    assert_gt(npcs, 2000)
    assert_match(CDB.Status(), "^Classic data: %d+ quests, %d+ NPCs, %d+ objects from CMaNGOS classic%-db ec4f5961%.$")
    -- Every row has the documented shape.
    for questID, row in pairs(ns.ClassicData.quests) do
      assert_eq(type(row[1]), "string", "title of " .. questID)
      assert_true(row[4] == 0 or row[4] == 1 or row[4] == 2, "side of " .. questID)
      for _, group in ipairs(row[17] or {}) do
        assert_gt(#group, 0, "prerequisite group of " .. questID)
        for _, id in ipairs(group) do assert_eq(type(id), "number") end
      end
      for _, key in ipairs({ 12, 13, 14, 15, 16 }) do
        if row[key] then assert_eq(#row[key] % 2, 0, "pairs in field " .. key .. " of " .. questID) end
      end
    end
    for npcID, row in pairs(ns.ClassicData.npcs) do
      assert_eq(type(row[1]), "string", "name of npc " .. npcID)
      if row[6] then assert_eq(#row[6] % 3, 0, "spawn triples of npc " .. npcID) end
    end
    -- Known facts.
    local call = CDB.Quest(1531)
    assert_eq(call.name, "Call of Air")
    assert_eq(call.faction, "Horde")
    assert_eq(call.classMask, 64)
    assert_eq(CDB.Giver(1531).name, "Searn Firewarder")
    assert_eq(CDB.Giver(1531).zone, "Orgrimmar")
    assert_eq(CDB.Turnin(1531).name, "Prate Cloudseer")
    local prate = CDB.Npc(5905).spawns[1]
    assert_eq(prate.uiMapID, 1441)
    assert_true(math.abs(prate.x - 0.536) < 0.01 and math.abs(prate.y - 0.428) < 0.01, "Prate Cloudseer lands where Attune pins her")
    -- Leaders of the Fang's chain, as a Horde character.
    Mock.character.faction = "Horde"
    local order = CDB.ChainTo(914, function() return false end)
    assert_eq(order[#order], 914)
    assert_eq(order[1], 870, "The Forgotten Pools starts it")
    local seen = {}
    for _, id in ipairs(order) do seen[id] = true end
    for _, id in ipairs({ 877, 880, 1489, 1490 }) do assert_true(seen[id], "chain includes " .. id) end
    -- Fixed-only rewards are indexed (Call of Air gives the Air Totem, no choice).
    Mock.character.classID = 7
    local ids = {}
    for _, entry in ipairs(CDB.QuestsRewarding(5178)) do ids[entry.id] = true end
    assert_true(ids[1531] and ids[1532], "both Horde Call of Air quests reward the Air Totem")
    Mock.character.classID = 1
    assert_eq(#CDB.QuestsRewarding(5178), 0, "not for a warrior")
  end)

  it("says when the data addon is missing", function()
    local ns = H.fresh()
    H.login(ns)
    assert_false(ns.ClassicDB.IsAvailable())
    assert_match(ns.ClassicDB.Status(), "ForeverPath_ClassicDB is not loaded %(MISSING%)")
    assert_nil(ns.QuestProvider.Get(1531))
    assert_nil(ns.QuestProvider.ClassicQuestline(914))
    assert_eq(#ns.ClassicDB.Search("air"), 0)
  end)
end)

describe("Classic quests in ForeverPath", function()
  local ns, QP, CDB
  before_each(function()
    ns = H.fresh()
    local data = fixture()
    Mock.addOnLoaders.ForeverPath_ClassicDB = function() ns.ClassicData = data end
    H.login(ns)
    QP, CDB = ns.QuestProvider, ns.ClassicDB
    items()
  end)

  it("falls back to classic entries for names, givers, turn-ins, items and rewards", function()
    local entry = QP.Get(102)
    assert_eq(entry.source, "classic")
    assert_eq(entry.name, "The Final Test")
    assert_eq(entry.level, 14)
    assert_eq(entry.requires, 10)
    assert_eq(entry.faction, "Both")
    assert_eq(entry.instance, "Stormwind City", "the giver's zone: Sally's zone-map spawn beats her Deadmines one")
    assert_eq(entry.rewards[1].itemID, SWORD)
    assert_true(entry.rewardChoice)
    assert_eq(entry.kills[1].id, WOLF)
    assert_eq(entry.kills[1].count, 5)
    assert_eq(QP.Name(102), "The Final Test")
    local giver = QP.Giver(100)
    assert_eq(giver.name, "Ranger Bob")
    assert_eq(giver.label, "Ranger Bob - Elwynn Forest")
    assert_eq(giver.mapID, 1429)
    assert_eq(giver.x, 0.42)
    assert_eq(giver.y, 0.655)
    assert_true(giver.classic)
    assert_eq(QP.Turnin(101).name, "Sally")
    assert_eq(QP.Waypoint(100).mapID, 1429)
    local needed = QP.RequiredItems(100)
    assert_eq(#needed, 1)
    assert_eq(needed[1].itemID, LEATHER)
    assert_eq(needed[1].count, 6)
    assert_true(needed[1].classic)
    -- Learned facts and shipped rows win over classic data.
    ns.Data.QuestCatalogue[100] = { giver = { name = "Ranger Robert", mapID = 1429, x = 0.5, y = 0.5, zone = "Elwynn Forest" },
      turnin = { name = "Ranger Robert", mapID = 1429, x = 0.5, y = 0.5, zone = "Elwynn Forest" }, items = { { itemID = MEDIUM, name = "Medium Leather", count = 3 } } }
    assert_eq(QP.Giver(100).name, "Ranger Robert")
    assert_eq(QP.RequiredItems(100)[1].itemID, MEDIUM)
    ns.Data.QuestCatalogue[100] = nil
    -- Rewards: classic quests this character can take.
    local rewarding = QP.QuestsRewarding(SWORD)
    assert_eq(#rewarding, 1, "the Horde-only quest is left out for an Alliance warrior")
    assert_eq(rewarding[1].id, 102)
    Mock.character.faction = "Horde"
    rewarding = QP.QuestsRewarding(SWORD)
    assert_eq(#rewarding, 2)
    Mock.character.faction = "Alliance"
    -- Search: titles, filtered by faction and class.
    local hits = QP.Search("final", 5)
    assert_eq(hits[1].questID, 102)
    assert_eq(hits[1].where, "Stormwind City - level 14")
    assert_eq(#QP.Search("horde thing", 5), 0)
    assert_eq(#QP.Search("totem call", 5), 0, "shaman only")
    Mock.character.classID = 7
    assert_eq(QP.Search("totem call", 5)[1].questID, 300)
    Mock.character.classID = 1
    -- State: prerequisites lock it until each group has a completed member.
    assert_eq(QP.StateLabel(QP.State(102), QP.Get(102), 60), "Locked")
    Mock.CompleteQuest(101)
    assert_eq(QP.StateLabel(QP.State(102), QP.Get(102), 60), "Locked", "Option A or B still needed")
    Mock.CompleteQuest(104)
    assert_eq(QP.StateLabel(QP.State(102), QP.Get(102), 60), "Available")
    -- Describe and status say the data is classic.
    assert_match(QP.Describe(102, ns.ItemProvider.GetName)[1], "%(classic data%)$")
    assert_match(QP.Status(), "plus 7 classic quests")
    Mock.RunSlash("status")
    assert_output("Classic data: 7 quests, 3 NPCs, 0 objects from CMaNGOS classic%-db abcdef12")
  end)

  it("builds a questline from classic prerequisites", function()
    local line = QP.Questline(102)
    assert_not_nil(line)
    assert_true(line.classic)
    assert_eq(line.attune.name, "The Final Test chain")
    assert_eq(line.total, 4)
    assert_eq(line.steps[1].questID, 100)
    assert_eq(line.steps[2].questID, 101)
    assert_eq(line.steps[3].questID, 103, "the first option this character can take")
    assert_eq(line.steps[4].questID, 102)
    assert_eq(line.steps[1].location, "Elwynn Forest")
    assert_eq(line.steps[1].state, "current")
    assert_eq(line.steps[2].state, "locked")
    assert_eq(line.next.questID, 100)
    assert_eq(line.target.questID, 102)
    assert_eq(line.percent, 0)
    -- Taking Option B instead puts it in the line.
    Mock.CompleteQuest(100)
    Mock.CompleteQuest(104)
    line = QP.Questline(102)
    assert_eq(line.steps[3].questID, 104)
    assert_eq(line.done, 2)
    assert_eq(line.next.questID, 101)
    assert_eq(line.percent, 50)
    -- A quest with no prerequisites has no line.
    assert_nil(QP.Questline(100))
    -- A ForeverDungeonJournal chain is Forever-curated and wins.
    Mock.InstallDungeonJournal({ ["Test Dungeon"] = { quests = { { id = 102, name = "The Final Test", faction = "Both", pickup = "Sally, Stormwind City", turnin = "Sally, Stormwind City", rewardItems = {} } } } },
      {}, { chains = { [102] = { { id = 100, name = "Gather Hides" } } } })
    QP.Invalidate()
    assert_eq(QP.Get(102).source, "journal")
    assert_nil(QP.Questline(102))
    local giver = QP.Giver(102)
    assert_eq(giver.label, "Sally, Stormwind City", "the journal's text")
    assert_eq(giver.mapID, 1453, "with the classic position of the same NPC")
  end)

  it("plans a classic quest reward and a classic quest goal along the chain", function()
    local goal = ns.GoalService.AddItemGoal(SWORD, 1)
    local view = ns.Planner.Evaluate(goal)
    assert_not_nil(view.questline)
    assert_eq(view.questline.quest.id, 102)
    assert_eq(view.questline.line.attune.name, "The Final Test chain")
    assert_eq(view.nextStep, "Pick up Gather Hides from Ranger Bob in Elwynn Forest")
    assert_eq(view.message, "0 of 1 on hand. Reward from The Final Test (The Final Test chain, step 1 of 4). Next: Pick up Gather Hides from Ranger Bob in Elwynn Forest.")
    assert_eq(view.waypoint.mapID, 1429)
    local materials = {}
    for _, m in ipairs(view.plan.materials) do materials[m.itemID] = m.required end
    assert_eq(materials[SWORD], 1)
    assert_eq(materials[LEATHER], 6, "Gather Hides asks for 6 Light Leather")
    assert_eq(materials[MEDIUM], 2, "The Final Test asks for 2 Medium Leather")
    local list = ns.ShoppingList.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    local rows = {}
    for _, row in ipairs(list.rows) do rows[row.itemID] = row end
    assert_eq(rows[LEATHER].missing, 6)
    assert_eq(rows[MEDIUM].missing, 2)
    -- The quest itself as a goal.
    local questGoal = ns.GoalService.AddQuestGoal(102)
    assert_eq(questGoal.target.instance, "Stormwind City")
    local qv = ns.Planner.Evaluate(questGoal)
    assert_eq(qv.quest.label, "Locked")
    assert_eq(qv.message, "First pick up Gather Hides from Ranger Bob in Elwynn Forest (step 1 of 4 of The Final Test chain, before The Final Test).")
    for _, id in ipairs({ 100, 101, 104 }) do Mock.CompleteQuest(id) end
    Mock.RunTimers()
    qv = ns.Planner.Evaluate(questGoal)
    assert_eq(qv.quest.label, "Available")
    assert_eq(qv.message, "Pick up The Final Test from Sally in Stormwind City.")
    assert_eq(qv.waypoint.mapID, 1453)
    -- A buyable item a classic quest also rewards is not planned as that quest.
    local threadGoal = ns.GoalService.AddItemGoal(THREAD, 1)
    local tv = ns.Planner.Evaluate(threadGoal)
    assert_nil(tv.questline, "Coarse Thread binds to nobody: buy it")
    Mock.items[THREAD].bind = 4
    tv = ns.Planner.Evaluate(threadGoal)
    assert_eq(tv.questline.quest.id, 100, "a quest item is quested for")
    -- Adding by name finds classic quests too.
    local ok, message, byName = ns.GoalService.AddQuestFromInput("gather hides")
    assert_true(ok, message)
    assert_eq(byName.target.questID, 100)
  end)

  it("lists classic quests that give reputation", function()
    local RP = ns.ReputationProvider
    local quests = RP.QuestsFor("Stormwind", 72)
    assert_eq(#quests, 2)
    assert_eq(quests[1].questID, 102, "largest first")
    assert_eq(quests[1].amount, 500)
    assert_true(quests[1].classic)
    assert_eq(quests[2].questID, 100)
    assert_eq(#RP.QuestsFor("Orgrimmar", 76), 0, "Horde-only quest left out")
    Mock.character.faction = "Horde"
    assert_eq(RP.QuestsFor("Orgrimmar", 76)[1].questID, 200)
  end)
end)
