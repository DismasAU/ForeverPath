local H = require("harness")
local Mock = H.Mock

-- The Horde shaman "Call of Air" class chain as Attune ships it (0.17.0):
-- two alternative starts, then five Forever quests ending in The Tempest's
-- Weapons, which rewards Rage of the Storm.
local CALL_A, CALL_B = 1532, 1531
local AID, EYES, STORM, HEED, TEMPEST = 79360, 79364, 79361, 79366, 79442
local RAGE, CLAW, GRASP, RUNE = 280604, 280605, 280607, 213086
local FIRE, EARTH, AIR, WATER = 274044, 274045, 274047, 274046
local MAGE_Q = 1920

local function installAttune()
  local function step(id, questID, follows, stage, extra)
    local s = { ID_ATTUNE = "5235", ID = id, TYPE = "Quest", STEP = "", LOCATION = "Thousand Needles", ID_WOWHEAD = tostring(questID), ICON = "q", FOLLOWS = follows, STAGE = stage }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
  end
  Mock.InstallAttune({
    attunes = {
      { ID = "5235", NAME = "Call of Air", GROUP = "CLASS_SHAMAN", CLASS = "SHAMAN", FACTION = "Horde", ICON = "air", GROUPSIZE = 1, LEVELS = "30-40" },
      { ID = "5136", NAME = "Mage's Wand", GROUP = "CLASS_MAGE", CLASS = "MAGE", FACTION = "Both", ICON = "wand", GROUPSIZE = 1, LEVELS = "30" },
    },
    steps = {
      { ID_ATTUNE = "5235", ID = "10", TYPE = "Level", STEP = "Reach level 30", LOCATION = "", ID_WOWHEAD = "30", ICON = "l", FOLLOWS = "0", STAGE = "10" },
      step("20", CALL_A, "10", "20", { OR = true }),
      step("25", CALL_B, "10", "20", { OR = true }),
      step("30", AID, "20|25", "30"),
      step("40", EYES, "30", "40"),
      step("50", STORM, "40", "50"),
      step("60", HEED, "50", "60"),
      step("70", TEMPEST, "60", "70"),
      { ID_ATTUNE = "5235", ID = "80", TYPE = "End", STEP = "Attuned", LOCATION = "", ID_WOWHEAD = "0", ICON = "e", FOLLOWS = "70", STAGE = "80" },
      { ID_ATTUNE = "5136", ID = "10", TYPE = "Quest", STEP = "", LOCATION = "Stormwind City", ID_WOWHEAD = tostring(MAGE_Q), ICON = "q", FOLLOWS = "0", STAGE = "10" },
      { ID_ATTUNE = "5136", ID = "20", TYPE = "End", STEP = "Attuned", LOCATION = "", ID_WOWHEAD = "0", ICON = "e", FOLLOWS = "10", STAGE = "20" },
    },
    quests = { [CALL_A] = { 30, 1 }, [CALL_B] = { 30, 1 }, [AID] = { 30, 1 }, [EYES] = { 30, 1 }, [STORM] = { 30, 1 }, [HEED] = { 30, 1 }, [TEMPEST] = { 30, 1 }, [MAGE_Q] = { 30, 1 } },
    questRewards = { [TEMPEST] = { choice = { { RAGE, 1 }, { CLAW, 1 }, { GRASP, 1 } }, fixed = { { RUNE, 1 } } } },
  }, { lang = {
    ["Q1_" .. CALL_A] = "Call of Air", ["Q1_" .. CALL_B] = "Call of Air", ["Q1_" .. AID] = "Elemental Aid", ["Q1_" .. EYES] = "Eyes on the Sky",
    ["Q1_" .. STORM] = "Storm, Earth, and Fire", ["Q1_" .. HEED] = "Heed My Call", ["Q1_" .. TEMPEST] = "The Tempest's Weapons", ["Q1_" .. MAGE_Q] = "Investigate the Blue Recluse",
  } })
end

local function shaman()
  Mock.character.faction = "Horde"
  Mock.character.class, Mock.character.classFile, Mock.character.classID = "Shaman", "SHAMAN", 7
  Mock.character.level = 60
end

local function items()
  Mock.AddItem(RAGE, { name = "Rage of the Storm", quality = 3, itemType = "Weapon", itemSubType = "Two-Handed Maces" })
  Mock.AddItem(CLAW, { name = "Tidebringer's Claw", quality = 3 })
  Mock.AddItem(GRASP, { name = "Lightning's Grasp", quality = 3 })
  Mock.AddItem(RUNE, { name = "Rune of the Storm", quality = 1 })
  Mock.AddItem(FIRE, { name = "Twisted Fire Totem", quality = 1 })
  Mock.AddItem(EARTH, { name = "Twisted Earth Totem", quality = 1 })
  Mock.AddItem(AIR, { name = "Twisted Air Totem", quality = 1 })
  Mock.AddItem(WATER, { name = "Twisted Water Totem", quality = 1 })
end

-- Names the client has shown this account (an item seen once is searchable).
local function seen(ns, ...)
  for _, itemID in ipairs({ ... }) do ns.ItemProvider.GetItem(itemID) end
end

describe("Questlines", function()
  local ns, QP
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    QP = ns.QuestProvider
    installAttune()
    items()
    seen(ns, RAGE, FIRE, EARTH, AIR, WATER)
    -- The shipped catalogue covers this very chain; these tests supply their own facts.
    ns.Data.QuestCatalogue = {}
    QP.Invalidate()
  end)

  it("finds the chain that leads to a quest for this class and faction", function()
    -- A warrior has no shaman chain; a Horde shaman does.
    assert_nil(QP.Questline(TEMPEST), "class chains are filtered by class")
    shaman()
    local line = QP.Questline(TEMPEST)
    assert_not_nil(line)
    assert_eq(line.attune.name, "Call of Air")
    assert_eq(line.attune.class, "SHAMAN")
    assert_eq(#line.steps, 8, "level, two alternative starts, five quests")
    assert_eq(line.total, 8)
    assert_eq(line.done, 1, "level 30 is reached")
    assert_eq(line.percent, 13)
    assert_eq(line.steps[1].type, "Level")
    assert_true(line.steps[1].done)
    assert_eq(line.steps[2].questID, CALL_A)
    assert_true(line.steps[2].alternative)
    assert_eq(line.steps[2].entry.name, "Call of Air")
    assert_false(line.steps[2].questState.completed)
    assert_eq(line.next, line.steps[2])
    assert_eq(line.target.questID, TEMPEST)
    assert_false(line.complete)
    assert_eq(line.steps[8].name, "The Tempest's Weapons")
    -- A quest in the middle of the chain only needs what comes before it.
    local partial = QP.Questline(AID)
    assert_eq(#partial.steps, 4)
    assert_eq(partial.target.questID, AID)
    -- Taking one of the alternative starts drops the other from the line.
    Mock.CompleteQuest(CALL_A)
    line = QP.Questline(TEMPEST)
    assert_eq(#line.steps, 7)
    assert_eq(line.steps[2].questID, CALL_A)
    assert_eq(line.steps[3].questID, AID)
    assert_eq(line.done, 2)
    assert_eq(line.next.questID, AID)
    -- The whole chain done.
    for _, id in ipairs({ AID, EYES, STORM, HEED, TEMPEST }) do Mock.CompleteQuest(id) end
    line = QP.Questline(TEMPEST)
    assert_true(line.complete)
    assert_eq(line.percent, 100)
    assert_nil(line.next)
    -- Faction: an Alliance shaman does not get the Horde chain.
    Mock.character.faction = "Alliance"
    assert_nil(QP.Questline(TEMPEST))
    -- The mage chain is found by a mage of either faction.
    Mock.character.classFile = "MAGE"
    assert_eq(QP.Questline(MAGE_Q).attune.name, "Mage's Wand")
    assert_eq(QP.Questline(MAGE_Q).next.questID, MAGE_Q)
  end)

  it("plans a quest-reward item as the chain that leads to it", function()
    shaman()
    local goal, message = ns.GoalService.AddItemGoal(RAGE, 1)
    assert_eq(goal.type, "OBTAIN_ITEM", message)
    local view = ns.Planner.Evaluate(goal)
    assert_eq(view.status, ns.Status.OK)
    assert_not_nil(view.questline)
    assert_eq(view.questline.quest.id, TEMPEST)
    assert_eq(view.questline.line.attune.name, "Call of Air")
    assert_eq(view.hint.label, "Quest reward: The Tempest's Weapons")
    assert_eq(view.sourceText, "Quest reward: The Tempest's Weapons - Call of Air")
    assert_eq(view.nextStep, "Pick up Call of Air in Thousand Needles", "no giver recorded yet: the step's zone")
    assert_eq(view.message, "0 of 1 on hand. Reward from The Tempest's Weapons (Call of Air, step 2 of 8). Next: Pick up Call of Air in Thousand Needles.")
    assert_nil(view.waypoint, "no map position recorded")
    assert_eq(view.tree.root.route, "quest")
    assert_nil(view.tree.root.noRoute)
    assert_eq(#view.plan.materials, 1)
    local overview = ns.Overview.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_eq(overview.nextSteps[1].title, "Pick up Call of Air in Thousand Needles")
    assert_eq(overview.nextSteps[1].detail, "Call of Air - step 2 of 8 - rewards Rage of the Storm")
    assert_eq(overview.nextSteps[1].badge, "Quest")
    -- Shipped facts name the giver and give the map pin.
    ns.Data.QuestCatalogue[CALL_A] = { giver = { name = "Prate Cloudseer", mapID = 1441, x = 0.4512, y = 0.5033, zone = "Thousand Needles" } }
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.nextStep, "Pick up Call of Air from Prate Cloudseer in Thousand Needles")
    assert_eq(view.waypoint.mapID, 1441)
    assert_eq(view.waypoint.label, "Prate Cloudseer - Thousand Needles")
    local ok, text = QP.SetWaypoint(view.waypoint)
    assert_true(ok, text)
    assert_eq(text, "Waypoint set: Prate Cloudseer - Thousand Needles.")
    assert_eq(Mock.waypoint.uiMapID, 1441)
    assert_eq(Mock.waypoint.position.x, 0.4512)
    assert_true(Mock.superTracked)
    Mock.waypointMaps = {}
    ok, text = QP.SetWaypoint(view.waypoint)
    assert_false(ok)
    assert_eq(text, "The map does not allow waypoints here.")
    Mock.waypointMaps = nil
    assert_false((QP.SetWaypoint(nil)))
    -- Working through the chain moves the next step along.
    Mock.AcceptQuest(CALL_A, { title = "Call of Air", level = 30, zone = "Thousand Needles", objectives = { { text = "Speak with the wind", type = "event", numRequired = 0 } } })
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.nextStep, "Finish Call of Air: Speak with the wind")
    assert_nil(view.waypoint, "no pin while objectives are in progress")
    Mock.SetQuestObjective(CALL_A, 1, 1, true)
    ns.Data.QuestCatalogue[CALL_A].turnin = { name = "Prate Cloudseer", mapID = 1441, x = 0.4512, y = 0.5033, zone = "Thousand Needles" }
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.nextStep, "Turn in Call of Air to Prate Cloudseer in Thousand Needles")
    assert_eq(view.waypoint.mapID, 1441)
    Mock.CompleteQuest(CALL_A)
    Mock.RunTimers()
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.nextStep, "Pick up Elemental Aid in Thousand Needles")
    assert_match(view.message, "step 3 of 7")
    -- The reward lands in the bags: done, chain or not.
    Mock.SetBag(0, 16, { { RAGE, 1 } })
    Mock.FireEvent("BAG_UPDATE_DELAYED")
    Mock.RunTimers()
    view = ns.Planner.Evaluate(goal)
    assert_true(view.plan.isComplete)
    assert_match(view.message, "^All 1 x Rage of the Storm on hand")
    -- A character the chain does not apply to still sees the reward quest, without a chain.
    Mock.SetBag(0, 16, {})
    Mock.FireEvent("BAG_UPDATE_DELAYED")
    Mock.RunTimers()
    Mock.character.classFile = "WARRIOR"
    view = ns.Planner.Evaluate(goal)
    assert_not_nil(view.questline)
    assert_nil(view.questline.line)
    assert_eq(view.nextStep, "Pick up The Tempest's Weapons in Thousand Needles")
    assert_eq(view.message, "0 of 1 on hand. Reward from The Tempest's Weapons. Next: Pick up The Tempest's Weapons in Thousand Needles.")
  end)

  it("brings what the chain's quests ask for into the tree, the requirements and the shopping list", function()
    shaman()
    for _, id in ipairs({ CALL_A, AID, EYES }) do Mock.CompleteQuest(id) end
    Mock.AcceptQuest(STORM, { title = "Storm, Earth, and Fire", level = 30, zone = "Thousand Needles", objectives = {
      { text = "Twisted Fire Totem: 0/5", type = "item", numFulfilled = 0, numRequired = 5 },
      { text = "Twisted Earth Totem: 2/5", type = "item", numFulfilled = 2, numRequired = 5 },
      { text = "Twisted Air Totem: 5/5", type = "item", numFulfilled = 5, numRequired = 5, finished = true },
    } })
    Mock.SetBag(0, 16, { { EARTH, 2 }, { AIR, 5 } })
    Mock.RunTimers()
    local needed = QP.RequiredItems(STORM)
    assert_eq(#needed, 3)
    assert_eq(needed[1].itemID, FIRE)
    assert_eq(needed[1].count, 5)
    assert_eq(needed[2].have, 2)
    -- The reward item's goal.
    local goal = ns.GoalService.AddItemGoal(RAGE, 1)
    local view = ns.Planner.Evaluate(goal)
    assert_eq(view.nextStep, "Finish Storm, Earth, and Fire: 0/5 Twisted Fire Totem: 0/5, 2/5 Twisted Earth Totem: 2/5, 5/5 Twisted Air Totem: 5/5")
    local root = view.tree.root
    assert_eq(#root.children, 3)
    assert_eq(root.children[1].itemID, FIRE)
    assert_eq(root.children[1].quantity, 5)
    assert_eq(root.children[1].missing, 5)
    assert_true(root.children[1].questItem)
    assert_eq(root.children[1].questName, "Storm, Earth, and Fire")
    assert_eq(root.children[2].owned, 2)
    assert_eq(root.children[2].missing, 3)
    assert_eq(root.children[3].missing, 0)
    assert_eq(#view.plan.materials, 4, "the item and three quest items")
    assert_eq(view.plan.materials[2].itemID, FIRE)
    assert_eq(view.plan.totals.materialsMissing, 3)
    assert_eq(view.questline.items[1].name, "Twisted Fire Totem")
    -- The reward is still a leaf: the Quests screen keeps listing its quest as feeding the goal.
    local leafIDs = {}
    for _, leaf in ipairs(view.tree.summary.missingLeaves) do leafIDs[leaf.itemID] = leaf.count end
    assert_eq(leafIDs[RAGE], 1)
    assert_eq(leafIDs[FIRE], 5)
    assert_eq(leafIDs[EARTH], 3)
    assert_nil(leafIDs[AIR])
    local feeds = QP.FeedsGoals({ goal }, { [goal.id] = view }, ns.GoalService.Name)
    assert_not_nil(feeds[TEMPEST])
    assert_eq(feeds[TEMPEST].goals[1].itemID, RAGE)
    -- Shopping list rows.
    local list = ns.ShoppingList.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    local rows = {}
    for _, row in ipairs(list.rows) do rows[row.itemID] = row end
    assert_eq(rows[FIRE].missing, 5)
    assert_eq(rows[EARTH].missing, 3)
    assert_eq(rows[EARTH].owned, 2)
    assert_nil(rows[AIR], "nothing missing")
    assert_eq(rows[RAGE].category, "gather")
    assert_eq(rows[RAGE].goals[1], "Rage of the Storm")
    assert_eq(rows[FIRE].goals[1], "Rage of the Storm")
    -- Overview: the next step stays the quest, the missing list carries the totems.
    local overview = ns.Overview.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_match(overview.nextSteps[1].title, "^Finish Storm, Earth, and Fire")
    local missing = {}
    for _, m in ipairs(overview.missing) do missing[m.itemID] = m.count end
    assert_eq(missing[FIRE], 5)
    assert_eq(missing[EARTH], 3)
    assert_eq(missing[RAGE], 1)
    -- A quest goal for the chain's end carries the same items.
    local questGoal = ns.GoalService.AddQuestGoal(TEMPEST)
    local qv = ns.Planner.Evaluate(questGoal)
    assert_eq(qv.quest.line.attune.name, "Call of Air")
    assert_eq(qv.quest.label, "Locked")
    assert_eq(#qv.quest.items, 3)
    assert_eq(qv.tree.root.step.kind, "quest")
    assert_eq(qv.tree.root.route, "quest")
    assert_eq(#qv.tree.root.children, 3)
    assert_eq(#qv.plan.materials, 3)
    assert_eq(qv.plan.totals.materialsMissing, 2)
    assert_false(qv.plan.isComplete)
    assert_eq(qv.progress.percent, 57, "4 of 7 steps")
    assert_match(qv.message, "^First finish Storm, Earth, and Fire: .* %(step 5 of 7 of Call of Air, before The Tempest's Weapons%)%.$")
    assert_match(qv.nextStep, "^Finish Storm, Earth, and Fire")
    local lines = QP.Describe(TEMPEST, ns.ItemProvider.GetName)
    local joined = table.concat(lines, "\n")
    assert_match(joined, "Chain: Call of Air %- 4 of 7 steps done")
    assert_match(joined, "1%. %[x%] Level: Reach level 30")
    assert_match(joined, "5%. %[>%] Quest: Storm, Earth, and Fire %- Thousand Needles")
    assert_match(joined, "Reward %(choose one%): Rune of the Storm, Rage of the Storm")
    -- The quest goal's own quest, once reached, lists the items it asks for.
    local stormLines = table.concat(QP.Describe(STORM, ns.ItemProvider.GetName), "\n")
    assert_match(stormLines, "Needs: 5 x Twisted Fire Totem\n")
    assert_match(stormLines, "Needs: 5 x Twisted Earth Totem %(2/5%)")
    local quest2 = ns.GoalService.AddQuestGoal(STORM)
    local sv = ns.Planner.Evaluate(quest2)
    assert_eq(sv.quest.label, "In log")
    assert_eq(#sv.plan.materials, 3)
    assert_match(sv.message, "^Finish Storm, Earth, and Fire: ")
    -- Without any chain, a plain quest goal still lists its live items.
    Mock.character.classFile = "WARRIOR"
    sv = ns.Planner.Evaluate(quest2)
    assert_nil(sv.quest.line)
    assert_eq(#sv.plan.materials, 3)
  end)

  it("learns givers, items and turn-ins at quest windows and keeps them on the account", function()
    shaman()
    local QF = ns.QuestFactsProvider
    assert_match(QF.Status(), "^Quest facts: 0 quests shipped, 0 learned")
    -- Objective parsing.
    local name, have, need, kill = QF.ParseObjective("Twisted Fire Totem: 0/5")
    assert_eq(name, "Twisted Fire Totem") assert_eq(have, 0) assert_eq(need, 5) assert_false(kill)
    name, have, need = QF.ParseObjective("3/20 Deviate Hide")
    assert_eq(name, "Deviate Hide") assert_eq(have, 3) assert_eq(need, 20)
    name, have, need, kill = QF.ParseObjective("Lord Cobrahn slain: 0/1")
    assert_eq(name, "Lord Cobrahn") assert_true(kill)
    assert_eq((QF.ParseObjective("Explore the place")), "Explore the place")
    assert_nil(QF.ParseObjective(nil))
    assert_nil(QP.Facts(STORM))
    -- The giver window: name and position.
    Mock.position = { mapID = 1441, x = 0.45123, y = 0.50331 }
    Mock.zone, Mock.subzone = "Thousand Needles", "Freewind Post"
    Mock.OfferQuest(STORM, "Prate Cloudseer")
    local learned = ns.db.questFacts[STORM]
    assert_not_nil(learned)
    assert_eq(learned.giver.name, "Prate Cloudseer")
    assert_eq(learned.giver.mapID, 1441)
    assert_eq(learned.giver.x, 0.4512)
    assert_eq(learned.giver.y, 0.5033)
    assert_eq(learned.giver.zone, "Thousand Needles")
    assert_eq(learned.giver.subzone, "Freewind Post")
    assert_not_nil(learned.giver.seenAt)
    local giver = QP.Giver(STORM)
    assert_eq(giver.label, "Prate Cloudseer - Thousand Needles")
    assert_eq(QP.Waypoint(STORM).mapID, 1441)
    -- Accepting records the item objectives; unknown names resolve later.
    Mock.AcceptQuest(STORM, { title = "Storm, Earth, and Fire", level = 30, zone = "Thousand Needles", objectives = {
      { text = "Twisted Fire Totem: 0/5", type = "item", numFulfilled = 0, numRequired = 5 },
      { text = "Mystery Widget: 0/3", type = "item", numFulfilled = 0, numRequired = 3 },
      { text = "Pridewing Wyvern slain: 0/4", numFulfilled = 0, numRequired = 4 },
      { text = "Speak with the wind", type = "event", numRequired = 0 },
    } })
    Mock.CloseQuestWindow()
    learned = ns.db.questFacts[STORM]
    assert_eq(#learned.items, 2, "kill counters and events are not items")
    assert_eq(learned.items[1].itemID, FIRE)
    assert_eq(learned.items[1].count, 5)
    assert_eq(learned.items[2].name, "Mystery Widget")
    assert_nil(learned.items[2].itemID)
    assert_eq(QF.pending[STORM], 1)
    assert_nil(QP.Waypoint(STORM), "in progress: nowhere to go yet")
    Mock.AddItem(777001, { name = "Mystery Widget" })
    Mock.FireEvent("BAG_UPDATE_DELAYED")
    Mock.RunTimers()
    assert_nil(ns.db.questFacts[STORM].items[2].itemID, "never shown to the client yet")
    assert_eq(QF.pending[STORM], 2)
    Mock.SetBag(0, 16, { { 777001, 1 } })
    Mock.FireEvent("BAG_UPDATE_DELAYED")
    Mock.RunTimers()
    assert_eq(ns.db.questFacts[STORM].items[2].itemID, 777001, "the first drop names it")
    assert_nil(QF.pending[STORM])
    -- Facts merge shipped and learned rows; learned positions win.
    ns.Data.QuestCatalogue[STORM] = { giver = { name = "Someone Else", mapID = 1441, x = 0.1, y = 0.1, zone = "Thousand Needles" },
      turnin = { name = "Prate Cloudseer", mapID = 1441, x = 0.45, y = 0.5, zone = "Thousand Needles" },
      items = { { itemID = FIRE, name = "Twisted Fire Totem", count = 5 } } }
    local facts = QP.Facts(STORM)
    assert_eq(facts.giver.name, "Prate Cloudseer")
    assert_eq(facts.turnin.name, "Prate Cloudseer", "shipped turn-in until one is learned")
    assert_eq(#facts.items, 2, "learned items are complete, so they win")
    assert_true(facts.learned)
    assert_true(facts.shipped)
    assert_match(QF.Status(), "1 quests shipped, 1 learned")
    assert_match(QP.Status(), "givers and items recorded for 2 quests")
    -- The reward window records the turn-in; completing clears the retry.
    Mock.SetQuestObjective(STORM, 1, 5, true)
    Mock.SetQuestObjective(STORM, 2, 3, true)
    Mock.SetQuestObjective(STORM, 3, 4, true)
    Mock.SetQuestObjective(STORM, 4, 0, true)
    Mock.position = { mapID = 1441, x = 0.46, y = 0.51 }
    Mock.ShowQuestReward(STORM, "Prate Cloudseer")
    assert_eq(ns.db.questFacts[STORM].turnin.name, "Prate Cloudseer")
    assert_eq(ns.db.questFacts[STORM].turnin.x, 0.46)
    assert_eq(QP.Turnin(STORM).x, 0.46)
    assert_eq(QP.Waypoint(STORM).label, "Prate Cloudseer - Thousand Needles", "ready: the turn-in")
    Mock.CompleteQuest(STORM)
    Mock.CloseQuestWindow()
    Mock.RunTimers()
    assert_nil(QP.Waypoint(STORM), "completed")
    -- Once out of the log, the recorded items still describe the quest.
    local needed = QP.RequiredItems(STORM)
    assert_eq(#needed, 2)
    assert_eq(needed[1].itemID, FIRE)
    assert_eq(needed[1].have, 0)
    -- A quest offered by an NPC the facts already know keeps the newer position.
    Mock.position = { mapID = 1441, x = 0.3, y = 0.3 }
    Mock.OfferQuest(STORM, "Prate Cloudseer")
    assert_eq(ns.db.questFacts[STORM].giver.x, 0.3)
    -- Nothing is written without a quest id.
    Mock.questNPC = { questID = 0, name = "Nobody" }
    Mock.FireEvent("QUEST_DETAIL", 0)
    assert_nil(ns.db.questFacts[0])
  end)

  it("ships the shaman Call of Air chain for both factions in the quest catalogue", function()
    local shipped = H.fresh()
    H.login(shipped)
    local rows = shipped.Data.QuestCatalogue
    local QF = shipped.QuestFactsProvider
    assert_eq(QF.ShippedCount(), 12)
    for questID, row in pairs(rows) do
      assert_true(type(questID) == "number" and questID > 0, "quest id")
      for _, key in ipairs({ "giver", "turnin" }) do
        local place = row[key]
        assert_true(type(place) == "table" and type(place.name) == "string" and place.name ~= "", questID .. " " .. key)
        assert_true(type(place.mapID) == "number" and place.mapID > 0, questID .. " " .. key .. " map")
        assert_true(place.x > 0 and place.x < 1 and place.y > 0 and place.y < 1, questID .. " " .. key .. " position as a fraction")
        assert_true(type(place.zone) == "string", questID .. " " .. key .. " zone")
      end
      for _, item in ipairs(row.items) do
        assert_true(type(item.itemID) == "number" and item.itemID > 0, questID .. " item id")
        assert_true(type(item.name) == "string" and item.count > 0, questID .. " item name and count")
        assert_true(type(item.source) == "string" and item.source ~= "", questID .. " item source")
      end
    end
    local QP2 = shipped.QuestProvider
    -- No Attune needed: the catalogue alone names the givers and the items.
    assert_eq(QP2.Giver(TEMPEST).label, "Rau Cliffrunner - Thousand Needles")
    assert_eq(QP2.Giver(TEMPEST).mapID, 1441)
    assert_eq(QP2.Turnin(TEMPEST).label, "Bath'rah the Windwatcher - Alterac Mountains")
    assert_eq(QP2.Waypoint(TEMPEST).name, "Rau Cliffrunner")
    assert_eq(QP2.Giver(94789).name, "Eldrun Stormbreaker")
    assert_eq(QP2.Turnin(94789).name, "Veyric Thunderhame")
    local needed = QP2.RequiredItems(STORM)
    assert_eq(#needed, 4)
    assert_eq(needed[1].itemID, FIRE)
    assert_eq(needed[1].count, 5)
    assert_match(needed[1].source, "Badlands")
    assert_eq(QP2.RequiredItems(79358)[4].itemID, WATER)
    assert_eq(QP2.RequiredItems(AID)[1].itemID, 274463)
    assert_eq(QP2.RequiredItems(HEED)[1].itemID, 212792)
    -- The item sources reach the resolver through SourceProvider.
    local hints = shipped.SourceProvider.Sources(FIRE)
    assert_eq(hints[1].kind, "drop")
    assert_eq(hints[1].label, "Drop: Stonevault troggs and Dustbelcher ogres, Agmond's End, Badlands")
    assert_match(hints[1].detail, "for Quest 79358 %(quest catalogue%)", "no Attune here: the lowest quest id names it")
    assert_true(hints[1].questItem)
    assert_eq(#shipped.SourceProvider.Sources(FIRE), 1, "the same source for both factions' quests is listed once")
    assert_eq(#QF.ItemHints(999999), 0)
    assert_match(QF.Status(), "^Quest facts: 12 quests shipped, 0 learned")
    -- A quest goal with the shipped facts and no chain: the items and the giver.
    Mock.AddItem(274463, { name = "Tattered Note" })
    Mock.quests.titles[AID] = "Elemental Aid"
    local goal = shipped.GoalService.AddQuestGoal(AID)
    local view = shipped.Planner.Evaluate(goal)
    assert_eq(view.nextStep, "Pick up Elemental Aid from Prate Cloudseer in Thousand Needles")
    assert_eq(view.waypoint.mapID, 1441)
    assert_eq(#view.plan.materials, 1)
    assert_eq(view.plan.materials[1].itemID, 274463)
    assert_eq(view.tree.root.children[1].route, "drop")
    assert_eq(view.tree.root.children[1].hint.label, "Drop: Charlga Razorflank, Razorfen Kraul")
    local list = shipped.ShoppingList.Build({ { goal = goal, view = view } }, { nameOf = shipped.ItemProvider.GetName })
    assert_eq(list.rows[1].itemID, 274463)
    assert_eq(list.rows[1].category, "gather")
    assert_eq(list.rows[1].sources[1], "Drop: Charlga Razorflank", "the short form on tags; the full text in tooltips")
    assert_eq(hints[1].short, "Drop: Stonevault troggs and Dustbelcher ogres")
  end)

  it("cuts source tags to their column instead of running past the table", function()
    local Widgets = ns.UI.Widgets
    local cell = CreateFrame("Frame")
    cell:SetSize(180, 40)
    local long = "Drop: the quilboar ritual at the steam pools west of Freewind Post, Thousand Needles"
    assert_eq(Widgets.LayoutTags(cell, { long }), 1)
    local tag = cell.tags[1]
    assert_eq(tag:GetWidth(), 180, "no wider than the cell")
    assert_eq(tag.label:GetWidth(), 168, "the label is cut with an ellipsis")
    assert_true(tag.truncated)
    assert_eq(tag.fullText, long)
    -- Short tags keep their natural width; a tag with no room left is hidden.
    assert_eq(Widgets.LayoutTags(cell, { "In bags", "Vendor: Tharynn Bouden", long }), 2)
    assert_eq(cell.tags[1]:GetWidth(), 7 * 6 + 12)
    assert_false(cell.tags[1].truncated)
    assert_true(cell.tags[2].truncated, "the second tag takes what is left")
    assert_false(cell.tags[3]:IsShown())
    assert_eq(Widgets.LayoutTags(cell, { "Bank" }), 1)
    assert_false(cell.tags[2]:IsShown())
    -- The crafting rows and the shopping rows use the same layout.
    shaman()
    local MainFrame = ns.UI.MainFrame
    MainFrame.Show()
    Mock.RunTimers()
    ns.Data.QuestCatalogue[STORM] = { giver = { name = "Prate Cloudseer", mapID = 1441, x = 0.45, y = 0.5, zone = "Thousand Needles" },
      turnin = { name = "Prate Cloudseer", mapID = 1441, x = 0.45, y = 0.5, zone = "Thousand Needles" },
      items = { { itemID = FIRE, name = "Twisted Fire Totem", count = 5, source = "Stonevault troggs and Dustbelcher ogres, Agmond's End, Badlands" } } }
    local goal = ns.GoalService.AddItemGoal(RAGE, 1)
    MainFrame.OpenGoal(goal.id)
    Mock.RunTimers()
    local row = MainFrame.screens.crafting.pool.rows[1]
    assert_eq(row.itemID, FIRE)
    assert_eq(row.sourceFrame.tags[1].label:GetText(), "Drop: Stonevault troggs and Dustbelcher ogres")
    assert_true(row.sourceFrame.tags[1]:GetWidth() <= 180)
    assert_eq(MainFrame.screens.crafting.pool.rows[2].note:GetText(), "Two-Handed Maces", "the item class note keeps its hyphen")
    MainFrame.ShowScreen("shopping")
    Mock.RunTimers()
    local shopRow = MainFrame.screens.shopping.pool.rows[1]
    assert_eq(shopRow.itemID, FIRE)
    assert_eq(shopRow.sourceFrame.tags[1].label:GetText(), "Drop: Stonevault troggs and Dustbelcher ogres")
    assert_true(shopRow.sourceFrame.tags[1]:GetWidth() <= 180)
  end)

  it("shows the chain, the items and the waypoint button on the screens", function()
    shaman()
    local MainFrame = ns.UI.MainFrame
    local function screen(key) return MainFrame.screens[key] end
    MainFrame.Show()
    Mock.RunTimers()
    ns.Data.QuestCatalogue[CALL_A] = { giver = { name = "Prate Cloudseer", mapID = 1441, x = 0.45, y = 0.5, zone = "Thousand Needles" } }
    Mock.AcceptQuest(STORM, { title = "Storm, Earth, and Fire", level = 30, zone = "Thousand Needles", objectives = {
      { text = "Twisted Fire Totem: 0/5", type = "item", numFulfilled = 0, numRequired = 5 } } })
    local goal = ns.GoalService.AddItemGoal(RAGE, 1)
    MainFrame.OpenGoal(goal.id)
    Mock.RunTimers()
    assert_eq(MainFrame.currentScreen, "crafting")
    local crafting = screen("crafting")
    local hero = crafting.hero
    assert_eq(hero.chips[1].label:GetText(), "Obtain")
    assert_eq(hero.chips[2].label:GetText(), "Quest reward: The Tempest's Weapons")
    assert_eq(hero.chips[3].label:GetText(), "Call of Air - 1 of 8 steps")
    assert_true(hero.waypoint:IsShown(), "the next step has a recorded position")
    hero.waypoint:Click()
    assert_eq(Mock.waypoint.uiMapID, 1441)
    assert_eq(MainFrame.frame.alertText:GetText(), "Waypoint set: Prate Cloudseer - Thousand Needles.")
    assert_match(hero.reagents:GetText(), "^0 of 1 in your bags %- Quest reward: The Tempest's Weapons")
    -- The requirement rows list the item and the totems; the tree hangs them below the reward.
    local rows = crafting.pool.rows
    assert_eq(rows[1].itemID, FIRE, "sorted by missing: 5 totems before the 1 reward")
    assert_eq(rows[2].itemID, RAGE)
    assert_nil(rows[3])
    crafting.tabs.tabs.tree:Click()
    local treeRows = crafting.treeView.pool.rows
    assert_match(treeRows[1].name:GetText(), "Rage of the Storm")
    assert_match(treeRows[2].name:GetText(), "Twisted Fire Totem")
    assert_eq(treeRows[1].via:GetText(), "Quest")
    crafting.tabs.tabs.requirements:Click()
    -- My Goals row and the dashboard carry the next step.
    MainFrame.ShowScreen("goals")
    Mock.RunTimers()
    local goalRow = screen("goals").rowPool.rows[1]
    assert_match(goalRow.sub:GetText(), "^Quest reward %- Pick up Call of Air from Prate Cloudseer")
    MainFrame.ShowScreen("dashboard")
    Mock.RunTimers()
    local dash = screen("dashboard")
    assert_match(dash.goalsPanel.pool.rows[1].detail:GetText(), "Twisted Fire Totem", "a missing quest item shows as a material")
    -- A quest goal opens on the Quests screen, whose side panel lists the chain; the waypoint button follows the position.
    local questGoal = ns.GoalService.AddQuestGoal(TEMPEST)
    MainFrame.OpenGoal(questGoal.id)
    Mock.RunTimers()
    assert_eq(MainFrame.currentScreen, "quests")
    local quests = screen("quests")
    quests:Select(TEMPEST)
    Mock.RunTimers()
    local side = quests.side
    assert_eq(side.title:GetText(), "The Tempest's Weapons")
    assert_match(side.objectives[1].text:GetText(), "1%. Level: Reach level 30 %(done%)")
    assert_match(side.objectives[2].text:GetText(), "2%. Quest: Call of Air %- Thousand Needles")
    assert_match(side.objectives[8].text:GetText(), "8%. Quest: The Tempest's Weapons")
    assert_false(side.waypoint:IsShown(), "no position for the last quest's giver")
    quests:Select(CALL_A)
    Mock.RunTimers()
    assert_true(side.waypoint:IsShown())
    assert_match(side.meta:GetText(), "Prate Cloudseer %- Thousand Needles")
    side.waypoint:Click()
    assert_eq(MainFrame.frame.alertText:GetText(), "Waypoint set: Prate Cloudseer - Thousand Needles.")
    quests:Select(STORM)
    Mock.RunTimers()
    assert_match(side.objectives[1].text:GetText(), "Twisted Fire Totem: 0/5")
    assert_match(side.objectives[2].text:GetText(), "Bring 5 x Twisted Fire Totem")
    assert_false(side.waypoint:IsShown())
    quests:Select(nil)
    assert_false(side.waypoint:IsShown())
  end)
end)
