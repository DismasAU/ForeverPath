local H = require("harness")

describe("Planner", function()
  local ns, Planner, Status
  before_each(function()
    ns = H.fresh()
    Planner = ns.Planner
    Status = ns.Status
  end)

  local recipe = {
    recipeID = 2963, name = "Bolt of Linen Cloth", outputItemID = 2996, quantityMin = 1, quantityMax = 1,
    professionID = 197, professionName = "Tailoring", scannedAt = 1792147000,
    reagents = { { itemID = 2589, quantity = 2 } },
  }

  local function deps(overrides)
    local d = {
      item = { GetItem = function(id) return { itemID = id, exists = true, loaded = true, name = "Bolt of Linen Cloth" } end },
      profession = {
        IsAvailable = function() return true end,
        HasScanData = function() return true end,
        GetScannedProfessions = function() return { { professionID = 197, name = "Tailoring" } } end,
        FindRecipesForItem = function(id) if id == 2996 then return { { recipe = recipe, learned = true } } end return {} end,
        GetRecipe = function(id, refresh) return recipe, true end,
      },
      inventory = { GetCounts = function(id) return { bags = 1, bank = nil, bankSource = "none" } end },
      data = { Lookup = function() return nil end },
      settings = { includeBank = true },
    }
    for k, v in pairs(overrides or {}) do d[k] = v end
    return d
  end

  local goal = { id = "g", type = "CRAFT_ITEM", target = { itemID = 2996, quantity = 3 } }

  it("flags unsupported goal types", function()
    local view = Planner.Evaluate({ id = "q", type = "REACH_REPUTATION", target = {} }, deps())
    assert_eq(view.status, Status.UNSUPPORTED_GOAL)
    assert_match(view.message, "Reach reputation")
  end)

  it("flags invalid items", function()
    local d = deps({ item = { GetItem = function(id) return { itemID = id, exists = false } end } })
    local view = Planner.Evaluate(goal, d)
    assert_eq(view.status, Status.ITEM_INVALID)
    assert_match(view.message, "2996")
  end)

  it("flags items the server has no data for", function()
    local d = deps({ item = { GetItem = function(id) return { itemID = id, exists = true, unavailable = true } end } })
    assert_eq(Planner.Evaluate(goal, d).status, Status.ITEM_UNAVAILABLE)
  end)

  it("flags a missing profession API", function()
    local d = deps()
    d.profession.IsAvailable = function() return false end
    local view = Planner.Evaluate(goal, d)
    assert_eq(view.status, Status.PROVIDER_UNAVAILABLE)
    assert_match(view.message, "C_TradeSkillUI")
  end)

  it("asks for a scan when no profession data exists", function()
    local d = deps()
    d.profession.FindRecipesForItem = function() return {} end
    d.profession.HasScanData = function() return false end
    local view = Planner.Evaluate(goal, d)
    assert_eq(view.status, Status.RECIPES_NOT_SCANNED)
    assert_match(view.message, "/fp scan")
  end)

  it("distinguishes 'no known recipe' from 'not scanned'", function()
    local d = deps()
    d.profession.FindRecipesForItem = function() return {} end
    local view = Planner.Evaluate(goal, d)
    assert_eq(view.status, Status.RECIPE_NOT_FOUND)
    assert_match(view.message, "Tailoring")
  end)

  it("plans an unlearned recipe as an item to get, with the craft laid out as information", function()
    local d = deps()
    d.profession.FindRecipesForItem = function() return { { recipe = recipe, learned = false } } end
    local view = Planner.Evaluate(goal, d)
    assert_eq(view.status, Status.OK)
    assert_eq(view.recipeStatus, "unlearned")
    assert_eq(view.recipe, recipe)
    assert_true(view.obtain)
    assert_eq(view.tree.root.route, "buy", "nobody to craft it: the AH is the route")
    assert_true(view.tree.root.craftOption.unavailable)
    assert_match(view.message, "^Bolt of Linen Cloth %(Tailoring%) is not learned%. 1 of 3 on hand")
    assert_true(view.plan.obtain)
    -- With a tailor on the account the craft becomes the route and its reagents the plan.
    d.characters = { WithProfession = function(name) if name == "Tailoring" then return { { name = "Mira", skillLevel = 100 } } end return {} end }
    view = Planner.Evaluate(goal, d)
    assert_eq(view.tree.root.route, "craft")
    assert_eq(view.tree.root.routeSource, "learn")
    assert_eq(view.tree.root.craft.crafter.name, "Mira")
    assert_match(view.message, "craft 2 more with Tailoring %(Mira at 100%)")
    assert_eq(view.plan.materials[1].itemID, 2589)
  end)

  it("prefers a learned recipe over an unlearned one", function()
    local other = { recipeID = 1, name = "Other", outputItemID = 2996, quantityMin = 1, reagents = {} }
    local d = deps()
    d.profession.FindRecipesForItem = function() return { { recipe = other, learned = false }, { recipe = recipe, learned = true } } end
    local view = Planner.Evaluate(goal, d)
    assert_eq(view.status, Status.OK)
    assert_eq(view.recipe.recipeID, 2963)
  end)

  it("builds a plan from live recipe data", function()
    local view = Planner.Evaluate(goal, deps())
    assert_eq(view.status, Status.OK)
    assert_true(view.recipeIsLive)
    assert_eq(view.plan.craftsNeeded, 3)
    assert_eq(view.plan.materials[1].required, 6)
    assert_eq(view.plan.materials[1].owned, 1)
    assert_eq(view.plan.materials[1].missing, 5)
    assert_match(view.message, "1 material still missing")
    assert_match(view.inventoryNote, "Bags only")
  end)

  it("mentions cached data when the live schematic is unavailable", function()
    local d = deps()
    d.profession.GetRecipe = function() return recipe, false end
    local view = Planner.Evaluate(goal, d)
    assert_eq(view.status, Status.OK)
    assert_false(view.recipeIsLive)
    assert_match(view.message, "cached from scan")
  end)

  it("reports complete plans", function()
    local d = deps({ inventory = { GetCounts = function() return { bags = 6 } end } })
    local view = Planner.Evaluate(goal, d)
    assert_true(view.plan.isComplete)
    assert_match(view.message, "on hand")
  end)

  it("flags invalid cached recipe data", function()
    local broken = { recipeID = 5, outputItemID = 2996, reagents = { { itemID = "x" } } }
    local d = deps()
    d.profession.FindRecipesForItem = function() return { { recipe = broken, learned = true } } end
    d.profession.GetRecipe = function() return broken, false end
    local view = Planner.Evaluate(goal, d)
    assert_eq(view.status, Status.RECIPE_DATA_INVALID)
  end)

  it("still plans while the item name is loading", function()
    local d = deps({ item = { GetItem = function(id) return { itemID = id, exists = true, loaded = false } end } })
    local view = Planner.Evaluate(goal, d)
    assert_eq(view.status, Status.OK)
    assert_false(view.item.loaded)
  end)

  it("describes the inventory source", function()
    local d = deps({ inventory = { GetCounts = function() return { bags = 1, bank = 2, bankSource = "live" } end } })
    assert_match(Planner.Evaluate(goal, d).inventoryNote, "live")
    d = deps({ inventory = { GetCounts = function() return { bags = 1, bank = 2, bankSource = "cached", bankScannedAt = 1792147990 - 7200 } end } })
    assert_match(Planner.Evaluate(goal, d).inventoryNote, "2h ago")
    d = deps({ settings = { includeBank = false }, inventory = { GetCounts = function() return { bags = 1, bank = 2, bankSource = "live" } end } })
    local view = Planner.Evaluate(goal, d)
    assert_match(view.inventoryNote, "excluded")
    assert_eq(view.plan.materials[1].owned, 1)
  end)

  it("attaches a dependency tree and derives the plan from its allocation", function()
    local view = Planner.Evaluate(goal, deps())
    assert_not_nil(view.tree)
    assert_eq(view.tree.root.itemID, 2996)
    assert_eq(view.tree.root.children[1].quantity, 6)
    assert_eq(view.tree.root.children[1].owned, 1)
    assert_eq(view.plan.materials[1].owned, 1)
    assert_eq(view.plan.materials[1].missing, 5)
    assert_eq(view.plan.materials[1].reserved, 0)
    assert_eq(view.tree.summary.nodes, 1)
  end)

  it("shares one allocation ledger across goals in EvaluateAll", function()
    local d = deps({ inventory = { GetCounts = function() return { bags = 3, bank = nil, bankSource = "none" } end } })
    local first = { id = "a", type = "CRAFT_ITEM", target = { itemID = 2996, quantity = 1 } }
    local second = { id = "b", type = "CRAFT_ITEM", target = { itemID = 2996, quantity = 1 } }
    local views = Planner.EvaluateAll({ first, second }, d)
    assert_eq(views.a.plan.materials[1].owned, 3)
    assert_eq(views.a.plan.materials[1].missing, 0)
    assert_eq(views.b.plan.materials[1].owned, 1, "two cloth were claimed by goal a")
    assert_eq(views.b.plan.materials[1].missing, 1)
    assert_eq(views.b.plan.materials[1].reserved, 2)
    assert_nil(d.ledger, "the temporary ledger is cleared afterwards")
    -- A lone Evaluate starts from a fresh ledger.
    assert_eq(Planner.Evaluate(second, d).plan.materials[1].owned, 3)
  end)

  it("expands craftable reagents and honours goal routes", function()
    local bag = { recipeID = 3755, name = "Linen Bag", outputItemID = 4238, quantityMin = 1, quantityMax = 1,
      professionID = 197, professionName = "Tailoring", scannedAt = 1792147000,
      reagents = { { itemID = 2996, quantity = 3 }, { itemID = 2320, quantity = 3 } } }
    local byItem = { [4238] = { { recipe = bag, learned = true } }, [2996] = { { recipe = recipe, learned = true } } }
    local d = deps()
    d.profession.FindRecipesForItem = function(itemID) return byItem[itemID] or {} end
    d.profession.GetRecipe = function(id) return id == 3755 and bag or recipe, true end
    d.inventory = { GetCounts = function() return { bags = 0, bankSource = "none" } end }
    local bagGoal = { id = "bag", type = "CRAFT_ITEM", target = { itemID = 4238, quantity = 1 } }
    local view = Planner.Evaluate(bagGoal, d)
    assert_eq(view.tree.summary.nodes, 3, "bolt, thread and the cloth under the bolt")
    assert_eq(view.tree.summary.crafts[1].itemID, 2996)
    bagGoal.routes = { [2996] = "buy" }
    view = Planner.Evaluate(bagGoal, d)
    assert_eq(view.tree.summary.nodes, 2)
    assert_eq(#view.tree.summary.crafts, 0)
  end)

  it("plans an uncraftable item from its sources instead of dead-ending", function()
    local d = deps({ sources = { Sources = function(id)
      return id == 2996 and { { kind = "drop", label = "Dropped by Kresh", detail = "Wailing Caverns (DungeonJournal)" } } or {}
    end } })
    d.profession.FindRecipesForItem = function() return {} end
    local view = Planner.Evaluate(goal, d)
    assert_eq(view.status, Status.OK)
    assert_true(view.obtain)
    assert_true(view.plan.obtain)
    assert_eq(#view.plan.materials, 1)
    assert_eq(view.plan.materials[1].itemID, 2996)
    assert_eq(view.plan.materials[1].owned, 1)
    assert_eq(view.plan.materials[1].missing, 2)
    assert_eq(view.progress.percent, 33)
    assert_eq(view.tree.root.route, "drop")
    assert_eq(view.hint.label, "Dropped by Kresh")
    assert_eq(view.sourceText, "Dropped by Kresh - Wailing Caverns (DungeonJournal)")
    assert_match(view.message, "No recipe recorded")
    assert_match(view.message, "1 of 3 on hand")
    assert_match(view.message, "Dropped by Kresh")
    assert_eq(#view.sources, 1)
    -- Without any source the explicit status stays.
    d.sources = nil
    view = Planner.Evaluate(goal, d)
    assert_eq(view.status, Status.RECIPE_NOT_FOUND)
    assert_match(view.message, "no vendor, loot table or gathering source")
  end)

  it("evaluates obtain goals, crafting the shortfall when the recipe is learned", function()
    local obtain = { id = "o", type = "OBTAIN_ITEM", target = { itemID = 2996, quantity = 3 } }
    local view = Planner.Evaluate(obtain, deps())
    assert_eq(view.status, Status.OK)
    assert_true(view.obtain)
    assert_eq(view.tree.root.owned, 1)
    assert_eq(view.tree.root.craft.crafts, 2)
    assert_eq(view.recipe.recipeID, 2963)
    assert_eq(view.plan.craftsNeeded, 2)
    assert_nil(view.plan.obtain)
    assert_eq(view.plan.materials[1].itemID, 2589)
    assert_eq(view.plan.materials[1].required, 4)
    assert_match(view.message, "1 of 3 on hand; craft 2 more with Tailoring")
    -- All on hand: a complete single-line plan.
    local d = deps({ inventory = { GetCounts = function() return { bags = 5, bankSource = "none" } end } })
    view = Planner.Evaluate(obtain, d)
    assert_true(view.plan.isComplete)
    assert_true(view.plan.obtain)
    assert_eq(view.progress.percent, 100)
    assert_match(view.message, "All 3 x Bolt of Linen Cloth on hand")
    -- Unlearned recipe on an obtain goal: no dead end, the craft is an option.
    d = deps()
    d.profession.FindRecipesForItem = function(id) if id == 2996 then return { { recipe = recipe, learned = false } } end return {} end
    view = Planner.Evaluate(obtain, d)
    assert_eq(view.status, Status.OK)
    assert_eq(view.tree.root.route, "buy")
    assert_false(view.tree.root.craftOption.learned)
    assert_true(view.plan.obtain)
    assert_match(view.message, "No source recorded yet")
    -- Nothing scanned yet: an obtain goal still plans (it does not need recipes).
    d = deps()
    d.profession.FindRecipesForItem = function() return {} end
    d.profession.HasScanData = function() return false end
    view = Planner.Evaluate(obtain, d)
    assert_eq(view.status, Status.OK)
    assert_true(view.plan.obtain)
  end)


  it("evaluates attunement goals through the Attune bridge", function()
    local attuneGoal = { id = "a", type = "COMPLETE_ATTUNEMENT", target = { attuneID = "40", name = "Onyxia's Lair", icon = "ony" } }
    local view = Planner.Evaluate(attuneGoal, deps({ attune = { IsAvailable = function() return false end } }))
    assert_eq(view.status, Status.PROVIDER_UNAVAILABLE)
    assert_match(view.message, "Attune addon")
    assert_eq(view.item.name, "Onyxia's Lair", "icon and name still come from the goal")
    local fake = {
      IsAvailable = function() return true end,
      Progress = function(id)
        if id ~= "40" then return nil end
        return { attune = { id = "40", name = "Onyxia's Lair", icon = "ony2" }, done = 6, total = 11, percent = 55, complete = false,
          next = { typeLabel = "Quest", name = "Jail Break!", location = "Blackrock Depths" }, current = {}, steps = {} }
      end,
      StepText = function(step) return step.typeLabel .. ": " .. step.name .. " - " .. step.location end,
    }
    view = Planner.Evaluate(attuneGoal, deps({ attune = fake }))
    assert_eq(view.status, Status.OK)
    assert_eq(view.attunement.percent, 55)
    assert_eq(view.progress.percent, 55)
    assert_eq(view.item.icon, "ony2")
    assert_eq(view.message, "6 of 11 steps done. Next: Quest: Jail Break! - Blackrock Depths")
    assert_eq(ns.Overview.Percent(view), 55)
    view = Planner.Evaluate({ id = "b", type = "COMPLETE_ATTUNEMENT", target = { attuneID = "99", name = "Nope" } }, deps({ attune = fake }))
    assert_eq(view.status, Status.ITEM_INVALID)
  end)

end)
