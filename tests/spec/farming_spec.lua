local H = require("harness")
local Mock = H.Mock

local LEATHER, HERB, CLAM = 2318, 2447, 5503
local WOLF, BOB = 600, 500

local function classic()
  return {
    meta = { source = "CMaNGOS classic-db", commit = "abc" },
    zones = { [1429] = "Elwynn Forest", [1436] = "Westfall" }, instances = {}, quests = {},
    npcs = {
      [WOLF] = { "Wolf", nil, 5, 6, 0, { 1429, 300, 300 }, 3 },
      [BOB] = { "Ranger Bob", nil, 20, 20, 2, { 1429, 420, 655 }, 0 },
    },
    objects = { [700] = { "Peacebloom", 3, { 1436, 400, 400 }, 1, 1 } },
    drops = { [LEATHER] = { 12, WOLF, 2500 } },
    gathered = { [HERB] = { 1, 700, 5000 } },
    trainers = {
      [3915] = { 197, 1, 25, BOB },     -- Brown Linen Shirt
      [2392] = { 197, 40, 45, BOB },    -- Red Linen Shirt
      [12044] = { 197, 40, 30, BOB },   -- Simple Linen Pants
      [2394] = { 197, 70, 100, BOB },   -- Blue Linen Shirt
      [2386] = { 197, 120, 200, BOB },  -- Linen Boots, out of the window
    },
  }
end

describe("Farming estimates", function()
  it("turns a chance into kills, nodes, skins or casts", function()
    local ns = H.fresh()
    local F = ns.Farming
    local e = F.Estimate({ kind = "drop", chance = 2500, boss = "Wolf" }, 4)
    assert_eq(e.count, 16)
    assert_eq(e.text, "~16 kills of Wolf")
    assert_eq(F.Estimate({ kind = "drop", chance = 2500, target = "Wolf", perLoot = 2 }, 4).text, "~8 kills of Wolf", "two per loot halves it")
    assert_eq(F.Estimate({ kind = "gather", skill = "Skinning", chance = 8000, target = "Wolf" }, 4).text, "~5 skins of Wolf")
    assert_eq(F.Estimate({ kind = "gather", skill = "Herbalism", chance = 10000, object = "Peacebloom" }, 3).text, "~3 nodes of Peacebloom")
    assert_eq(F.Estimate({ kind = "gather", skill = "Fishing", chance = 1200, target = "Westfall" }, 1).text, "~9 casts in Westfall")
    assert_eq(F.Estimate({ kind = "drop", chance = 10000, boss = "Hogger" }, 1).text, "~1 kill of Hogger")
    assert_eq(F.Estimate({ kind = "drop", object = "Battered Chest", chance = 5000 }, 1).text, "~2 loots of Battered Chest")
    assert_nil(F.Estimate({ kind = "vendor" }, 3))
    assert_nil(F.Estimate({ kind = "drop", chance = 2500 }, 0))
    assert_nil(F.Estimate(nil, 3))
  end)

  it("puts the estimate and the zone on the overview and the shopping list", function()
    local ns = H.fresh()
    local data = classic()
    Mock.addOnLoaders.ForeverPath_ClassicDB = function() ns.ClassicData = data end
    H.login(ns)
    Mock.AddItem(LEATHER, { name = "Light Leather" })
    Mock.AddItem(HERB, { name = "Peacebloom" })
    Mock.SetProfessions({ { slot = 1, name = "Herbalism", skillLevel = 75, maxSkillLevel = 150, skillLine = 182 } })
    local leather = ns.GoalService.AddObtainGoal(LEATHER, 4)
    local herb = ns.GoalService.AddObtainGoal(HERB, 3)
    local lv, hv = ns.Planner.Evaluate(leather), ns.Planner.Evaluate(herb)
    assert_eq(lv.tree.summary.missingLeaves[1].farm.text, "~16 kills of Wolf")
    assert_eq(lv.tree.summary.missingLeaves[1].zone, "Elwynn Forest")
    assert_eq(hv.tree.root.route, "gather")
    assert_eq(hv.tree.summary.missingLeaves[1].farm.text, "~6 nodes of Peacebloom")
    local overview = ns.Overview.Build({ { goal = leather, view = lv } }, { nameOf = ns.ItemProvider.GetName })
    assert_eq(overview.nextSteps[1].title, "Obtain 4 x Light Leather")
    assert_match(overview.nextSteps[1].detail, "^~16 kills of Wolf %- Elwynn Forest %- 25%%")
    local list = ns.ShoppingList.Build({ { goal = leather, view = lv }, { goal = herb, view = hv } }, { nameOf = ns.ItemProvider.GetName, sort = "zone" })
    assert_eq(list.rows[1].itemID, LEATHER, "Elwynn Forest before Westfall")
    assert_eq(list.rows[1].zone, "Elwynn Forest")
    assert_eq(list.rows[1].farm.text, "~16 kills of Wolf")
    assert_eq(list.rows[2].zone, "Westfall")
    assert_eq(list.rows[2].farm.text, "~6 nodes of Peacebloom")
    -- The shopping screen shows both, and sorts by zone.
    local MainFrame = ns.UI.MainFrame
    MainFrame.Show()
    MainFrame.ShowScreen("shopping")
    Mock.RunTimers()
    local shop = MainFrame.screens.shopping
    ns.chardb.shopping = ns.chardb.shopping or {}
    ns.chardb.shopping.sort = "zone"
    shop:Refresh()
    local row = shop.pool.rows[1]
    assert_eq(row.itemID, LEATHER)
    assert_match(row.note:GetText(), "^Elwynn Forest %- ~16 kills of Wolf %- Light Leather")
  end)

  it("lists what each profession can train now and next", function()
    local ns = H.fresh()
    local data = classic()
    Mock.addOnLoaders.ForeverPath_ClassicDB = function() ns.ClassicData = data end
    H.login(ns)
    Mock.SetProfessions({ { slot = 1, name = "Tailoring", skillLevel = 50, maxSkillLevel = 75, skillLine = 197 } })
    ns.chardb.knownRecipes[3915] = true
    local plans = ns.Planner.Trainable()
    assert_eq(#plans, 1)
    local plan = plans[1]
    assert_eq(plan.profession, "Tailoring")
    assert_eq(plan.skill, 50)
    assert_eq(#plan.now, 2, "Red Linen Shirt and Simple Linen Pants; Brown Linen Shirt is known")
    assert_eq(plan.now[1].recipe.name, "Red Linen Shirt")
    assert_eq(plan.now[1].rank, 40)
    assert_eq(plan.now[1].trainer, "Ranger Bob")
    assert_eq(plan.now[1].zone, "Elwynn Forest")
    assert_true(plan.now[1].classic)
    assert_eq(plan.cost, 75)
    assert_eq(#plan.soon, 1)
    assert_eq(plan.soon[1].recipe.name, "Blue Linen Shirt")
    assert_false(plan.scanned)
    Mock.RunSlash("train")
    assert_output("Tailoring 50/75: 2 recipes to train now %(")
    assert_output("  40  Red Linen Shirt %- .* %- Ranger Bob %(Elwynn Forest%) %[classic data%]")
    assert_output("  Next: Blue Linen Shirt %(70%)")
    assert_output("Open your Tailoring window once")
    Mock.RunSlash("train cooking")
    assert_output("You do not have cooking%.")
    assert_eq(#ns.Planner.Trainable(nil, "tailoring"), 1)
  end)
end)
