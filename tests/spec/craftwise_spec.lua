local H = require("harness")

describe("CraftWise", function()
  local ns, CW, R
  before_each(function()
    ns = H.fresh()
    CW = ns.CraftWise
    R = ns.DependencyResolver
  end)

  local CLOTH, THREAD, BOLT, BAG = 2589, 2320, 2996, 4238
  local boltRecipe = { recipeID = 2963, name = "Bolt", outputItemID = BOLT, quantityMin = 1, quantityMax = 1, professionName = "Tailoring", reagents = { { itemID = CLOTH, quantity = 2 } } }
  local bagRecipe = { recipeID = 3755, name = "Bag", outputItemID = BAG, quantityMin = 1, quantityMax = 1, professionName = "Tailoring", reagents = { { itemID = BOLT, quantity = 3 }, { itemID = THREAD, quantity = 3 } } }
  local recipes = { [BOLT] = { { recipe = boltRecipe, learned = true } } }

  local function tree(inventory, extra)
    local opts = { findRecipes = function(id) return recipes[id] or {} end, counts = function(id) return inventory[id] or 0 end }
    for k, v in pairs(extra or {}) do opts[k] = v end
    return R.Resolve({ recipe = bagRecipe, quantity = 1 }, opts)
  end

  local function pricer(prices)
    return function(itemID)
      local p = prices[itemID]
      if not p then return nil end
      if type(p) == "number" then return { copper = p, kind = "market", scannedAt = 1792147990 - 600 } end
      return p
    end
  end

  local function row(result, itemID)
    for _, r in ipairs(result.rows) do if r.itemID == itemID then return r end end
  end

  it("compares buying, crafting and the hybrid per component", function()
    local prices = { [CLOTH] = 10, [THREAD] = 20, [BOLT] = 15, [BAG] = 500 }
    local result = CW.Compare(tree({}), { priceOf = pricer(prices) })
    assert_eq(result.buy.cost, 500, "buy the finished bag")
    assert_eq(result.craft.cost, 120, "6 cloth + 3 thread")
    assert_eq(result.hybrid.cost, 105, "3 bolts bought at 15c beat crafting them from 60c of cloth")
    assert_eq(result.recommended, "hybrid")
    assert_eq(result.savings.buy, 395)
    assert_eq(result.savings.craft, 15)
    assert_eq(result.hybrid.unknown, 0)
    assert_eq(result.unpriced, 0)
    assert_true(result.available)
    local bolt = row(result, BOLT)
    assert_eq(bolt.depth, 1)
    assert_eq(bolt.buy, 45)
    assert_eq(bolt.craftPath, 60)
    assert_eq(bolt.craft, 60)
    assert_eq(bolt.hybrid, 45)
    assert_eq(bolt.choice, "buy")
    assert_true(bolt.switchable)
    assert_eq(row(result, CLOTH).depth, 2)
    assert_eq(row(result, CLOTH).buy, 60)
    assert_eq(row(result, THREAD).choice, "buy")
    assert_eq(row(result, THREAD).hybrid, 60)
    assert_eq(result.plan[BOLT], "buy")
    assert_nil(result.plan[THREAD], "only craftable components get a route")
    assert_eq(#result.hybrid.buyList, 2)
    assert_eq(result.hybrid.buyList[1].itemID, BOLT)
    assert_eq(#result.hybrid.craftList, 0)
    assert_eq(result.rootRow.choice, "craft", "crafting the bag (105c) beats buying it (500c)")
    assert_eq(result.hybrid.freshness.key, "fresh")
    -- Cheaper cloth flips the bolt to crafting.
    prices[CLOTH] = 2
    result = CW.Compare(tree({}), { priceOf = pricer(prices) })
    assert_eq(result.hybrid.cost, 12 + 60)
    assert_eq(row(result, BOLT).choice, "craft")
    assert_eq(result.plan[BOLT], "craft")
    assert_eq(#result.hybrid.craftList, 1)
    assert_eq(result.hybrid.craftList[1].crafts, 3)
    assert_eq(result.craft.cost, result.hybrid.cost)
    assert_eq(result.recommended, "hybrid", "ties go to the hybrid")
    assert_eq(result.savings.craft, 0)
  end)

  it("keeps unknown prices unknown instead of pricing them at zero", function()
    local prices = { [CLOTH] = 10, [BOLT] = 15, [BAG] = 500 }
    local result = CW.Compare(tree({}), { priceOf = pricer(prices) })
    assert_nil(result.craft.cost)
    assert_eq(result.craft.unknown, 1)
    assert_nil(result.hybrid.cost)
    assert_eq(result.hybrid.unknown, 1)
    assert_eq(result.recommended, "buy", "the only fully priced strategy")
    assert_eq(result.unpriced, 1)
    assert_nil(row(result, THREAD).buy)
    assert_nil(row(result, THREAD).freshness)
    assert_eq(row(result, THREAD).unknown, 1)
    -- No prices at all: nothing is available.
    result = CW.Compare(tree({}), { priceOf = function() return nil end })
    assert_false(result.available)
    assert_nil(result.recommended)
    assert_nil(result.buy.cost)
    assert_nil(result.savings)
  end)

  it("counts owned stock and alt holdings as free", function()
    local prices = { [CLOTH] = 10, [THREAD] = 20, [BOLT] = 15, [BAG] = 500 }
    local result = CW.Compare(tree({ [CLOTH] = 6 }), { priceOf = pricer(prices) })
    local cloth = row(result, CLOTH)
    assert_eq(cloth.choice, "owned")
    assert_eq(cloth.hybrid, 0)
    assert_eq(row(result, BOLT).craft, 0)
    assert_eq(row(result, BOLT).choice, "craft", "crafting from owned cloth is free")
    assert_eq(result.hybrid.cost, 60, "only the thread is bought")
    assert_eq(result.craft.cost, 60)
    assert_eq(result.hybrid.ownedList[1].itemID, CLOTH)
    assert_eq(result.hybrid.ownedList[1].count, 6)
    assert_eq(result.rootRow.choice, "craft")
    -- An alt holds the thread: nothing to buy at all.
    local altTree = tree({ [CLOTH] = 6 }, { sources = function(id) return id == THREAD and { { kind = "alt", name = "Miravelle", count = 3, label = "Miravelle has 3" } } or {} end })
    result = CW.Compare(altTree, { priceOf = pricer(prices) })
    assert_eq(row(result, THREAD).choice, "alt")
    assert_eq(result.hybrid.cost, 0)
    assert_eq(#result.hybrid.altList, 1)
    assert_eq(result.hybrid.altList[1].name, "Miravelle")
    assert_eq(result.recommended, "hybrid")
  end)

  it("plans routes, recognises presets and prices obtain trees", function()
    local prices = { [CLOTH] = 10, [THREAD] = 20, [BOLT] = 15, [BAG] = 500 }
    local result = CW.Compare(tree({}), { priceOf = pricer(prices) })
    local applied = {}
    local changed = CW.ApplyPlan(result, function(itemID, route) applied[itemID] = route or "default" return true end)
    assert_eq(changed, 1)
    assert_eq(applied[BOLT], "buy")
    assert_eq(CW.Mode(result, nil), "default")
    assert_eq(CW.Mode(result, { [BOLT] = "buy" }), "hybrid")
    assert_eq(CW.Mode(result, { [BOLT] = "craft" }), "custom")
    assert_eq(CW.Mode(result, { [CLOTH] = "buy" }), "custom")
    assert_deep_eq(CW.BuyAllPlan(result), { [BOLT] = "buy" })
    assert_eq(CW.Mode(result, CW.BuyAllPlan(result)), "hybrid", "here buying all materials is the hybrid plan")
    assert_eq(CW.ChoiceLabels.altcraft, "Alt crafts")
    -- Obtain tree: the root is a leaf with a market price.
    local obtain = R.Resolve({ itemID = 10411, quantity = 2 }, { findRecipes = function() return {} end, counts = function() return 1 end })
    result = CW.Compare(obtain, { priceOf = pricer({ [10411] = 300 }) })
    assert_eq(result.buy.cost, 300, "one of two still missing")
    assert_false(result.craft.possible)
    assert_eq(result.hybrid.cost, 300)
    assert_eq(result.recommended, "hybrid")
    assert_nil((CW.Compare(nil)))
  end)
end)
