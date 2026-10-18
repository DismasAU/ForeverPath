local H = require("harness")
local Mock = H.Mock

-- The generated catalogue (Data/RecipeCatalogue.lua) is loaded through the
-- TOC like any other file, so these tests read the real client data.
local SULFURAS, HAMMER, EYE, PLANS, INGOT, ARCANITE = 17182, 17193, 17204, 18592, 17203, 12360
local LINEN = 2589

local function nameItems()
  Mock.AddItem(SULFURAS, { name = "Sulfuras, Hand of Ragnaros", quality = 5 })
  Mock.AddItem(HAMMER, { name = "Sulfuron Hammer", quality = 4 })
  Mock.AddItem(EYE, { name = "Eye of Sulfuras", quality = 5 })
  Mock.AddItem(PLANS, { name = "Plans: Sulfuron Hammer", quality = 4 })
  Mock.AddItem(INGOT, { name = "Sulfuron Ingot" })
  Mock.AddItem(ARCANITE, { name = "Arcanite Bar" })
end

local function blacksmith(skill)
  Mock.professionSlots = { 1 }
  Mock.professionInfo = { [1] = { name = "Blacksmithing", skillLevel = skill, maxSkillLevel = 300, skillLine = 164 } }
end

describe("Recipe catalogue (Data/Recipes)", function()
  local ns, Recipes
  before_each(function()
    ns = H.fresh()
    Recipes = ns.Data.Recipes
  end)

  it("ships the client's recipes with build information", function()
    assert_true(Recipes.IsAvailable())
    local info = Recipes.Info()
    assert_match(info.build, "^1%.60%.")
    assert_eq(info.product, "wow_classic_beta")
    assert_gt(Recipes.Count(), 2000)
    assert_gt(Recipes.CombineCount(), 100)
    assert_eq(Recipes.ProfessionName(164), "Blacksmithing")
    assert_eq(Recipes.ProfessionID("Blacksmithing"), 164)
    assert_match(Recipes.Status(), "^Recipe catalogue: %d+ recipes")
  end)

  it("decodes a profession recipe with skill ranks, plans and reagents", function()
    local recipe = Recipes.Get(21161)
    assert_eq(recipe.name, "Sulfuron Hammer")
    assert_eq(recipe.outputItemID, HAMMER)
    assert_eq(recipe.quantityMin, 1)
    assert_eq(recipe.professionID, 164)
    assert_eq(recipe.professionName, "Blacksmithing")
    assert_eq(recipe.source, "catalogue")
    assert_true(recipe.static)
    assert_deep_eq(recipe.skill, { min = 300, yellow = 325, green = 337, grey = 350 })
    assert_eq(recipe.teachItemID, PLANS)
    assert_eq(#recipe.reagents, 7)
    local ingots
    for _, reagent in ipairs(recipe.reagents) do
      if reagent.itemID == INGOT then ingots = reagent.quantity end
    end
    assert_eq(ingots, 8)
    assert_eq(Recipes.Get(21161), recipe, "decoded once")
    assert_nil(Recipes.Get(1))
    local linen = Recipes.Get(2963)
    assert_eq(linen.name, "Bolt of Linen Cloth")
    assert_nil(linen.teachItemID, "trainer recipe")
    assert_eq(linen.skill.min, 1)
  end)

  it("decodes item-use combines and looks recipes up by the item they make", function()
    local combine = Recipes.GetCombine(21160)
    assert_eq(combine.name, "Eye of Sulfuras")
    assert_true(combine.combine)
    assert_eq(combine.outputItemID, SULFURAS)
    assert_eq(combine.professionID, 0)
    assert_eq(combine.professionName, "Combine")
    local needs = {}
    for _, reagent in ipairs(combine.reagents) do needs[reagent.itemID] = reagent.quantity end
    assert_eq(needs[HAMMER], 1)
    assert_eq(needs[EYE], 1)
    assert_eq(#combine.tools, 0, "the eye is already a reagent")
    assert_eq(Recipes.Lookup(SULFURAS)[1].recipeID, 21160)
    assert_eq(Recipes.Lookup(HAMMER)[1].recipeID, 21161)
    assert_nil(Recipes.Lookup(LINEN))
    assert_true(Recipes.IsCraftable(HAMMER))
    assert_false(Recipes.IsCraftable(LINEN))
    -- Three lesser essences into a greater one: the used essence is spent.
    local greater = Recipes.Lookup(11082)[1]
    assert_true(greater.combine)
    assert_eq(greater.reagents[1].itemID, 10998)
  end)

  it("names items and knows which ones are soulbound", function()
    assert_eq(Recipes.ItemName(SULFURAS), "Sulfuras, Hand of Ragnaros")
    assert_eq(Recipes.ItemQuality(SULFURAS), 5)
    assert_eq(Recipes.ItemBind(SULFURAS), Recipes.Bind.PICKUP)
    assert_true(Recipes.IsSoulbound(SULFURAS))
    assert_eq(Recipes.ItemBind(HAMMER), Recipes.Bind.EQUIP)
    assert_false(Recipes.IsSoulbound(HAMMER))
    assert_false(Recipes.IsSoulbound(LINEN))
    assert_nil(Recipes.ItemBind(1))
    local lines = Recipes.Lines(SULFURAS)
    assert_match(lines[1], "^Combine %(use Eye of Sulfuras%): Eye of Sulfuras x1")
    assert_match(lines[2], "1 Sulfuron Hammer")
    lines = Recipes.Lines(HAMMER)
    assert_match(lines[1], "^Blacksmithing 300 %(yellow 325, grey 350%): Sulfuron Hammer x1 %- taught by Plans: Sulfuron Hammer")
    assert_match(lines[2], "8 Sulfuron Ingot")
  end)

  it("feeds item names, qualities and search before the client has cached them", function()
    Mock.AddItem(SULFURAS, { name = "Sulfuras, Hand of Ragnaros", loaded = false })
    local item = ns.ItemProvider.GetItem(SULFURAS)
    assert_false(item.loaded)
    assert_eq(item.name, "Sulfuras, Hand of Ragnaros")
    assert_eq(item.quality, 5)
    assert_eq(ns.ItemProvider.GetCachedName(HAMMER), "Sulfuron Hammer")
    local hits = ns.ItemProvider.SearchByName("sulfuras, hand")
    assert_eq(hits[1].itemID, SULFURAS)
  end)
end)

describe("DependencyResolver with catalogue recipes", function()
  local ns, R
  before_each(function()
    ns = H.fresh()
    R = ns.DependencyResolver
  end)

  local BAR, ORE, PLANSX, WIDGET, PART, TOOL = 100, 101, 102, 103, 104, 105
  local barRecipe = { recipeID = 900, name = "Smelt Bar", outputItemID = BAR, quantityMin = 1, quantityMax = 1,
    professionID = 186, professionName = "Mining", static = true, skill = { min = 125, yellow = 150, green = 162, grey = 175 },
    teachItemID = PLANSX, reagents = { { itemID = ORE, quantity = 2 } } }
  local widgetCombine = { recipeID = 901, name = "Assemble Widget", outputItemID = WIDGET, quantityMin = 1, quantityMax = 1,
    professionID = 0, professionName = "Combine", combine = true, static = true, tools = { TOOL },
    reagents = { { itemID = PART, quantity = 3 } } }

  local function opts(extra)
    local o = {
      findRecipes = function(itemID)
        if itemID == BAR then return { { recipe = barRecipe, learned = false, static = true } } end
        if itemID == WIDGET then return { { recipe = widgetCombine, learned = false, static = true } } end
        return {}
      end,
      counts = function() return 0 end,
    }
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
  end

  it("routes through a catalogue recipe when someone on the account can learn it", function()
    local tree = R.Resolve({ itemID = BAR, quantity = 2 }, opts({
      crafters = function(name) if name == "Mining" then return { { name = "Thandrel", skillLevel = 200, isCurrent = true } } end return {} end,
    }))
    local root = tree.root
    assert_eq(root.route, "craft")
    assert_eq(root.routeSource, "learn")
    assert_eq(root.craft.crafter.name, "Thandrel")
    assert_nil(root.craft.unavailable)
    assert_eq(root.craft.teachItemID, PLANSX)
    assert_eq(#root.children, 2)
    assert_eq(root.children[1].itemID, PLANSX)
    assert_true(root.children[1].learn)
    assert_eq(root.children[1].learnFor, "Smelt Bar")
    assert_eq(root.children[1].quantity, 1)
    assert_eq(root.children[2].itemID, ORE)
    assert_eq(root.children[2].quantity, 4)
    local plans
    for _, leaf in ipairs(tree.summary.missingLeaves) do
      if leaf.itemID == PLANSX then plans = leaf end
    end
    assert_true(plans.learn)
    assert_eq(tree.summary.crafts[1].teachItemID, PLANSX)
    assert_match(R.Describe(tree)[2], "learn: Item 102")
  end)

  it("never recommends a craft nobody can do, but shows it when the item is soulbound", function()
    local none = function() return {} end
    local tree = R.Resolve({ itemID = BAR, quantity = 1 }, opts({ crafters = none }))
    assert_eq(tree.root.route, "buy", "a tradeable item with no crafter is bought")
    assert_true(tree.root.craftOption.unavailable)
    assert_eq(tree.root.craftOption.reason, "no Mining on this account")
    assert_eq(#tree.root.children, 0)
    -- Skill too low reads the same way.
    tree = R.Resolve({ itemID = BAR, quantity = 1 }, opts({
      crafters = function() return { { name = "Mira", skillLevel = 80 } } end,
    }))
    assert_eq(tree.root.route, "buy")
    assert_eq(tree.root.craftOption.reason, "needs Mining 125; Mira has 80")
    -- Soulbound: the Auction House is out, so the craft is laid out as the pathway.
    tree = R.Resolve({ itemID = BAR, quantity = 1 }, opts({ crafters = none, soulbound = function(id) return id == BAR end }))
    assert_true(tree.root.soulbound)
    assert_eq(tree.root.route, "craft")
    assert_eq(tree.root.craft.unavailable, "no Mining on this account")
    assert_eq(#tree.root.children, 2)
    assert_match(R.Describe(tree)[1], "%[no Mining on this account%]")
    -- Soulbound with nothing known at all: no route.
    tree = R.Resolve({ itemID = ORE, quantity = 1 }, opts({ soulbound = function() return true end }))
    assert_true(tree.root.noRoute)
    assert_eq(tree.root.route, "buy")
    assert_match(R.Describe(tree)[1], "no known route")
  end)

  it("treats combines as something anyone can do and requires the tool once", function()
    local tree = R.Resolve({ itemID = WIDGET, quantity = 2 }, opts())
    local root = tree.root
    assert_eq(root.route, "craft")
    assert_eq(root.routeSource, "combine")
    assert_true(root.craft.combine)
    assert_eq(#root.children, 2)
    assert_eq(root.children[1].itemID, TOOL)
    assert_true(root.children[1].tool)
    assert_eq(root.children[1].quantity, 1)
    assert_eq(root.children[2].itemID, PART)
    assert_eq(root.children[2].quantity, 6)
    assert_true(tree.summary.crafts[1].combine)
    -- A vendor beats a combine; an alt-craft ties with it and wins on order.
    tree = R.Resolve({ itemID = WIDGET, quantity = 1 }, opts({ sources = function() return { { kind = "vendor", label = "Vendor" } } end }))
    assert_eq(tree.root.route, "vendor")
  end)
end)

describe("Planning with the catalogue", function()
  local ns
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    nameItems()
  end)

  it("types goals from the catalogue and lays out Sulfuras down to its raw materials", function()
    assert_eq(ns.GoalService.TypeForItem(SULFURAS), "CRAFT_ITEM")
    assert_eq(ns.GoalService.TypeForItem(LINEN), "OBTAIN_ITEM")
    blacksmith(300)
    local ok, message, goal = ns.GoalService.AddFromInput("Sulfuras, Hand of Ragnaros", 1)
    assert_true(ok, message)
    assert_eq(goal.target.itemID, SULFURAS)
    assert_eq(goal.type, "CRAFT_ITEM")
    local view = ns.Planner.Evaluate(goal)
    assert_eq(view.status, ns.Status.OK)
    assert_true(view.obtain)
    assert_eq(view.recipeStatus, "unlearned")
    assert_eq(view.recipe.recipeID, 21160)
    local root = view.tree.root
    assert_eq(root.route, "craft")
    assert_eq(root.routeSource, "combine")
    assert_true(root.craft.combine)
    assert_match(view.message, "combine 1 more by using Eye of Sulfuras")
    local hammer, eye
    for _, child in ipairs(root.children) do
      if child.itemID == HAMMER then hammer = child end
      if child.itemID == EYE then eye = child end
    end
    assert_eq(hammer.route, "craft")
    assert_eq(hammer.routeSource, "learn")
    assert_eq(hammer.craft.crafter.name, "Thandrel")
    assert_true(hammer.craft.crafter.isCurrent)
    assert_eq(hammer.craft.teachItemID, PLANS)
    assert_eq(hammer.children[1].itemID, PLANS)
    assert_true(hammer.children[1].learn)
    assert_eq(#hammer.children, 8, "plans plus seven reagents")
    assert_true(eye.soulbound)
    assert_true(eye.noRoute, "no loot table is loaded in tests")
    -- The shopping list carries the plans as a recipe to get and keeps the eye off the AH.
    local list = ns.ShoppingList.Build({ { goal = goal, view = view } })
    local plansRow, eyeRow
    for _, r in ipairs(list.rows) do
      if r.itemID == PLANS then plansRow = r end
      if r.itemID == EYE then eyeRow = r end
    end
    assert_true(plansRow.learn)
    assert_eq(plansRow.sources[1], "Recipe: teaches Sulfuron Hammer")
    assert_eq(eyeRow.category, "gather")
    assert_eq(eyeRow.sources[1], "Soulbound")
    -- Chat helpers.
    ns.Commands.Dispatch("recipe sulfuras, hand")
    assert_output("Combine %(use Eye of Sulfuras%)")
    ns.Commands.Dispatch("catalogue")
    assert_output("Recipe catalogue: %d+ recipes")
  end)

  it("explains a crafter who is missing or under-skilled", function()
    local goal = ns.GoalService.AddCraftGoal(HAMMER, 1)
    local view = ns.Planner.Evaluate(goal)
    assert_eq(view.status, ns.Status.OK)
    assert_eq(view.recipeStatus, "unlearned")
    assert_eq(view.tree.root.route, "buy", "no blacksmith: the hammer is bind-on-equip, so the AH is the route")
    assert_match(view.message, "0 of 1 on hand")
    assert_true(view.tree.root.craftOption.unavailable)
    blacksmith(250)
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.tree.root.craftOption.reason, "needs Blacksmithing 300; Thandrel has 250")
    blacksmith(300)
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.tree.root.route, "craft")
    assert_match(view.message, "craft 1 more with Blacksmithing %(you at 300; needs Plans: Sulfuron Hammer%)")
    local overview = ns.Overview.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_match(overview.nextSteps[1].title, "^Obtain %d+ x ")
  end)
end)
