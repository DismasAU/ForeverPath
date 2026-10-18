local H = require("harness")

describe("ShoppingList", function()
  local ns, SL, R
  before_each(function()
    ns = H.fresh()
    SL = ns.ShoppingList
    R = ns.DependencyResolver
  end)

  local CLOTH, THREAD, BOLT, BAG = 2589, 2320, 2996, 4238
  local names = { [CLOTH] = "Linen Cloth", [THREAD] = "Coarse Thread", [BOLT] = "Bolt of Linen Cloth", [BAG] = "Linen Bag" }
  local function nameOf(id) return names[id] or ("Item " .. id) end
  local boltRecipe = { recipeID = 2963, name = "Bolt", outputItemID = BOLT, quantityMin = 1, quantityMax = 1, professionName = "Tailoring", reagents = { { itemID = CLOTH, quantity = 2 } } }
  local bagRecipe = { recipeID = 3755, name = "Bag", outputItemID = BAG, quantityMin = 1, quantityMax = 1, professionName = "Tailoring", reagents = { { itemID = BOLT, quantity = 3 }, { itemID = THREAD, quantity = 3 } } }
  local recipes = { [BOLT] = { { recipe = boltRecipe, learned = true } } }

  -- Two goals sharing one ledger, like Planner.EvaluateAll.
  local function entries(inventory, statuses, sources)
    local ledger = ns.Allocation.New()
    local function resolve(recipe, qty)
      return R.Resolve({ recipe = recipe, quantity = qty }, {
        findRecipes = function(id) return recipes[id] or {} end,
        counts = function(id) return inventory[id] or 0 end,
        ledger = ledger, sources = sources,
      })
    end
    return {
      { goal = { id = "bag", status = statuses[1] or "ACTIVE", type = "CRAFT_ITEM", target = { itemID = BAG, quantity = 1 } }, view = { tree = resolve(bagRecipe, 1) } },
      { goal = { id = "bolt", status = statuses[2] or "ACTIVE", type = "CRAFT_ITEM", target = { itemID = BOLT, quantity = 1 } }, view = { tree = resolve(boltRecipe, 1) } },
    }
  end

  it("aggregates every tree node per item with totals, owned and missing", function()
    local list = SL.Build(entries({ [CLOTH] = 5 }, {}), { nameOf = nameOf })
    assert_eq(#list.goals, 2)
    assert_true(list.goals[1].included)
    assert_eq(list.goals[1].name, "Linen Bag")
    assert_eq(#list.rows, 3, "thread, cloth and the bolts to craft")
    local thread, cloth, bolt = list.rows[1], list.rows[2], list.rows[3]
    assert_eq(thread.itemID, THREAD, "equal gaps: lowest item id first")
    assert_eq(thread.missing, 3)
    assert_eq(cloth.itemID, CLOTH)
    assert_eq(cloth.total, 8, "6 for the bag's bolts + 2 for the bolt goal")
    assert_eq(cloth.owned, 5)
    assert_eq(cloth.missing, 3)
    assert_eq(cloth.reserved, 0)
    assert_eq(cloth.category, "buy")
    assert_deep_eq(cloth.sources, { "AH" })
    assert_deep_eq(cloth.goals, { "Linen Bag", "Bolt of Linen Cloth" })
    assert_eq(bolt.itemID, BOLT)
    assert_eq(bolt.category, "craft")
    assert_eq(bolt.missing, 3)
    assert_deep_eq(bolt.sources, { "Craft - Tailoring", "AH" })
    assert_eq(list.counts.all, 3)
    assert_eq(list.counts.buy, 2)
    assert_eq(list.counts.craft, 1)
    assert_eq(list.units.total, 14)
    assert_eq(list.units.owned, 5)
    assert_eq(list.units.missing, 9)
    assert_eq(list.units.percent, 36)
    assert_eq(#list.mail, 0)
  end)

  it("keeps paused goals off the list and shows what they hold as reserved", function()
    -- Bag goal (priority 1) is paused but still claims 5 cloth; the bolt goal gets none.
    local list = SL.Build(entries({ [CLOTH] = 5 }, { "PAUSED", "ACTIVE" }), { nameOf = nameOf })
    assert_false(list.goals[1].included)
    assert_eq(#list.rows, 1)
    local cloth = list.rows[1]
    assert_eq(cloth.total, 2)
    assert_eq(cloth.owned, 2, "two cloth are physically there for this row")
    assert_eq(cloth.reserved, 2, "but the paused goal holds them")
    assert_eq(cloth.usable, 0)
    assert_eq(cloth.missing, 2)
    assert_deep_eq(cloth.goals, { "Bolt of Linen Cloth" })
    assert_eq(list.units.owned, 0)
    -- Explicit membership overrides the default.
    list = SL.Build(entries({ [CLOTH] = 5 }, { "PAUSED", "ACTIVE" }), { nameOf = nameOf, included = function(goal) return goal.id == "bag" end })
    assert_eq(#list.rows, 3)
    local byItem = {}
    for _, r in ipairs(list.rows) do byItem[r.itemID] = r end
    assert_eq(byItem[CLOTH].owned, 5)
    assert_eq(byItem[CLOTH].reserved, 0)
    assert_eq(byItem[CLOTH].missing, 1)
  end)

  it("classifies craft and alt rows, plans mail and ticks bought items", function()
    local sources = function(id)
      if id == THREAD then return { { kind = "alt", name = "Miravelle", count = 2, label = "Mail from Miravelle", detail = "Miravelle has 2" } } end
      return {}
    end
    local list = SL.Build(entries({ [CLOTH] = 0 }, {}, sources), { nameOf = nameOf, bought = { [CLOTH] = true } })
    local byItem = {}
    for _, r in ipairs(list.rows) do byItem[r.itemID] = r end
    assert_eq(byItem[THREAD].category, "alt")
    assert_deep_eq(byItem[THREAD].sources, { "Alt: Miravelle", "AH" })
    assert_eq(byItem[THREAD].altHolders.Miravelle, 2)
    assert_eq(#list.mail, 1)
    assert_eq(list.mail[1].name, "Miravelle")
    assert_eq(list.mail[1].items[1].itemID, THREAD)
    assert_eq(list.mail[1].items[1].count, 2, "she only has two of the three")
    assert_true(byItem[CLOTH].bought)
    assert_eq(list.counts.bought, 1)
    assert_eq(list.counts.alt, 1)
    assert_eq(list.rows[#list.rows].itemID, CLOTH, "bought rows sink to the bottom")

    -- Force the bolt to be bought: it becomes a craftable-category row.
    local forced = entries({ [CLOTH] = 0 }, {})
    forced[1].view.tree = R.Resolve({ recipe = bagRecipe, quantity = 1 }, {
      findRecipes = function(id) return recipes[id] or {} end, counts = function() return 0 end, routes = { [BOLT] = "buy" },
    })
    list = SL.Build(forced, { nameOf = nameOf })
    byItem = {}
    for _, r in ipairs(list.rows) do byItem[r.itemID] = r end
    assert_eq(byItem[BOLT].category, "buy")
    assert_deep_eq(byItem[BOLT].sources, { "Craft - Tailoring", "AH" })
    assert_eq(#SL.Filter(list.rows, "buy"), 3)
    assert_eq(#SL.Filter(list.rows, "craft"), 0)
    assert_eq(#SL.Filter(list.rows, "all"), 3)
  end)

  it("sorts by name, total and source", function()
    local list = SL.Build(entries({ [CLOTH] = 5 }, {}), { nameOf = nameOf, sort = "name" })
    assert_eq(list.rows[1].itemID, BOLT, "Bolt before Coarse Thread before Linen Cloth")
    assert_eq(list.rows[2].itemID, THREAD)
    SL.Sort(list.rows, "total", nameOf)
    assert_eq(list.rows[1].itemID, CLOTH)
    SL.Sort(list.rows, "source", nameOf)
    assert_eq(list.rows[1].itemID, THREAD, "Auction House rows before craftable ones; equal gaps by id")
    assert_eq(list.rows[3].itemID, BOLT)
  end)

  it("renders chat lines with links when available", function()
    local sources = function(id)
      if id == THREAD then return { { kind = "alt", name = "Miravelle", count = 5 } } end
      return {}
    end
    local list = SL.Build(entries({ [CLOTH] = 5 }, {}, sources), { nameOf = nameOf, bought = { [CLOTH] = true } })
    local lines = SL.Lines(list, nameOf, function(id) return id == CLOTH and "|Hitem:2589|h[Linen Cloth]|h" or nil end)
    assert_match(lines[1], "^Shopping list %(3 items for Linen Bag, Bolt of Linen Cloth%): 5 of 14 units in hand")
    assert_match(lines[2], "3 x Coarse Thread %- Alt: Miravelle, AH")
    assert_match(lines[3], "3 x Bolt of Linen Cloth %- Craft %- Tailoring, AH")
    assert_match(lines[4], "%[bought%] 3 x |Hitem:2589|h%[Linen Cloth%]|h %- AH")
    assert_match(lines[5], "Mail from Miravelle: 3 x Coarse Thread")
    assert_eq(#lines, 5)
  end)

  it("prices rows from the price callback and classifies vendor rows", function()
    local sources = function(id)
      if id == THREAD then return { { kind = "vendor", name = "Tharynn", price = 10, label = "Buy from Tharynn" } } end
      return {}
    end
    local list = SL.Build(entries({ [CLOTH] = 5 }, {}, sources), { nameOf = nameOf, priceOf = function(id) return id == THREAD and 10 or nil end })
    local byItem = {}
    for _, r in ipairs(list.rows) do byItem[r.itemID] = r end
    assert_eq(byItem[THREAD].category, "vendor")
    assert_deep_eq(byItem[THREAD].sources, { "Vendor: Tharynn", "AH" })
    assert_eq(byItem[THREAD].unitPrice, 10)
    assert_eq(byItem[THREAD].cost, 30)
    assert_nil(byItem[CLOTH].cost)
    assert_eq(list.cost.known, 30)
    assert_eq(list.cost.pricedRows, 1)
    assert_eq(list.cost.unpricedRows, 1, "cloth is unpriced; the craftable bolt does not count")
    assert_eq(list.counts.vendor, 1)
    assert_eq(#SL.Filter(list.rows, "vendor"), 1)
  end)

  it("lists an obtain goal's item itself", function()
    local tree = R.Resolve({ itemID = 10411, quantity = 2 }, {
      findRecipes = function() return {} end, counts = function() return 1 end,
      sources = function() return { { kind = "quest", label = "Quest reward: Leaders of the Fang", detail = "Wailing Caverns" } } end,
    })
    local list = SL.Build({ { goal = { id = "o", status = "ACTIVE", type = "OBTAIN_ITEM", target = { itemID = 10411, quantity = 2 } }, view = { tree = tree } } }, { nameOf = nameOf })
    assert_eq(#list.rows, 1)
    local row = list.rows[1]
    assert_eq(row.itemID, 10411)
    assert_eq(row.total, 2)
    assert_eq(row.owned, 1)
    assert_eq(row.missing, 1)
    assert_eq(row.category, "gather", "quest rewards sit with gathering and drops")
    assert_eq(row.sources[1], "Quest reward: Leaders of the Fang")
    assert_eq(list.counts.gather, 1)
    assert_eq(list.units.total, 2)
  end)


  it("tells whether the remaining cost is affordable now, with alts' gold, or not at all", function()
    local prices = { [THREAD] = 10, [CLOTH] = 4 }
    local priceOf = function(id) return prices[id] end
    local list = SL.Build(entries({}, {}), { nameOf = nameOf, priceOf = priceOf, gold = { current = 100, account = 160 } })
    -- bag: 3 thread (30c) + bolts crafted from 6 cloth; bolt goal: 2 cloth. 8 cloth = 32c. Total 62c.
    assert_eq(list.cost.known, 62)
    assert_eq(list.cost.remaining, 62)
    local aff = list.affordability
    assert_eq(aff.status, "now")
    assert_eq(aff.shortNow, 0)
    assert_eq(aff.altsGold, 60)
    for _, r in ipairs(list.rows) do if r.cost then assert_eq(r.affordable, "now") end end
    assert_match(SL.AffordabilityText(aff), "^Affordable now: 62c of your 100c$")
    assert_match(SL.Lines(list, nameOf)[2], "^  Cost: Affordable now")
    -- Only the account covers it.
    list = SL.Build(entries({}, {}), { nameOf = nameOf, priceOf = priceOf, gold = { current = 31, account = 100 } })
    aff = list.affordability
    assert_eq(aff.status, "account")
    assert_eq(aff.shortNow, 31)
    assert_eq(aff.shortAccount, 0)
    assert_match(SL.AffordabilityText(aff), "^Short by 31c on this character; alts hold 69c, so the account covers it$")
    local byItem = {}
    for _, r in ipairs(list.rows) do byItem[r.itemID] = r end
    assert_eq(byItem[THREAD].affordable, "now", "30c fits in 31c")
    assert_eq(byItem[CLOTH].affordable, "account", "32c does not")
    -- Nobody can pay.
    list = SL.Build(entries({}, {}), { nameOf = nameOf, priceOf = priceOf, gold = { current = 5, account = 20 } })
    aff = list.affordability
    assert_eq(aff.status, "no")
    assert_eq(aff.shortAccount, 42)
    assert_match(SL.AffordabilityText(aff), "^Not affordable: short by 42c even with every character's gold$")
    for _, r in ipairs(list.rows) do if r.cost then assert_eq(r.affordable, "no") end end
    -- Bought rows no longer count; unpriced rows are mentioned; no gold = unknown.
    list = SL.Build(entries({}, {}), { nameOf = nameOf, priceOf = function(id) return id == THREAD and 10 or nil end, bought = { [THREAD] = true }, gold = { current = 5 } })
    assert_eq(list.cost.bought, 30)
    assert_eq(list.cost.remaining, 0)
    assert_match(SL.AffordabilityText(list.affordability), "^Nothing left to pay for %(1 item unpriced%)$")
    list = SL.Build(entries({}, {}), { nameOf = nameOf, priceOf = priceOf })
    assert_eq(list.affordability.status, "unknown")
    assert_nil(list.rows[1].affordable)
    assert_nil((SL.AffordabilityText(list.affordability)))
    assert_nil((SL.Affordable(5, nil)))
    assert_eq(SL.Affordable(5, { account = 10 }), "account")
  end)

end)
