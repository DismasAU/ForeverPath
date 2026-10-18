local H = require("harness")
local Mock = H.Mock

local HELM, BETTER_HELM, CHEST, RING, SWORD, VENDOR_HELM = 1001, 1002, 1003, 1004, 1005, 1007

local function wardrobe()
  Mock.AddItem(HELM, { name = "Plain Helm", quality = 1, equipLoc = "INVTYPE_HEAD", ilvl = 20, stats = { ITEM_MOD_STAMINA_SHORT = 5, ITEM_MOD_ARMOR = 50 } })
  Mock.AddItem(BETTER_HELM, { name = "Better Helm", quality = 2, equipLoc = "INVTYPE_HEAD", ilvl = 30, stats = { ITEM_MOD_STAMINA_SHORT = 8, ITEM_MOD_ARMOR = 70, ITEM_MOD_STRENGTH_SHORT = 3 } })
  Mock.AddItem(CHEST, { name = "Plain Chest", quality = 1, equipLoc = "INVTYPE_CHEST", ilvl = 25, stats = { ITEM_MOD_ARMOR = 90 } })
  Mock.AddItem(RING, { name = "Plain Ring", quality = 2, equipLoc = "INVTYPE_FINGER", ilvl = 15 })
  Mock.AddItem(SWORD, { name = "Big Sword", quality = 2, equipLoc = "INVTYPE_2HWEAPON", ilvl = 28, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 12.5 } })
  Mock.AddItem(VENDOR_HELM, { name = "Vendor Helm", quality = 1, equipLoc = "INVTYPE_HEAD", ilvl = 22 })
  Mock.Equip(1, HELM)
  Mock.Equip(5, CHEST)
  Mock.Equip(11, RING)
  Mock.Equip(16, SWORD)
end

local function installGearQuest()
  return Mock.InstallGearQuest({
    spec = "arms", specLabel = "Arms",
    entries = {
      { itemId = BETTER_HELM, slot = "Head", minLevel = 15, maxLevel = 25, curatedRank = 1, pipelineScore = 3.2, classes = { WARRIOR = true }, specs = { arms = true }, factions = { Alliance = true },
        sourceType = "quest_reward", instructions = "Reward from the quest 'Sweet Amber'. Starts with Grimbooze Thunderbrew in Westfall.", zone = "Westfall", questName = "Sweet Amber" },
      { itemId = BETTER_HELM, slot = "Head", minLevel = 15, maxLevel = 25, curatedRank = 2, pipelineScore = 1.0, classes = { WARRIOR = true }, specs = { fury = true } },
      { itemId = VENDOR_HELM, slot = "Head", minLevel = 15, maxLevel = 25, curatedRank = 2, pipelineScore = 2.0, classes = { WARRIOR = true }, sourceType = "vendor", instructions = "Bought from Bob.", zone = "Stormwind City", npc = "Bob" },
      { itemId = 1008, slot = "Head", minLevel = 15, maxLevel = 25, curatedRank = 1, classes = { WARRIOR = true }, specs = { fury = true }, sourceType = "world_drop" },
      { itemId = 1009, slot = "Head", minLevel = 30, maxLevel = 40, curatedRank = 1, classes = { WARRIOR = true }, sourceType = "world_drop" },
      { itemId = 1010, slot = "Head", minLevel = 10, maxLevel = 20, curatedRank = 1, classes = { MAGE = true }, sourceType = "world_drop" },
      { itemId = 1011, slot = "Head", minLevel = 10, maxLevel = 20, curatedRank = 1, classes = { WARRIOR = true }, factions = { Horde = true }, sourceType = "world_drop" },
      { itemId = CHEST, slot = "Chest", minLevel = 10, maxLevel = 25, curatedRank = 1, classes = { WARRIOR = true }, sourceType = "vendor", npc = "Bob", zone = "Stormwind City" },
    },
    facts = {
      [BETTER_HELM] = { name = "Better Helm", quality = 2, ilvl = 30, reqLevel = 15, sourceType = "quest_reward", instructions = "Reward from the quest 'Sweet Amber'. Starts with Grimbooze Thunderbrew in Westfall.", zone = "Westfall", questName = "Sweet Amber" },
      [VENDOR_HELM] = { name = "Vendor Helm", quality = 1, ilvl = 22, reqLevel = 15, sourceType = "vendor", instructions = "Bought from Bob.", zone = "Stormwind City", npc = "Bob" },
      [CHEST] = { name = "Plain Chest", quality = 1, ilvl = 25, reqLevel = 10, sourceType = "vendor", instructions = "Bought from Bob.", zone = "Stormwind City", npc = "Bob" },
    },
    scoredStats = { [VENDOR_HELM] = { armor = 55, sta = 6 } },
  })
end

describe("EquipmentProvider", function()
  local ns, EP
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    EP = ns.EquipmentProvider
    Mock.character.level = 20
    wardrobe()
  end)

  it("reads what is worn, item levels, stats, slots and the average", function()
    assert_true(EP.IsAvailable())
    assert_false(EP.HasGearQuest())
    local byKey, list = EP.Equipped()
    assert_eq(#list, 17)
    assert_eq(byKey.Head.itemID, HELM)
    assert_eq(byKey.Head.name, "Plain Helm")
    assert_eq(byKey.Head.ilvl, 20)
    assert_nil(byKey.Neck.itemID)
    assert_eq(byKey.MainHand.itemID, SWORD)
    assert_eq(EP.AverageItemLevel(list), 5.5, "88 levels over 16 slots (the empty off hand is not counted)")
    local stats = EP.Stats(HELM)
    assert_eq(stats.ilvl, 20)
    assert_eq(stats.sta, 5)
    assert_eq(stats.armor, 50)
    assert_eq(EP.Stats(SWORD).dps, 12.5)
    assert_deep_eq(EP.SlotKeysFor(RING), { "Finger1", "Finger2" })
    assert_deep_eq(EP.SlotKeysFor(SWORD), { "MainHand" })
    assert_deep_eq(EP.SlotKeysFor(2589), {})
    assert_match(EP.Status(), "^Equipment: 4 of 17 slots filled, average item level 5%.5; upgrade hunts unavailable")
    assert_eq(#EP.Candidates("Head"), 0)
    -- Without GearQuest the analysis still maps goals to slots.
    local goal = ns.GoalService.AddObtainGoal(BETTER_HELM, 1)
    local ringGoal = ns.GoalService.AddObtainGoal(RING, 1)
    local analysis = EP.Analyze({ goals = ns.GoalService.List({ open = true }) })
    assert_false(analysis.hasGearQuest)
    assert_eq(analysis.trackedGoals, 2)
    assert_eq(analysis.upgradesPlanned, 2)
    assert_eq(analysis.slots[1].slot.key, "Head")
    assert_eq(analysis.slots[1].goal.id, goal.id)
    assert_eq(analysis.slots[1].status, "none")
    assert_eq(analysis.slots[11].goal.id, ringGoal.id, "a ring goal lands on the first finger slot")
    assert_nil(analysis.slots[12].goal)
    assert_eq(analysis.slots[2].status, "empty")
  end)

  it("ranks GearQuest hunts for the class, spec, faction and level band, and feeds sources", function()
    local GQ = installGearQuest()
    assert_true(EP.HasGearQuest())
    local spec, label = EP.Spec()
    assert_eq(spec, "arms")
    assert_eq(label, "Arms")
    local picks = EP.Candidates("Head")
    assert_eq(#picks, 2, "wrong spec, level band, class and faction are filtered; the duplicate row folds")
    assert_eq(picks[1].itemID, BETTER_HELM)
    assert_eq(picks[1].rank, 1)
    assert_eq(picks[1].sourceLabel, "Quest")
    assert_eq(picks[1].ilvl, 30)
    assert_eq(picks[1].zone, "Westfall")
    assert_eq(picks[2].itemID, VENDOR_HELM)
    assert_eq(picks[2].sourceLabel, "Vendor")
    assert_eq(picks[2].npc, "Bob")
    assert_gt(GQ.Data.loadCalls, 0, "the class data is asked for")
    assert_eq(#EP.Candidates("Head", { source = "vendor" }), 1)
    assert_eq(EP.Candidates("Head", { source = "vendor" })[1].itemID, VENDOR_HELM)
    assert_eq(#EP.Candidates("Head", { source = "dungeon" }), 0)
    assert_eq(EP.Candidates("Chest")[1].itemID, CHEST)
    assert_eq(#EP.Candidates("Neck"), 0)
    Mock.character.level = 31
    assert_eq(#EP.Candidates("Head"), 1, "the 30-40 pick comes into its band")
    assert_eq(EP.Candidates("Head")[1].itemID, 1009)
    Mock.character.level = 50
    assert_eq(#EP.Candidates("Head"), 0, "out of every band plus the grace")
    Mock.character.level = 20
    -- Facts and stats fallbacks.
    assert_eq(EP.Facts(BETTER_HELM).reqLevel, 15)
    assert_nil(EP.Facts(HELM))
    Mock.AddItem(1012, { name = "Statless", equipLoc = "INVTYPE_HEAD" })
    GQ.Data.scoredStats[1012] = { armor = 40, agi = 2 }
    local stats = EP.Stats(1012)
    assert_eq(stats.armor, 40)
    assert_eq(stats.agi, 2)
    -- Hints reach the source provider and the planner.
    local hints = EP.Hints(BETTER_HELM)
    assert_eq(hints[1].kind, "quest")
    assert_eq(hints[1].label, "Quest reward: Sweet Amber")
    assert_match(hints[1].detail, "Westfall")
    assert_eq(EP.Hints(VENDOR_HELM)[1].label, "Vendor: Bob")
    assert_eq(#EP.Hints(HELM), 0)
    local sources = ns.SourceProvider.Sources(BETTER_HELM)
    assert_eq(sources[1].kind, "quest")
    assert_eq(sources[1].label, "Quest reward: Sweet Amber")
    local goal = ns.GoalService.AddObtainGoal(BETTER_HELM, 1)
    local view = ns.Planner.Evaluate(goal)
    assert_eq(view.tree.root.route, "quest")
    assert_match(view.message, "Quest reward: Sweet Amber")
    -- The analysis.
    local analysis = EP.Analyze({ goals = ns.GoalService.List({ open = true }), views = { [goal.id] = view } })
    assert_true(analysis.hasGearQuest)
    assert_eq(analysis.specLabel, "Arms")
    local head, chest, neck = analysis.slots[1], analysis.slots[5], analysis.slots[2]
    assert_eq(head.status, "upgrade")
    assert_eq(head.best.itemID, BETTER_HELM)
    assert_eq(head.goal.id, goal.id)
    assert_eq(chest.status, "bis", "the worn chest is GearQuest's top pick")
    assert_nil(chest.best)
    assert_eq(neck.status, "empty")
    assert_match(EP.Status(), "upgrade hunts from GearQuest Forever %(Arms%)")
    ns.Commands.Dispatch("equipment")
    assert_output("Head: Plain Helm %(20%) %- goal: Better Helm %- pick: Better Helm %(Quest, ilvl 30%)")
    assert_output("Chest: Plain Chest %(25%) %- best in slot")
    ns.Commands.Dispatch("status")
    assert_output("Equipment: 4 of 17 slots filled")
  end)

  it("renders the Equipment screen with picks, comparison, goals and filters", function()
    installGearQuest()
    local MainFrame = ns.UI.MainFrame
    MainFrame.Show()
    MainFrame.ShowScreen("equipment")
    Mock.RunTimers()
    assert_eq(MainFrame.currentScreen, "equipment")
    local screen = MainFrame.screens.equipment
    assert_eq(screen.strip.cells[1].value:GetText(), "5.5")
    assert_eq(screen.strip.cells[2].value:GetText(), "0")
    assert_eq(screen.strip.cells[3].value:GetText(), "0")
    assert_match(screen.equipped.specText:GetText(), "Hunts for Arms")
    assert_eq(screen.slotRows.Head.badge.label:GetText(), "UPGRADE FOUND")
    assert_eq(screen.slotRows.Chest.badge.label:GetText(), "BEST IN SLOT")
    assert_eq(screen.slotRows.Neck.badge.label:GetText(), "EMPTY")
    assert_eq(screen.slotKey, "Head", "the first slot with an upgrade is selected")
    local side = screen.side
    assert_eq(side.title:GetText(), "HEAD")
    assert_match(side.wornName:GetText(), "Plain Helm")
    assert_match(side.target.name:GetText(), "Better Helm")
    assert_match(side.target.meta:GetText(), "^Quest %- Westfall")
    assert_eq(side.target.state:GetText(), "best pick")
    local ilvlRow = side.statRows[1]
    assert_true(ilvlRow:IsShown())
    assert_eq(ilvlRow.label:GetText(), "Item level")
    assert_eq(ilvlRow.old:GetText(), "20")
    assert_eq(ilvlRow.new:GetText(), "30")
    assert_match(ilvlRow.delta:GetText(), "%+10")
    local strengthRow
    for _, row in ipairs(side.statRows) do
      if row:IsShown() and row.label:GetText() == "Strength" then strengthRow = row end
    end
    assert_not_nil(strengthRow)
    assert_match(strengthRow.old:GetText(), "%-")
    assert_eq(strengthRow.new:GetText(), "3")
    assert_true(side.optionPool.rows[1]:IsShown())
    assert_match(side.optionPool.rows[1].name:GetText(), "Vendor Helm")
    assert_match(side.optionPool.rows[1].meta:GetText(), "^Vendor %- ilvl 22 %- Stormwind City")
    assert_false(side.openGoal:IsShown())
    -- Make the target a goal.
    side.addTarget:Click()
    Mock.RunTimers()
    local goal = ns.GoalService.GetSelected()
    assert_eq(goal.target.itemID, BETTER_HELM)
    assert_eq(goal.type, "OBTAIN_ITEM")
    screen:Refresh()
    assert_match(screen.slotRows.Head.goalLine:GetText(), "Better Helm")
    assert_eq(screen.strip.cells[2].value:GetText(), "1")
    assert_eq(screen.strip.cells[3].value:GetText(), "1")
    assert_true(side.openGoal:IsShown())
    assert_match(side.target.state:GetText(), "^goal")
    assert_eq(side.addTarget.label:GetText(), "Goal added")
    -- Other option -> goal.
    side.optionPool.rows[1].add:Click()
    Mock.RunTimers()
    assert_not_nil(ns.GoalService.Store():FindByItem("OBTAIN_ITEM", VENDOR_HELM))
    -- Filters persist.
    screen.segment.segments.upgrades:Click()
    assert_eq(ns.chardb.ui.equipmentFilter, "upgrades")
    assert_eq(screen.slotRows.Neck:GetAlpha(), 0.35)
    assert_eq(screen.slotRows.Head:GetAlpha(), 1)
    ns.chardb.ui.equipmentSource = "vendor"
    screen:Refresh()
    assert_eq(screen.source.label:GetText(), "Source: Vendors")
    screen:Select("Chest")
    assert_eq(side.title:GetText(), "CHEST")
    assert_match(side.target.name:GetText(), "No pick for this slot", "the worn chest is the only vendor pick")
    ns.chardb.ui.equipmentSource = "any"
    -- Equipping the pick turns the slot into best in slot after the change event
    -- (the slot shows the goal line while the goal is open, the badge afterwards).
    Mock.Equip(1, BETTER_HELM)
    Mock.RunTimers()
    screen:Refresh()
    assert_false(screen.slotRows.Head.badge:IsShown())
    assert_match(screen.slotRows.Head.goalLine:GetText(), "Better Helm")
    ns.GoalService.Remove(goal.id)
    screen:Refresh()
    assert_match(screen.slotRows.Head.goalLine:GetText(), "Vendor Helm", "the other head goal takes the line")
    ns.GoalService.Remove(ns.GoalService.Store():FindByItem("OBTAIN_ITEM", VENDOR_HELM).id)
    screen:Refresh()
    assert_true(screen.slotRows.Head.badge:IsShown())
    assert_eq(screen.slotRows.Head.badge.label:GetText(), "BEST IN SLOT")
    assert_eq(#ns.Log.errors, 0, ns.Log.errors[1] and ns.Log.errors[1].message or "")
    -- Without GearQuest the screen still shows the wardrobe.
    _G.GearQuest = nil
    EP.factsCache = {}
    screen:Refresh()
    assert_match(screen.equipped.specText:GetText(), "not installed")
    assert_false(screen.slotRows.Neck.badge:IsShown())
    assert_eq(#ns.Log.errors, 0)
  end)
end)
