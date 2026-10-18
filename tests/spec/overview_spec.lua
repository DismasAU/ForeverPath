local H = require("harness")

describe("Overview", function()
  local ns, Overview
  before_each(function()
    ns = H.fresh()
    Overview = ns.Overview
  end)

  local names = { [1] = "Alpha Sword", [2] = "Beta Potion", [10] = "Ore", [11] = "Leather", [12] = "Thread" }
  local function nameOf(id) return names[id] or ("Item " .. id) end

  local function plan(materials, complete)
    local totals = { required = 0, owned = 0, missing = 0, materialsMissing = 0 }
    for _, m in ipairs(materials) do
      totals.required = totals.required + m.required
      totals.owned = totals.owned + math.min(m.owned, m.required)
      totals.missing = totals.missing + m.missing
      if m.missing > 0 then totals.materialsMissing = totals.materialsMissing + 1 end
    end
    return { craftsNeeded = 2, materials = materials, totals = totals, isComplete = complete }
  end

  it("aggregates missing materials across active goals", function()
    local entries = {
      { goal = { id = "a", status = "ACTIVE", type = "CRAFT_ITEM", target = { itemID = 1, quantity = 1 } },
        view = { status = "OK", plan = plan({ { itemID = 10, required = 8, owned = 2, missing = 6, perCraft = 4 }, { itemID = 11, required = 2, owned = 2, missing = 0, perCraft = 1 } }, false) } },
      { goal = { id = "b", status = "ACTIVE", type = "CRAFT_ITEM", target = { itemID = 2, quantity = 1 } },
        view = { status = "OK", plan = plan({ { itemID = 10, required = 4, owned = 0, missing = 4, perCraft = 2 }, { itemID = 12, required = 1, owned = 0, missing = 1, perCraft = 1 } }, false) } },
      { goal = { id = "c", status = "PAUSED", type = "CRAFT_ITEM", target = { itemID = 2, quantity = 1 } },
        view = { status = "OK", plan = plan({ { itemID = 12, required = 50, owned = 0, missing = 50, perCraft = 1 } }, false) } },
    }
    local overview = Overview.Build(entries, { nameOf = nameOf, craftableBy = function(id) return id == 10 and "Mining" or nil end })
    assert_eq(overview.activeCount, 2)
    assert_eq(#overview.missing, 2, "paused goals do not contribute")
    assert_eq(overview.missing[1].itemID, 10)
    assert_eq(overview.missing[1].count, 10)
    assert_deep_eq(overview.missing[1].goals, { "Alpha Sword", "Beta Potion" })
    assert_eq(overview.missing[1].craftableBy, "Mining")
    assert_eq(overview.missing[2].itemID, 12)
    assert_eq(#overview.nextSteps, 2)
    assert_eq(overview.nextSteps[1].title, "Obtain 6 x Ore")
    assert_match(overview.nextSteps[1].badge, "Mining")
    assert_eq(overview.nextSteps[1].goalID, "a")
  end)

  it("recommends crafting when everything is on hand and explains blockers", function()
    local entries = {
      { goal = { id = "a", status = "ACTIVE", type = "CRAFT_ITEM", target = { itemID = 1, quantity = 2 } },
        view = { status = "OK", plan = plan({ { itemID = 10, required = 2, owned = 5, missing = 0, perCraft = 1 } }, true) } },
      { goal = { id = "b", status = "ACTIVE", type = "CRAFT_ITEM", target = { itemID = 2, quantity = 1 } },
        view = { status = ns.Status.RECIPES_NOT_SCANNED } },
      { goal = { id = "c", status = "ACTIVE", type = "CRAFT_ITEM", target = { itemID = 2, quantity = 1 } },
        view = { status = ns.Status.RECIPE_NOT_LEARNED, recipe = { name = "Beta Potion", professionName = "Alchemy" } } },
      { goal = { id = "d", status = "ACTIVE", type = "CRAFT_ITEM", target = { itemID = 2, quantity = 1 } },
        view = { status = ns.Status.RECIPE_NOT_FOUND } },
    }
    local overview = Overview.Build(entries, { nameOf = nameOf })
    assert_eq(#overview.nextSteps, 3, "capped at three steps")
    assert_eq(overview.nextSteps[1].title, "Craft 2 x Alpha Sword")
    assert_eq(overview.nextSteps[1].badge, "Ready")
    assert_eq(overview.nextSteps[2].badge, "Scan")
    assert_eq(overview.nextSteps[3].title, "Learn Beta Potion")
    assert_eq(#overview.missing, 0)
  end)

  it("computes percentages and missing summaries", function()
    assert_nil(Overview.Percent(nil))
    assert_nil(Overview.Percent({}))
    local view = { plan = plan({ { itemID = 10, required = 8, owned = 2, missing = 6, perCraft = 4 }, { itemID = 11, required = 2, owned = 2, missing = 0, perCraft = 1 } }, false) }
    assert_eq(Overview.Percent(view), 40)
    assert_eq(Overview.MissingSummary(view, nameOf), "Missing: 6 Ore")
    local many = { plan = plan({
      { itemID = 10, required = 1, owned = 0, missing = 1, perCraft = 1 }, { itemID = 11, required = 1, owned = 0, missing = 1, perCraft = 1 },
      { itemID = 12, required = 1, owned = 0, missing = 1, perCraft = 1 }, { itemID = 13, required = 1, owned = 0, missing = 1, perCraft = 1 },
    }, false) }
    assert_match(Overview.MissingSummary(many, nameOf, 2), "^Missing: 1 Ore, 1 Leather, %+2 more$")
    assert_eq(Overview.MissingSummary({ plan = plan({}, true) }, nameOf), "All materials on hand")
    assert_eq(Overview.Percent({ plan = plan({}, true) }), 100)
  end)

  it("uses the dependency tree for missing leaves and next steps", function()
    local R = ns.DependencyResolver
    local boltRecipe = { recipeID = 1, name = "Bolt", outputItemID = 20, quantityMin = 1, quantityMax = 1, professionName = "Tailoring",
      reagents = { { itemID = 10, quantity = 2 } } }
    local bagRecipe = { recipeID = 2, name = "Bag", outputItemID = 1, quantityMin = 1, quantityMax = 1, professionName = "Tailoring",
      reagents = { { itemID = 20, quantity = 3 }, { itemID = 12, quantity = 3 } } }
    local recipes = { [20] = { { recipe = boltRecipe, learned = true } } }
    local function build(inventory)
      local tree = R.Resolve({ recipe = bagRecipe, quantity = 1 }, {
        findRecipes = function(id) return recipes[id] or {} end,
        counts = function(id) return inventory[id] or 0 end,
      })
      local direct = R.DirectCounts(tree)
      local plan = ns.CraftingEngine.BuildPlan(bagRecipe, 1, function(id) return direct[id] or 0 end)
      return { goal = { id = "a", status = "ACTIVE", type = "CRAFT_ITEM", target = { itemID = 1, quantity = 1 } }, view = { status = "OK", plan = plan, tree = tree } }
    end
    local names2 = { [1] = "Bag", [20] = "Bolt", [10] = "Ore", [12] = "Thread" }
    local function nameOf2(id) return names2[id] or ("Item " .. id) end

    local overview = Overview.Build({ build({ [12] = 3 }) }, { nameOf = nameOf2 })
    assert_eq(#overview.missing, 1, "the bolt is crafted, so only its raw ore is listed")
    assert_eq(overview.missing[1].itemID, 10)
    assert_eq(overview.missing[1].count, 6)
    assert_eq(overview.nextSteps[1].title, "Obtain 6 x Ore")
    assert_eq(overview.nextSteps[1].badge, "Buy")
    assert_match(overview.nextSteps[1].detail, "1 of 3 dependencies resolved")

    overview = Overview.Build({ build({ [12] = 3, [10] = 6 }) }, { nameOf = nameOf2 })
    assert_eq(#overview.missing, 0)
    assert_eq(overview.nextSteps[1].title, "Craft 3 x Bolt")
    assert_eq(overview.nextSteps[1].badge, "Craft - Tailoring")
  end)

  it("describes obtain goals", function()
    local done = plan({ { itemID = 2, required = 1, owned = 1, missing = 0, perCraft = 1 } }, true)
    done.obtain, done.quantityWanted = true, 1
    local entries = {
      { goal = { id = "a", status = "ACTIVE", type = "OBTAIN_ITEM", target = { itemID = 2, quantity = 1 } }, view = { status = "OK", plan = done } },
    }
    local overview = Overview.Build(entries, { nameOf = nameOf })
    assert_eq(overview.nextSteps[1].title, "1 x Beta Potion on hand")
    assert_eq(overview.nextSteps[1].badge, "Ready")
    assert_eq(overview.nextSteps[1].detail, "Mark the goal complete")
    -- A missing obtain root is the thing to get, with its source as the badge.
    local tree = ns.DependencyResolver.Resolve({ itemID = 1, quantity = 2 }, {
      findRecipes = function() return {} end, counts = function() return 0 end,
      sources = function() return { { kind = "drop", label = "Dropped by Kresh", detail = "Wailing Caverns" } } end,
    })
    local open = plan({ { itemID = 1, required = 2, owned = 0, missing = 2, perCraft = 1 } }, false)
    open.obtain = true
    overview = Overview.Build({ { goal = { id = "b", status = "ACTIVE", type = "OBTAIN_ITEM", target = { itemID = 1, quantity = 2 } }, view = { status = "OK", plan = open, tree = tree } } }, { nameOf = nameOf })
    assert_eq(overview.nextSteps[1].title, "Obtain 2 x Alpha Sword")
    assert_eq(overview.nextSteps[1].badge, "Drop")
    assert_match(overview.nextSteps[1].detail, "^Wailing Caverns %- For Alpha Sword")
    assert_eq(overview.missing[1].itemID, 1)
    assert_eq(overview.missing[1].count, 2)
  end)


  it("turns the next attunement step into a recommended step", function()
    local view = { status = "OK", attunement = { done = 6, total = 11, percent = 55, complete = false,
      next = { typeLabel = "Quest", name = "Jail Break!", location = "Blackrock Depths", inLog = true } } }
    local goal = { id = "a", status = "ACTIVE", type = "COMPLETE_ATTUNEMENT", target = { attuneID = "40", name = "Onyxia's Lair" } }
    local overview = Overview.Build({ { goal = goal, view = view } }, { nameOf = nameOf })
    assert_eq(overview.nextSteps[1].title, "Quest: Jail Break!")
    assert_eq(overview.nextSteps[1].detail, "Blackrock Depths - step 7 of 11 for Onyxia's Lair")
    assert_eq(overview.nextSteps[1].badge, "Quest")
    assert_eq(overview.nextSteps[1].badgeKind, "ok")
    assert_eq(Overview.Percent(view), 55)
    view.attunement.complete = true
    overview = Overview.Build({ { goal = goal, view = view } }, { nameOf = nameOf })
    assert_eq(overview.nextSteps[1].title, "Attuned: Onyxia's Lair")
    assert_eq(#overview.missing, 0)
  end)

end)
