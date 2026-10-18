local H = require("harness")

describe("DependencyResolver", function()
  local ns, R
  before_each(function()
    ns = H.fresh()
    R = ns.DependencyResolver
  end)

  local CLOTH, THREAD, BOLT, BAG, ORE, BAR = 2589, 2320, 2996, 4238, 2770, 2840
  local boltRecipe = { recipeID = 2963, name = "Bolt of Linen Cloth", outputItemID = BOLT, quantityMin = 1, quantityMax = 1,
    professionID = 197, professionName = "Tailoring", reagents = { { itemID = CLOTH, quantity = 2 } } }
  local bagRecipe = { recipeID = 3755, name = "Linen Bag", outputItemID = BAG, quantityMin = 1, quantityMax = 1,
    professionID = 197, professionName = "Tailoring", reagents = { { itemID = BOLT, quantity = 3 }, { itemID = THREAD, quantity = 3 } } }

  local function opts(inventory, recipes, extra)
    local o = {
      findRecipes = function(itemID) return recipes[itemID] or {} end,
      counts = function(itemID) return inventory[itemID] or 0 end,
    }
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
  end
  local learnedBolt = { [BOLT] = { { recipe = boltRecipe, learned = true } } }

  local function child(tree, itemID, parent)
    parent = parent or tree.root
    for _, c in ipairs(parent.children) do
      if c.itemID == itemID then return c end
    end
  end

  it("lists direct reagents with owned and missing when nothing is craftable", function()
    local tree = R.Resolve({ recipe = bagRecipe, quantity = 1 }, opts({ [BOLT] = 1 }, {}))
    assert_eq(tree.root.itemID, BAG)
    assert_eq(tree.root.status, "root")
    assert_eq(tree.root.craft.crafts, 1)
    assert_eq(#tree.root.children, 2)
    local bolt = child(tree, BOLT)
    assert_eq(bolt.quantity, 3)
    assert_eq(bolt.owned, 1)
    assert_eq(bolt.available, 1)
    assert_eq(bolt.missing, 2)
    assert_eq(bolt.status, "partial")
    assert_eq(bolt.route, "buy")
    assert_eq(#bolt.children, 0)
    assert_eq(child(tree, THREAD).status, "missing")
    assert_eq(tree.summary.nodes, 2)
    assert_eq(tree.summary.resolved, 0)
    assert_eq(tree.summary.missingLeaves[1].itemID, THREAD, "biggest gap first")
    assert_eq(tree.summary.missingLeaves[1].count, 3)
    assert_eq(tree.summary.missingLeaves[2].count, 2)
    assert_eq(#tree.summary.crafts, 0)
  end)

  it("expands learned intermediates down to raw materials", function()
    local tree = R.Resolve({ recipe = bagRecipe, quantity = 1 }, opts({ [BOLT] = 1, [CLOTH] = 3 }, learnedBolt))
    local bolt = child(tree, BOLT)
    assert_eq(bolt.route, "craft")
    assert_eq(bolt.routeSource, "default")
    assert_eq(bolt.craft.crafts, 2, "2 missing bolts, 1 per craft")
    assert_eq(bolt.craft.professionName, "Tailoring")
    assert_true(bolt.craft.learned)
    local cloth = child(tree, CLOTH, bolt)
    assert_eq(cloth.depth, 2)
    assert_eq(cloth.quantity, 4)
    assert_eq(cloth.owned, 3)
    assert_eq(cloth.missing, 1)
    assert_eq(cloth.key, BAG .. ">" .. BOLT .. ">" .. CLOTH)
    assert_eq(tree.summary.nodes, 3)
    assert_eq(tree.summary.resolved, 0)
    assert_eq(tree.summary.maxDepth, 2)
    assert_eq(#tree.summary.crafts, 1)
    assert_eq(tree.summary.crafts[1].itemID, BOLT)
    assert_false(tree.summary.crafts[1].ready, "cloth still missing")
    assert_eq(tree.summary.missingLeaves[1].itemID, THREAD)
    assert_eq(tree.summary.missingLeaves[2].itemID, CLOTH)
    assert_eq(tree.summary.missingLeaves[2].count, 1)

    local rich = R.Resolve({ recipe = bagRecipe, quantity = 1 }, opts({ [BOLT] = 1, [CLOTH] = 10, [THREAD] = 3 }, learnedBolt))
    assert_true(rich.summary.crafts[1].ready)
    assert_eq(rich.summary.resolved, 2, "thread and cloth are on hand; bolts still need crafting")
    assert_eq(#rich.summary.missingLeaves, 0)
  end)

  it("plans crafts from the guaranteed minimum yield", function()
    local twoPer = ns.Util.DeepCopy(boltRecipe)
    twoPer.quantityMin, twoPer.quantityMax = 2, 4
    local recipes = { [BOLT] = { { recipe = twoPer, learned = true } } }
    local tree = R.Resolve({ recipe = bagRecipe, quantity = 1 }, opts({}, recipes))
    local bolt = child(tree, BOLT)
    assert_eq(bolt.missing, 3)
    assert_eq(bolt.craft.crafts, 2)
    assert_eq(bolt.craft.expectedOutput, 4)
    assert_eq(bolt.craft.surplus, 1)
    assert_eq(child(tree, CLOTH, bolt).quantity, 4)
  end)

  it("does not count the same stack twice inside one tree", function()
    local mixed = { recipeID = 9, name = "Mixed", outputItemID = 99, quantityMin = 1, quantityMax = 1, professionName = "Tailoring",
      reagents = { { itemID = CLOTH, quantity = 2 }, { itemID = BOLT, quantity = 1 } } }
    local tree = R.Resolve({ recipe = mixed, quantity = 1 }, opts({ [CLOTH] = 3 }, learnedBolt))
    local direct = child(tree, CLOTH)
    assert_eq(direct.owned, 2)
    assert_eq(direct.available, 3)
    local viaBolt = child(tree, CLOTH, child(tree, BOLT))
    assert_eq(viaBolt.available, 1, "only one cloth left after the direct reagent claimed two")
    assert_eq(viaBolt.owned, 1)
    assert_eq(viaBolt.missing, 1)
    assert_eq(tree.ledger:Used(CLOTH), 3)
  end)

  it("honours route overrides", function()
    local buy = R.Resolve({ recipe = bagRecipe, quantity = 1 }, opts({}, learnedBolt, { routes = { [BOLT] = "buy" } }))
    local bolt = child(buy, BOLT)
    assert_eq(bolt.route, "buy")
    assert_eq(bolt.routeSource, "override")
    assert_eq(#bolt.children, 0)
    assert_not_nil(bolt.craftOption, "the craft option is still offered")

    local unlearned = { [BOLT] = { { recipe = boltRecipe, learned = false } } }
    local default = R.Resolve({ recipe = bagRecipe, quantity = 1 }, opts({}, unlearned))
    assert_eq(child(default, BOLT).route, "buy", "unlearned recipes are not expanded by default")
    assert_false(child(default, BOLT).craftOption.learned)
    local forced = R.Resolve({ recipe = bagRecipe, quantity = 1 }, opts({}, unlearned, { routes = { [BOLT] = "craft" } }))
    assert_eq(child(forced, BOLT).route, "craft")
    assert_false(child(forced, BOLT).craft.learned)
    assert_eq(#child(forced, BOLT).children, 1)

    local noRecipe = R.Resolve({ recipe = bagRecipe, quantity = 1 }, opts({}, {}, { routes = { [THREAD] = "craft" } }))
    assert_eq(child(noRecipe, THREAD).route, "buy")
    assert_eq(child(noRecipe, THREAD).blocked, "no-recipe")
  end)

  it("stops on cycles and the depth limit", function()
    local a = { recipeID = 1, name = "A", outputItemID = 101, quantityMin = 1, quantityMax = 1, reagents = { { itemID = 102, quantity = 1 } } }
    local b = { recipeID = 2, name = "B", outputItemID = 102, quantityMin = 1, quantityMax = 1, reagents = { { itemID = 101, quantity = 1 } } }
    local recipes = { [101] = { { recipe = a, learned = true } }, [102] = { { recipe = b, learned = true } } }
    local tree = R.Resolve({ recipe = a, quantity = 1 }, opts({}, recipes))
    local bNode = child(tree, 102)
    assert_eq(bNode.route, "buy")
    assert_eq(bNode.blocked, "cycle")
    assert_eq(#bNode.children, 0)

    local chain = {}
    for i = 1, 5 do
      chain[i] = { recipeID = 100 + i, name = "L" .. i, outputItemID = 200 + i, quantityMin = 1, quantityMax = 1, reagents = { { itemID = 200 + i + 1, quantity = 1 } } }
    end
    local chainRecipes = {}
    for i = 2, 5 do chainRecipes[200 + i] = { { recipe = chain[i], learned = true } } end
    local limited = R.Resolve({ recipe = chain[1], quantity = 1 }, opts({}, chainRecipes, { maxDepth = 2 }))
    local l2 = child(limited, 202)
    local l3 = child(limited, 203, l2)
    assert_eq(l3.depth, 2)
    assert_eq(l3.route, "craft")
    assert_eq(l3.blocked, "depth")
    assert_eq(#l3.children, 0)
    assert_eq(limited.summary.blocked, 1)
  end)

  it("flattens with collapse state, unresolved filter and guide lines", function()
    local tree = R.Resolve({ recipe = bagRecipe, quantity = 1 }, opts({ [THREAD] = 3 }, learnedBolt))
    local rows = R.Flatten(tree)
    assert_eq(#rows, 4)
    assert_eq(rows[1].node.depth, 0)
    assert_eq(rows[2].node.itemID, BOLT)
    assert_false(rows[2].isLast)
    assert_true(rows[2].hasChildren)
    assert_eq(rows[3].node.itemID, CLOTH)
    assert_true(rows[3].isLast)
    assert_true(rows[3].guides[1], "bolt has a later sibling, so its guide continues past the cloth row")
    assert_eq(rows[4].node.itemID, THREAD)
    assert_true(rows[4].isLast)

    local collapsed = R.Flatten(tree, { collapsed = { [tree.root.key .. ">" .. BOLT] = true } })
    assert_eq(#collapsed, 3)
    assert_true(collapsed[2].collapsed)

    local unresolved = R.Flatten(tree, { unresolvedOnly = true })
    assert_eq(#unresolved, 3, "thread is on hand and hidden")
    assert_true(unresolved[2].isLast, "bolt becomes the last visible child")
  end)

  it("reports other goals using an item and describes the tree", function()
    local t1 = R.Resolve({ recipe = bagRecipe, quantity = 1 }, opts({}, learnedBolt))
    local t2 = R.Resolve({ recipe = boltRecipe, quantity = 2 }, opts({}, {}))
    local uses = R.UsesOf({ g1 = t1, g2 = t2 }, CLOTH, "g1")
    assert_eq(#uses, 1)
    assert_eq(uses[1].goalID, "g2")
    assert_eq(uses[1].quantity, 4)
    assert_eq(#R.UsesOf({ g1 = t1, g2 = t2 }, THREAD, "g1"), 0)

    local names = { [BAG] = "Linen Bag", [BOLT] = "Bolt", [CLOTH] = "Cloth", [THREAD] = "Thread" }
    local lines = R.Describe(t1, function(id) return names[id] end)
    assert_eq(lines[1], "Linen Bag x1 (1 craft)")
    assert_match(lines[2], "^  Bolt x3: 0/3 missing 3 via craft %- Tailoring")
    assert_match(lines[3], "^    Cloth x6: 0/6 missing 6 via buy")
    assert_eq(lines[#lines], "0 of 3 dependencies resolved")
  end)

  it("exposes direct-reagent counts for the flat plan", function()
    local tree = R.Resolve({ recipe = bagRecipe, quantity = 1 }, opts({ [BOLT] = 5, [THREAD] = { bags = 1, bank = 2, bankSource = "cached" } }, {}))
    local direct = R.DirectCounts(tree)
    assert_eq(direct[BOLT].bags, 5, "uncapped: what is free, not what was claimed")
    assert_eq(direct[THREAD].bags, 1)
    assert_eq(direct[THREAD].bank, 2)
    assert_eq(direct[THREAD].bankSource, "cached")
    assert_eq(direct[THREAD].reserved, 0)
  end)

  it("rejects bad input", function()
    local tree, err = R.Resolve({}, {})
    assert_nil(tree)
    assert_match(err, "recipe")
  end)

  it("prefers vendor, then alt, then gathering hints over the auction house", function()
    local hints = {
      [THREAD] = { { kind = "drop", label = "Humanoid drops" }, { kind = "vendor", name = "Tharynn", price = 10, label = "Buy from Tharynn" }, { kind = "alt", name = "Miravelle", count = 3 } },
      [BOLT] = { { kind = "gather", label = "Herbalism" } },
    }
    local tree = R.Resolve({ recipe = bagRecipe, quantity = 1 }, opts({}, {}, { sources = function(id) return hints[id] or {} end }))
    local thread = child(tree, THREAD)
    assert_eq(thread.route, "vendor")
    assert_eq(thread.hint.name, "Tharynn")
    assert_eq(child(tree, BOLT).route, "gather")
    assert_eq(tree.summary.missingLeaves[1].route, "vendor")
  end)

  it("resolves an obtain root as a claiming leaf with the best source", function()
    local FOOTPADS = 10411
    local tree = R.Resolve({ itemID = FOOTPADS, quantity = 2 }, opts({ [FOOTPADS] = 1 }, {}, {
      sources = function(id) return id == FOOTPADS and { { kind = "drop", label = "Dropped by Kresh", detail = "Wailing Caverns" }, { kind = "quest", label = "Quest reward: Leaders of the Fang" } } or {} end,
    }))
    assert_true(tree.obtain)
    local root = tree.root
    assert_true(root.claims)
    assert_eq(root.owned, 1)
    assert_eq(root.missing, 1)
    assert_eq(root.status, "partial")
    assert_eq(root.route, "drop", "drops rank above quests and the AH")
    assert_eq(root.hint.label, "Dropped by Kresh")
    assert_nil(root.craft)
    assert_eq(#root.options, 3, "drop, quest, buy")
    assert_eq(tree.summary.nodes, 1)
    assert_eq(#tree.summary.missingLeaves, 1)
    assert_eq(tree.summary.missingLeaves[1].itemID, FOOTPADS)
    assert_eq(tree.summary.missingLeaves[1].count, 1)
    assert_eq(tree.summary.missingLeaves[1].hint, "Wailing Caverns")
    assert_match(R.Describe(tree, function() return "Footpads" end)[1], "^Footpads x2: 1/2 missing 1 via drop")
    local uses = R.UsesOf({ a = tree }, FOOTPADS, "b")
    assert_eq(uses[1].quantity, 2, "an obtain root counts as a use of the item")
    assert_nil((R.Resolve({ quantity = 1 }, opts({}, {}))))
  end)

  it("expands an obtain root through a learned recipe", function()
    local tree = R.Resolve({ itemID = BOLT, quantity = 2 }, opts({ [BOLT] = 1, [CLOTH] = 1 }, learnedBolt))
    assert_true(tree.obtain)
    assert_eq(tree.root.route, "craft")
    assert_eq(tree.root.craft.crafts, 1)
    assert_eq(#tree.root.children, 1)
    local cloth = child(tree, CLOTH)
    assert_eq(cloth.quantity, 2)
    assert_eq(cloth.missing, 1)
    assert_eq(#tree.summary.crafts, 1, "the root craft is a craft step")
    assert_eq(tree.summary.crafts[1].itemID, BOLT)
    assert_eq(tree.summary.nodes, 2)
    -- Enough on hand: nothing expands.
    tree = R.Resolve({ itemID = BOLT, quantity = 2 }, opts({ [BOLT] = 2 }, learnedBolt))
    assert_eq(tree.root.missing, 0)
    assert_eq(#tree.root.children, 0)
    assert_eq(tree.root.status, "have")
    -- A crafting root is unchanged: it never claims and always crafts.
    tree = R.Resolve({ recipe = boltRecipe, quantity = 2 }, opts({ [BOLT] = 2 }, learnedBolt))
    assert_false(tree.root.claims == true)
    assert_eq(tree.root.status, "root")
    assert_eq(tree.root.craft.crafts, 2)
  end)

end)
