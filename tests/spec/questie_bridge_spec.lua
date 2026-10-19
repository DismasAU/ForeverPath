local H = require("harness")
local Mock = H.Mock

local CALL_A, AID, TEMPEST = 1531, 79360, 79442
local PRATE, RAU, SEARN = 5905, 4722, 3344
local NOTE, RAGE = 274463, 280604

-- Questie's Forever data in the shapes its QuestieDB returns.
local function questie()
  return {
    zones = { [400] = 1441, [1637] = 1454 },
    npcs = {
      [PRATE] = { name = "Prate Cloudseer", minLevel = 37, spawns = { [400] = { { 53.6, 42.8 } } } },
      [RAU] = { name = "Rau Cliffrunner", spawns = { [400] = { { 46.0, 51.6 } } } },
      [SEARN] = { name = "Searn Firewarder", spawns = { [1637] = { { 37.8, 37.4 } } } },
    },
    quests = {
      [CALL_A] = { name = "Call of Air", questLevel = 30, requiredLevel = 30, requiredRaces = 178, requiredClasses = 64,
        startedBy = { { SEARN } }, finishedBy = { { PRATE } }, objectives = {} },
      [AID] = { name = "Elemental Aid", questLevel = 33, requiredLevel = 30, requiredRaces = 178, requiredClasses = 64,
        startedBy = { { PRATE } }, finishedBy = { { RAU } }, preQuestSingle = { CALL_A, 1532 },
        objectives = { nil, nil, { { NOTE, "Tattered Note" } } }, objectivesText = { "Defeat Charlga Razorflank." } },
      [TEMPEST] = { name = "The Tempest's Weapons", questLevel = 40, requiredLevel = 30, requiredRaces = 178, requiredClasses = 64,
        startedBy = { { RAU } }, finishedBy = { { RAU } }, preQuestGroup = { AID }, objectives = {} },
    },
    items = { [RAGE] = { name = "Rage of the Storm", questRewards = { TEMPEST } } },
  }
end

describe("Questie bridge", function()
  local ns, QP, QB
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    QP, QB = ns.QuestProvider, ns.QuestieBridge
    ns.Data.QuestCatalogue = {}
    Mock.mapNames = { [1441] = "Thousand Needles", [1454] = "Orgrimmar" }
    Mock.AddItem(NOTE, { name = "Tattered Note" })
    Mock.AddItem(RAGE, { name = "Rage of the Storm", quality = 3, bind = 1 })
  end)

  it("stays out of the way without Questie", function()
    assert_false(QB.IsAvailable())
    assert_match(QB.Status(), "^Questie: not installed")
    assert_nil(QB.Quest(AID))
    assert_nil(QP.Get(AID))
  end)

  it("reads Questie's quests, givers, items and chains behind Forever data", function()
    Mock.InstallQuestie(questie())
    QB.Reset()
    assert_true(QB.IsAvailable())
    assert_match(QB.Status(), "quest database available")
    local entry = QP.Get(AID)
    assert_eq(entry.source, "questie")
    assert_eq(entry.name, "Elemental Aid")
    assert_eq(entry.faction, "Horde")
    assert_eq(entry.classMask, 64)
    assert_eq(entry.level, 33)
    assert_eq(entry.location, "Thousand Needles")
    assert_eq(entry.objective, "Defeat Charlga Razorflank.")
    assert_eq(entry.prerequisites[1][1], CALL_A, "preQuestSingle is one any-of group")
    local giver = QP.Giver(AID)
    assert_eq(giver.name, "Prate Cloudseer")
    assert_eq(giver.mapID, 1441)
    assert_eq(giver.x, 0.536)
    assert_eq(giver.label, "Prate Cloudseer - Thousand Needles")
    assert_eq(QP.Turnin(AID).name, "Rau Cliffrunner")
    local items = QP.RequiredItems(AID)
    assert_eq(items[1].itemID, NOTE)
    assert_true(items[1].questie)
    assert_match(QP.Describe(AID, ns.ItemProvider.GetName)[1], "%(Questie%)$")
    assert_match(QP.Status(), "known from Questie")
    -- Class and faction: a Horde shaman can take it, a warrior cannot.
    Mock.character.faction = "Horde"
    Mock.character.classID = 1
    assert_false(QP.Eligible(entry))
    assert_eq(#QP.QuestsRewarding(RAGE), 0)
    Mock.character.classID = 7
    assert_true(QP.Eligible(entry))
    local rewarding = QP.QuestsRewarding(RAGE)
    assert_eq(rewarding[1].id, TEMPEST)
    -- The chain: Call of Air -> Elemental Aid -> The Tempest's Weapons (preQuestGroup).
    local line = QP.Questline(TEMPEST)
    assert_not_nil(line)
    assert_eq(line.total, 3)
    assert_eq(line.steps[1].questID, CALL_A)
    assert_eq(line.steps[1].location, "Orgrimmar")
    assert_true(line.steps[1].questie)
    assert_eq(line.next.questID, CALL_A)
    -- The reward goal plans along it.
    local goal = ns.GoalService.AddItemGoal(RAGE, 1)
    local view = ns.Planner.Evaluate(goal)
    assert_eq(view.questline.quest.id, TEMPEST)
    assert_eq(view.nextStep, "Pick up Call of Air from Searn Firewarder in Orgrimmar")
    assert_eq(view.waypoint.mapID, 1454)
    local materials = {}
    for _, m in ipairs(view.plan.materials) do materials[m.itemID] = m.required end
    assert_eq(materials[NOTE], 1, "Elemental Aid's item from Questie")
    -- Forever data wins: the shipped catalogue names another giver.
    ns.Data.QuestCatalogue[AID] = { giver = { name = "Someone Forever", mapID = 1441, x = 0.1, y = 0.1, zone = "Thousand Needles" } }
    assert_eq(QP.Giver(AID).name, "Someone Forever")
    ns.Data.QuestCatalogue[AID] = nil
    -- Questie wins over classic-db for a quest both know.
    local classic = {
      meta = { source = "CMaNGOS classic-db", commit = "abc" }, zones = { [1454] = "Orgrimmar" }, instances = {},
      quests = { [CALL_A] = { "Call of Air (classic)", 30, 30, 2, 64, -82, { 999 }, nil, nil, { 999 }, nil } },
      npcs = { [999] = { "Classic Giver", nil, 30, 30, 2, { 1454, 100, 100 } } }, objects = {},
    }
    Mock.addOnLoaders.ForeverPath_ClassicDB = function() ns.ClassicData = classic end
    ns.ClassicDB.loadTried = false
    ns.ClassicDB.Init()
    assert_eq(QP.Get(CALL_A).name, "Call of Air", "Questie's entry")
    assert_eq(QP.Giver(CALL_A).name, "Searn Firewarder")
    -- Without Questie the classic entry takes over.
    _G.QuestieLoader = nil
    QB.Reset()
    assert_eq(QP.Get(CALL_A).name, "Call of Air (classic)")
    assert_eq(QP.Giver(CALL_A).name, "Classic Giver")
  end)
end)
