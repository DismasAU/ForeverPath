local H = require("harness")
local Mock = H.Mock

describe("SourceProvider", function()
  local ns, SP
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    SP = ns.SourceProvider
    Mock.AddItem(2589, { name = "Linen Cloth", classID = 7, subclassID = 5 })
    Mock.AddItem(2770, { name = "Copper Ore", classID = 7, subclassID = 7 })
    Mock.AddItem(2447, { name = "Peacebloom", classID = 7, subclassID = 9 })
    Mock.AddItem(2934, { name = "Ruined Leather Scraps", classID = 7, subclassID = 6 })
    Mock.AddItem(2840, { name = "Copper Bar", classID = 7, subclassID = 7 })
    Mock.AddItem(14149, { name = "Subterranean Cape", classID = 4, subclassID = 1 })
    Mock.AddItem(2320, { name = "Coarse Thread" })
  end)

  it("maps item classes to gathering and drop hints", function()
    assert_eq(SP.ClassHint(2589).kind, "drop")
    assert_eq(SP.ClassHint(2589).label, "Humanoid drops")
    assert_eq(SP.ClassHint(2770).label, "Mining")
    assert_eq(SP.ClassHint(2770).skill, "Mining")
    assert_eq(SP.ClassHint(2447).label, "Herbalism")
    assert_eq(SP.ClassHint(2934).label, "Skinning")
    assert_nil(SP.ClassHint(14149), "armour has no gathering hint")
    assert_nil(SP.ClassHint(2320), "generic trade goods have none")
    assert_true(SP.ClassHint(2770).heuristic)
  end)

  it("drops the class hint once a recipe produces the item, unless that recipe only refines a lower tier", function()
    assert_eq(#SP.Sources(2840), 0, "the catalogue knows Copper Bar is smelted, by Mining itself")
    assert_false(SP.IsRawMaterial(2840))
    assert_eq(SP.Sources(2770)[1].label, "Mining", "the ore keeps its hint")
    assert_true(SP.IsRawMaterial(2770))
    -- Leather tiers: Medium Leather is skinned; "Medium Leather" from Light Leather only refines it.
    Mock.AddItem(2318, { name = "Light Leather", classID = 7, subclassID = 6 })
    Mock.AddItem(2319, { name = "Medium Leather", classID = 7, subclassID = 6 })
    assert_true(SP.IsRawMaterial(2934), "scraps: no recipe at all")
    assert_true(SP.IsRawMaterial(2318))
    assert_true(SP.IsRawMaterial(2319))
    assert_eq(SP.Sources(2319)[1].kind, "gather")
    assert_eq(SP.Sources(2319)[1].skill, "Skinning")
    -- Classes come from the catalogue when the client has not cached the item.
    assert_true(SP.IsRawMaterial(4234), "Heavy Leather, never seen by this client")
    local classID, subclassID = SP.ItemClass(4234)
    assert_eq(classID, 7)
    assert_eq(subclassID, 6)
    -- A bolt is not gathered (cloth drops), a cured hide needs salt too: both stay crafts.
    Mock.AddItem(2996, { name = "Bolt of Linen Cloth", classID = 7, subclassID = 5 })
    assert_false(SP.IsRawMaterial(2996))
    assert_false(SP.IsRawMaterial(4231), "Cured Light Hide")
    assert_eq(#SP.Sources(4231), 0)
    -- Essences combine up and down the tiers; both stay disenchanting material by default.
    assert_true(SP.IsRawMaterial(11082), "Greater Astral Essence")
    assert_true(SP.IsRawMaterial(10998), "Lesser Astral Essence")
  end)

  it("plans gathering materials as their own items, with refining as an opt-in route", function()
    Mock.AddItem(2318, { name = "Light Leather", classID = 7, subclassID = 6 })
    Mock.AddItem(2319, { name = "Medium Leather", classID = 7, subclassID = 6 })
    Mock.AddItem(2320, { name = "Coarse Thread", classID = 7, subclassID = 11 })
    Mock.AddItem(4248, { name = "Dark Leather Cloak", classID = 4, subclassID = 2 })
    Mock.AddRecipe({ recipeID = 2881, name = "Light Leather", outputItemID = 2318, reagents = { { itemID = 2934, quantity = 3 } } })
    Mock.AddRecipe({ recipeID = 20648, name = "Medium Leather", outputItemID = 2319, reagents = { { itemID = 2318, quantity = 4 } } })
    Mock.AddRecipe({ recipeID = 2169, name = "Dark Leather Cloak", outputItemID = 4248, reagents = { { itemID = 2319, quantity = 8 }, { itemID = 2320, quantity = 1 } } })
    Mock.OpenProfession({ professionID = 165, name = "Leatherworking", skillLevel = 100, maxSkillLevel = 150, recipeIDs = { 2881, 20648, 2169 } })
    Mock.FireEvent("TRADE_SKILL_LIST_UPDATE")
    Mock.RunTimers()
    local goal = ns.GoalService.AddCraftGoal(4248, 1)
    local view = ns.Planner.Evaluate(goal)
    local medium
    for _, child in ipairs(view.tree.root.children) do if child.itemID == 2319 then medium = child end end
    assert_true(medium.raw)
    assert_eq(medium.route, "buy", "nobody skins here, so the AH; the refine recipe is not expanded")
    assert_eq(#medium.children, 0)
    assert_true(medium.craftOption.learned, "the craft is still offered")
    assert_eq(view.tree.summary.missingLeaves[1].itemID, 2319)
    local overview = ns.Overview.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_eq(overview.nextSteps[1].title, "Obtain 8 x Medium Leather")
    -- A skinner on the account makes it a gathering route.
    Mock.professionSlots = { 1 }
    Mock.professionInfo = { [1] = { name = "Skinning", skillLevel = 150, maxSkillLevel = 150, skillLine = 393 } }
    view = ns.Planner.Evaluate(goal)
    for _, child in ipairs(view.tree.root.children) do if child.itemID == 2319 then medium = child end end
    assert_eq(medium.route, "gather")
    assert_match(medium.hint.detail, "you have Skinning")
    -- Asking for the craft expands it one tier, and that tier is raw again.
    ns.GoalService.SetRoute(goal.id, 2319, "craft")
    view = ns.Planner.Evaluate(goal)
    for _, child in ipairs(view.tree.root.children) do if child.itemID == 2319 then medium = child end end
    assert_eq(medium.route, "craft")
    assert_eq(medium.routeSource, "override")
    assert_eq(#medium.children, 1)
    assert_eq(medium.children[1].itemID, 2318)
    assert_true(medium.children[1].raw)
    assert_eq(#medium.children[1].children, 0, "Light Leather is gathered too unless asked")
    assert_eq(medium.children[1].quantity, 32)
  end)

  it("puts recorded vendors ahead of loot tables and heuristics", function()
    Mock.InstallAtlasLoot({
      AtlasLootClassic_DungeonsAndRaids = {
        Ragefire = { items = { { name = "Taragaman the Hungerer", npcID = 11520, [1] = { { 1, 14149 }, { 2, 2589 } } } } },
        Deadmines = { items = { { name = "Edwin VanCleef", npcID = 639, [1] = { { 1, 2589 } } }, { name = "Mr. Smite", npcID = 646, [1] = { { 1, 2589 } }, [2] = { { 1, 2589 } } } } },
      },
    })
    Mock.OpenMerchant("Tharynn Bouden", { { 2589, 100, 1 } })
    Mock.CloseMerchant()
    local sources = SP.Sources(2589)
    assert_eq(sources[1].kind, "vendor")
    assert_eq(sources[1].name, "Tharynn Bouden")
    assert_eq(sources[2].kind, "drop")
    assert_true(sources[2].atlasloot)
    assert_match(sources[2].label, "Dropped by Taragaman")
    assert_match(sources[2].detail, "Ragefire")
    assert_eq(#sources, 5, "vendor + 3 loot entries (capped, duplicates merged) + class hint")
    assert_eq(sources[5].label, "Humanoid drops")
    assert_eq(SP.atlas.state, "ready")
    assert_eq(Mock.atlasLoads[1], "AtlasLootClassic_DungeonsAndRaids")
    local cape = SP.Sources(14149)
    assert_eq(#cape, 1)
    assert_eq(cape[1].boss, "Taragaman the Hungerer")
    assert_eq(cape[1].npcID, 11520)
    local lines = SP.Describe(14149)
    assert_match(lines[1], "^Drop: Dropped by Taragaman the Hungerer %- Ragefire %(AtlasLoot%)")
  end)

  it("works without AtlasLoot and feeds the planner's default route", function()
    assert_false(SP.HasAtlasLoot())
    assert_eq(#SP.AtlasSources(14149), 0)
    assert_eq(SP.atlas.state, "idle")
    Mock.AddRecipe({ recipeID = 2963, name = "Bolt of Linen Cloth", outputItemID = 2996, reagents = { { itemID = 2589, quantity = 2 } } })
    Mock.AddItem(2996, { name = "Bolt of Linen Cloth" })
    Mock.OpenProfession({ professionID = 197, name = "Tailoring", skillLevel = 50, maxSkillLevel = 150, recipeIDs = { 2963 } })
    Mock.FireEvent("TRADE_SKILL_LIST_UPDATE")
    Mock.RunTimers()
    ns.GoalService.AddCraftGoal(2996, 1)
    local view = ns.Planner.Evaluate(ns.GoalService.GetSelected())
    local cloth = view.tree.root.children[1]
    assert_eq(cloth.route, "drop", "cloth drops from humanoids")
    assert_eq(cloth.hint.label, "Humanoid drops")
    Mock.OpenMerchant("Cloth Vendor", { { 2589, 5, 1 } })
    Mock.CloseMerchant()
    view = ns.Planner.Evaluate(ns.GoalService.GetSelected())
    assert_eq(view.tree.root.children[1].route, "vendor")
    assert_eq(view.tree.summary.missingLeaves[1].altName, "Cloth Vendor")
  end)

  it("reads ForeverDungeonJournal boss loot, shared loot and quest rewards", function()
    Mock.AddItem(10411, { name = "Footpads of the Fang", classID = 4, subclassID = 2 })
    Mock.AddItem(10413, { name = "Gloves of the Fang", classID = 4, subclassID = 2 })
    Mock.AddItem(252512, { name = "Brawler's Leather Helm", classID = 4, subclassID = 2 })
    Mock.AddItem(279899, { name = "Catacomb Cloak", classID = 4, subclassID = 1 })
    Mock.InstallDungeonJournal({
      ["Wailing Caverns"] = {
        bosses = {
          { name = "Kresh", npcID = 3653, loot = { { 10411, "Footpads of the Fang", "Feet, Leather", 3 } } },
          { name = "Trash Drops", trash = true, loot = { { 10413, "Gloves of the Fang", "Hands, Leather", 3, "Druid of the Fang" } } },
        },
        quests = { { id = 96395, name = "An Ancient Grudge", faction = "Both", rewardChoice = true, rewardItems = { { 279899, "Catacomb Cloak", 3 } } } },
      },
    }, { ["Wailing Caverns"] = { Kresh = { { 252512, "Brawler's Leather Helm", "Head, Leather", 3 } } } })
    assert_true(SP.HasDungeonJournal())
    local s = SP.Sources(10411)
    assert_eq(#s, 1)
    assert_eq(s[1].kind, "drop")
    assert_true(s[1].journal)
    assert_eq(s[1].label, "Dropped by Kresh")
    assert_eq(s[1].detail, "Wailing Caverns (DungeonJournal)")
    assert_eq(s[1].npcID, 3653)
    assert_eq(SP.journal.state, "ready")
    local trash = SP.Sources(10413)[1]
    assert_eq(trash.label, "Dropped by Druid of the Fang")
    assert_true(trash.trash)
    local shared = SP.Sources(252512)[1]
    assert_eq(shared.label, "Dropped by Kresh")
    assert_match(shared.detail, "shared loot")
    local quest = SP.Sources(279899)[1]
    assert_eq(quest.kind, "quest")
    assert_eq(quest.label, "Quest reward: An Ancient Grudge")
    assert_match(quest.detail, "choose on turn%-in")
    assert_eq(quest.questID, 96395)
    assert_match(SP.Describe(279899)[1], "^Quest: Quest reward: An Ancient Grudge")
    -- AtlasLoot entries for a boss the journal already lists are folded in.
    Mock.InstallAtlasLoot({ AtlasLootClassic_DungeonsAndRaids = { WailingCaverns = { items = {
      { name = "Kresh", npcID = 3653, [1] = { { 1, 10411 } } },
      { name = "Lord Cobrahn", npcID = 3669, [1] = { { 2, 10411 } } },
    } } } })
    s = SP.Sources(10411)
    assert_eq(#s, 2)
    assert_eq(s[2].label, "Dropped by Lord Cobrahn")
    assert_true(s[2].atlasloot)
    local status = SP.Status()
    assert_eq(status.journal, "installed, 4 items indexed")
    assert_match(status.atlasloot, "index ready")
    Mock.RunSlash("vendors")
    assert_output("DungeonJournal: installed, 4 items indexed")
  end)

  it("works without the journal and ranks quests between drops and the AH", function()
    assert_false(SP.HasDungeonJournal())
    assert_eq(#SP.JournalSources(10411), 0)
    assert_eq(SP.journal.state, "idle")
    assert_eq(SP.Status().journal, "not installed")
    local rank = ns.DependencyResolver.RouteRank
    assert_true(rank.quest > rank.drop)
    assert_true(rank.quest < rank.buy)
    assert_eq(ns.DependencyResolver.RouteLabels.quest, "Quest")
  end)


  it("only routes gathering to characters that have the skill", function()
    local hint = SP.Sources(2934)[1]
    assert_eq(hint.label, "Skinning")
    assert_true(hint.unavailable, "nobody has Skinning yet")
    assert_match(hint.detail, "no character has Skinning$")
    assert_eq(#SP.GatherersFor("Skinning"), 0)
    ns.GoalService.AddObtainGoal(2934, 5)
    local view = ns.Planner.Evaluate(ns.GoalService.GetSelected())
    assert_eq(view.tree.root.route, "buy", "an unavailable gathering hint is never the route")
    assert_true(view.tree.root.options[1].unavailable)
    -- An alt with Skinning: the hint names the alt and becomes the route.
    ns.db.characters["Miravelle-Stormhold"] = {
      key = "Miravelle-Stormhold", name = "Miravelle", realm = "Stormhold", level = 52, class = "Shaman", lastSeen = Mock.now - 7200,
      bags = { items = {}, scannedAt = Mock.now - 7200 }, professions = { { name = "Skinning", skillLevel = 90, maxSkillLevel = 150, slot = 2 } }, knownRecipes = {},
    }
    hint = SP.Sources(2934)[1]
    assert_nil(hint.unavailable)
    assert_eq(hint.gatherer, "Miravelle")
    assert_match(hint.detail, "Miravelle has Skinning %(90%)$")
    view = ns.Planner.Evaluate(ns.GoalService.GetSelected())
    assert_eq(view.tree.root.route, "gather")
    assert_eq(view.tree.summary.missingLeaves[1].gatherer, "Miravelle")
    local overview = ns.Overview.Build({ { goal = ns.GoalService.GetSelected(), view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_eq(overview.nextSteps[1].badge, "Gather - Miravelle")
    assert_match(overview.nextSteps[1].detail, "^Skin beasts %- Miravelle has Skinning")
    -- This character has it too: "you" wins, no alt name.
    Mock.SetProfessions({ { slot = 1, name = "Skinning", skillLevel = 75, maxSkillLevel = 150, skillLine = 393 } })
    hint = SP.Sources(2934)[1]
    assert_nil(hint.gatherer)
    assert_match(hint.detail, "you have Skinning %(75%)$")
    assert_eq(SP.GatherersFor("Skinning")[1].isCurrent, true)
    assert_eq(#SP.GatherersFor("Skinning"), 2)
    view = ns.Planner.Evaluate(ns.GoalService.GetSelected())
    assert_eq(view.tree.root.route, "gather")
    assert_eq(ns.Overview.Build({ { goal = ns.GoalService.GetSelected(), view = view } }, { nameOf = ns.ItemProvider.GetName }).nextSteps[1].badge, "Gather")
  end)

end)
