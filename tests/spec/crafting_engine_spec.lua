local H = require("harness")

describe("CraftingEngine", function()
  local ns, Engine
  before_each(function()
    ns = H.fresh()
    Engine = ns.CraftingEngine
  end)

  local recipe = {
    recipeID = 1, outputItemID = 100, quantityMin = 1, quantityMax = 1,
    reagents = { { itemID = 10, quantity = 2 }, { itemID = 11, quantity = 3 } },
  }

  it("computes crafts needed with multi-output recipes", function()
    assert_eq(Engine.CraftsNeeded(5, 2), 3)
    assert_eq(Engine.CraftsNeeded(4, 2), 2)
    assert_eq(Engine.CraftsNeeded(1, 5), 1)
    assert_eq(Engine.CraftsNeeded(3, nil), 3)
    assert_eq(Engine.CraftsNeeded(0, 2), 0)
  end)

  it("multiplies reagent quantities by crafts", function()
    local req = Engine.ComputeRequirements(recipe, 4)
    assert_eq(req.craftsNeeded, 4)
    assert_eq(req.expectedOutput, 4)
    assert_eq(req.materials[1].required, 8)
    assert_eq(req.materials[2].required, 12)
  end)

  it("uses the guaranteed minimum yield for multi-output recipes", function()
    local multi = { recipeID = 2, outputItemID = 200, quantityMin = 2, quantityMax = 4, reagents = { { itemID = 10, quantity = 1 } } }
    local req = Engine.ComputeRequirements(multi, 5)
    assert_eq(req.craftsNeeded, 3)
    assert_eq(req.expectedOutput, 6)
    assert_eq(req.outputPerCraftMax, 4)
    assert_eq(req.materials[1].required, 3)
  end)

  it("merges the same reagent listed twice", function()
    local dup = { recipeID = 3, outputItemID = 300, quantityMin = 1, reagents = { { itemID = 10, quantity = 1 }, { itemID = 10, quantity = 2 } } }
    local req = Engine.ComputeRequirements(dup, 2)
    assert_eq(#req.materials, 1)
    assert_eq(req.materials[1].required, 6)
  end)

  it("rejects malformed recipes and quantities", function()
    local req, err = Engine.ComputeRequirements({ recipeID = 1 }, 1)
    assert_nil(req)
    assert_not_nil(err)
    req, err = Engine.ComputeRequirements(recipe, 0)
    assert_nil(req)
    assert_match(err, "quantity")
    assert_nil(Engine.ComputeRequirements(recipe, 1.5))
    assert_nil(Engine.ComputeRequirements(recipe, "2"))
    assert_nil(Engine.BuildPlan(nil, 1))
  end)

  it("calculates missing = max(0, required - owned)", function()
    local counts = { [10] = { bags = 0 }, [11] = { bags = 5 } }
    local plan = Engine.BuildPlan(recipe, 2, function(id) return counts[id] end)
    assert_eq(plan.materials[1].required, 4)
    assert_eq(plan.materials[1].owned, 0)
    assert_eq(plan.materials[1].missing, 4)
    assert_eq(plan.materials[2].required, 6)
    assert_eq(plan.materials[2].owned, 5)
    assert_eq(plan.materials[2].missing, 1)
    assert_eq(plan.totals.missing, 5)
    assert_eq(plan.totals.materialsMissing, 2)
    assert_false(plan.isComplete)
  end)

  it("never reports negative missing when more is owned than needed", function()
    local plan = Engine.BuildPlan(recipe, 1, function() return 999 end)
    assert_eq(plan.materials[1].missing, 0)
    assert_eq(plan.materials[2].missing, 0)
    assert_eq(plan.totals.owned, 5, "owned total is capped at required")
    assert_true(plan.isComplete)
  end)

  it("treats an exact match as complete", function()
    local plan = Engine.BuildPlan(recipe, 1, function(id) return id == 10 and 2 or 3 end)
    assert_true(plan.isComplete)
    assert_eq(plan.totals.missing, 0)
  end)

  it("includes or excludes bank counts", function()
    local lookup = function() return { bags = 1, bank = 4, bankSource = "cached" } end
    local withBank = Engine.BuildPlan(recipe, 1, lookup, { includeBank = true })
    assert_eq(withBank.materials[1].owned, 5)
    assert_eq(withBank.materials[1].ownedBank, 4)
    assert_eq(withBank.materials[1].bankSource, "cached")
    local bagsOnly = Engine.BuildPlan(recipe, 1, lookup, { includeBank = false })
    assert_eq(bagsOnly.materials[1].owned, 1)
    assert_eq(bagsOnly.materials[1].missing, 1)
  end)

  it("survives a missing or broken lookup", function()
    local plan = Engine.BuildPlan(recipe, 1, nil)
    assert_eq(plan.materials[1].owned, 0)
    plan = Engine.BuildPlan(recipe, 1, function() return "garbage" end)
    assert_eq(plan.materials[1].owned, 0)
    assert_eq(plan.materials[1].missing, 2)
  end)
end)
