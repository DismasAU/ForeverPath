local H = require("harness")

describe("RecipeModel", function()
  local ns, RecipeModel
  before_each(function()
    ns = H.fresh()
    RecipeModel = ns.RecipeModel
  end)

  local function schematic(overrides)
    local s = {
      recipeID = 2963,
      name = "Bolt of Linen Cloth",
      icon = 132889,
      outputItemID = 2996,
      quantityMin = 1,
      quantityMax = 1,
      recipeType = 1,
      reagentSlotSchematics = {
        { reagentType = 1, quantityRequired = 2, required = true, slotIndex = 1, reagents = { { itemID = 2589 } } },
      },
    }
    -- `false` removes a field (pairs() cannot carry nil).
    for k, v in pairs(overrides or {}) do
      if v == false then s[k] = nil else s[k] = v end
    end
    return s
  end

  it("normalizes a basic schematic", function()
    local recipe, err = RecipeModel.FromSchematic(schematic(), { recipeID = 2963, learned = true }, {
      professionID = 197, professionName = "Tailoring", now = 123,
    })
    assert_nil(err)
    assert_eq(recipe.recipeID, 2963)
    assert_eq(recipe.name, "Bolt of Linen Cloth")
    assert_eq(recipe.outputItemID, 2996)
    assert_eq(recipe.quantityMin, 1)
    assert_eq(recipe.professionName, "Tailoring")
    assert_eq(recipe.scannedAt, 123)
    assert_eq(#recipe.reagents, 1)
    assert_eq(recipe.reagents[1].itemID, 2589)
    assert_eq(recipe.reagents[1].quantity, 2)
    assert_true(RecipeModel.Validate(recipe))
    assert_true(ns.Util.IsPlainData(recipe))
  end)

  it("keeps only required basic reagent slots", function()
    local s = schematic({
      reagentSlotSchematics = {
        { reagentType = 1, quantityRequired = 2, required = true, reagents = { { itemID = 10 } } },
        { reagentType = 0, quantityRequired = 1, required = false, reagents = { { itemID = 11 } } },
        { reagentType = 2, quantityRequired = 1, required = false, reagents = { { itemID = 12 } } },
        { reagentType = 1, quantityRequired = 1, required = false, reagents = { { itemID = 13 } } },
        { reagentType = 3, quantityRequired = 1, reagents = { { itemID = 14 } } },
        { reagentType = 1, quantityRequired = 1, reagents = {} },
        { reagentType = 1, quantityRequired = 0, reagents = { { itemID = 15 } } },
      },
    })
    local recipe = RecipeModel.FromSchematic(s, nil, { basicReagentType = 1 })
    assert_eq(#recipe.reagents, 1)
    assert_eq(recipe.reagents[1].itemID, 10)
  end)

  it("treats untyped slots as basic and records alternatives", function()
    local s = schematic({
      reagentSlotSchematics = {
        { quantityRequired = 3, reagents = { { itemID = 20 }, { itemID = 21 }, { itemID = 22 } } },
      },
    })
    local recipe = RecipeModel.FromSchematic(s)
    assert_eq(recipe.reagents[1].itemID, 20)
    assert_deep_eq(recipe.reagents[1].alternatives, { 21, 22 })
  end)

  it("normalizes multi-output quantities", function()
    local recipe = RecipeModel.FromSchematic(schematic({ quantityMin = 2, quantityMax = 4 }))
    assert_eq(recipe.quantityMin, 2)
    assert_eq(recipe.quantityMax, 4)
    recipe = RecipeModel.FromSchematic(schematic({ quantityMin = false, quantityMax = false }))
    assert_eq(recipe.quantityMin, 1)
    assert_eq(recipe.quantityMax, 1)
    recipe = RecipeModel.FromSchematic(schematic({ quantityMin = 5, quantityMax = 2 }))
    assert_eq(recipe.quantityMax, 5, "max below min is corrected")
  end)

  it("rejects schematics without an item output or id", function()
    local recipe, err = RecipeModel.FromSchematic(schematic({ outputItemID = false }))
    assert_nil(recipe)
    assert_match(err, "no item output")
    recipe, err = RecipeModel.FromSchematic(schematic({ recipeID = "2963" }))
    assert_nil(recipe)
    assert_match(err, "recipe id")
    recipe, err = RecipeModel.FromSchematic(nil)
    assert_nil(recipe)
    assert_match(err, "schematic")
    recipe, err = RecipeModel.FromSchematic("garbage")
    assert_nil(recipe)
  end)

  it("validates stored recipes", function()
    assert_false(RecipeModel.Validate(nil))
    assert_false(RecipeModel.Validate({ recipeID = 1 }))
    local ok, reason = RecipeModel.Validate({ recipeID = 1, outputItemID = 2, quantityMin = 1, reagents = { { itemID = "x", quantity = 1 } } })
    assert_false(ok)
    assert_match(reason, "reagent #1")
    assert_true(RecipeModel.Validate({ recipeID = 1, outputItemID = 2, quantityMin = 1, reagents = {} }))
  end)

  it("merges profession metadata from an older entry", function()
    local old = { recipeID = 1, name = "Old", professionID = 197, professionName = "Tailoring", scannedAt = 5, icon = 9 }
    local fresh = RecipeModel.Merge(old, { recipeID = 1, name = "Recipe 1", reagents = {} })
    assert_eq(fresh.professionID, 197)
    assert_eq(fresh.professionName, "Tailoring")
    assert_eq(fresh.scannedAt, 5)
    assert_eq(fresh.name, "Old")
    assert_eq(fresh.icon, 9)
    assert_eq(RecipeModel.Merge(nil, { recipeID = 2 }).recipeID, 2)
  end)
end)
