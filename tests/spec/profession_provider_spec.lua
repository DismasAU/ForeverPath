local H = require("harness")
local Mock = H.Mock

describe("ProfessionProvider", function()
  local ns, Prof
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    Prof = ns.ProfessionProvider
  end)

  local function seedTailoring()
    Mock.AddItem(2589, { name = "Linen Cloth" })
    Mock.AddItem(2996, { name = "Bolt of Linen Cloth" })
    Mock.AddItem(4238, { name = "Linen Bag", quality = 1 })
    Mock.AddRecipe({ recipeID = 2963, name = "Bolt of Linen Cloth", outputItemID = 2996, reagents = { { itemID = 2589, quantity = 2 } } })
    Mock.AddRecipe({ recipeID = 3755, name = "Linen Bag", outputItemID = 4238, learned = false,
      reagents = { { itemID = 2996, quantity = 3 }, { itemID = 2320, quantity = 3 } } })
    -- An enchant has no item output: recorded by spell id, never indexed by item.
    Mock.AddRecipe({ recipeID = 7420, name = "Enchant Chest - Minor Health", outputItemID = nil, recipeType = 3, learned = false,
      reagents = { { itemID = 10940, quantity = 1 } } })
    local profession = { professionID = 197, name = "Tailoring", skillLevel = 75, maxSkillLevel = 150, recipeIDs = { 2963, 3755, 7420 } }
    Mock.OpenProfession(profession)
    return profession
  end

  local function scan()
    Mock.FireEvent("TRADE_SKILL_SHOW")
    Mock.FireEvent("TRADE_SKILL_LIST_UPDATE")
    Mock.RunTimers()
  end

  it("is unavailable without C_TradeSkillUI", function()
    ns = H.fresh({ setup = function() _G.C_TradeSkillUI = nil end })
    H.login(ns)
    assert_false(ns.ProfessionProvider.IsAvailable())
    assert_false(ns.ProfessionProvider.HasScanData())
    local ok, reason = ns.ProfessionProvider.ScanOpenProfession()
    assert_false(ok)
    assert_eq(reason, "unavailable")
    assert_false(ns.ProfessionProvider.RequestScan())
    assert_output("not available")
  end)

  it("records recipes from an open profession window", function()
    seedTailoring()
    local updates = {}
    ns.Events.On("FP_RECIPES_UPDATED", function(id) updates[#updates + 1] = id end)
    assert_false(Prof.HasScanData())
    scan()
    assert_true(Prof.HasScanData())
    assert_deep_eq(updates, { 197 })
    assert_not_nil(ns.db.recipes[2963])
    assert_not_nil(ns.db.recipes[3755])
    assert_true(ns.db.recipes[7420].enchant, "enchant recorded with the enchant flag")
    assert_nil(ns.db.recipes[7420].outputItemID)
    assert_eq(ns.db.recipes[7420].quantityMin, 1)
    assert_eq(ns.chardb.knownRecipes[7420], false)
    local indexed = false
    for _, ids in pairs(ns.db.itemRecipes) do if ids[7420] then indexed = true end end
    assert_false(indexed, "an enchant produces no item")
    assert_eq(ns.db.recipes[2963].professionName, "Tailoring")
    assert_eq(ns.db.recipes[2963].reagents[1].quantity, 2)
    assert_true(ns.db.itemRecipes[2996][2963])
    assert_eq(ns.chardb.knownRecipes[2963], true)
    assert_eq(ns.chardb.knownRecipes[3755], false)
    local summary = ns.chardb.professions[197]
    assert_eq(summary.name, "Tailoring")
    assert_eq(summary.recipeCount, 3)
    assert_eq(summary.learnedCount, 1)
    assert_eq(summary.skillLevel, 75)
    assert_output("Recorded Tailoring: 3 recipes %(1 enchants%) %(1 learned%)")
    assert_eq(#Prof.GetScannedProfessions(), 1)
    assert_true(ns.Util.IsPlainData(ns.db.recipes))
  end)

  it("finds recipes by output item with learned flags", function()
    seedTailoring()
    scan()
    local hits = Prof.FindRecipesForItem(2996)
    assert_eq(#hits, 1)
    assert_eq(hits[1].recipe.recipeID, 2963)
    assert_true(hits[1].learned)
    hits = Prof.FindRecipesForItem(4238)
    assert_false(hits[1].learned)
    assert_eq(#Prof.FindRecipesForItem(1), 0)
  end)

  it("processes large recipe lists in chunks", function()
    local ids = {}
    for i = 1, 150 do
      Mock.AddRecipe({ recipeID = 10000 + i, name = "R" .. i, outputItemID = 20000 + i, reagents = { { itemID = 1, quantity = 1 } } })
      ids[#ids + 1] = 10000 + i
    end
    Mock.OpenProfession({ professionID = 164, name = "Blacksmithing", recipeIDs = ids })
    Mock.FireEvent("TRADE_SKILL_LIST_UPDATE")
    Mock.RunTimers(1) -- only the debounce fires: first chunk processed synchronously
    assert_nil(ns.chardb.professions[164], "scan not finished yet")
    Mock.RunTimers()
    assert_eq(ns.chardb.professions[164].recipeCount, 150)
  end)

  it("ignores NPC, guild and linked profession views", function()
    seedTailoring()
    Mock.tradeskill.npc = true
    local ok, reason = Prof.ScanOpenProfession()
    assert_false(ok)
    assert_eq(reason, "npc crafting")
    Mock.tradeskill.npc = false
    Mock.tradeskill.linked = true
    ok, reason = Prof.ScanOpenProfession()
    assert_eq(reason, "linked profession")
    Mock.tradeskill.linked = false
    Mock.CloseProfession()
    ok, reason = Prof.ScanOpenProfession()
    assert_eq(reason, "no profession open")
    assert_false(Prof.HasScanData())
  end)

  it("keys professions by their parent profession", function()
    Mock.AddRecipe({ recipeID = 1, name = "X", outputItemID = 2, reagents = { { itemID = 3, quantity = 1 } } })
    Mock.OpenProfession({ professionID = 2399, parentProfessionID = 197, name = "Classic Tailoring", parentProfessionName = "Tailoring", recipeIDs = { 1 } })
    scan()
    assert_not_nil(ns.chardb.professions[197])
    assert_eq(ns.chardb.professions[197].name, "Tailoring")
    assert_eq(ns.chardb.professions[197].childProfessionID, 2399)
  end)

  it("refreshes recipes live only when the API has the data", function()
    seedTailoring()
    scan()
    Mock.tradeskill.schematicRequiresOpen = true
    Mock.CloseProfession()
    local recipe, live = Prof.GetRecipe(2963, true)
    assert_false(live)
    assert_eq(#recipe.reagents, 1, "cached reagents kept when the live schematic is empty")
    Mock.OpenProfession({ professionID = 197, name = "Tailoring", recipeIDs = { 2963 } })
    Mock.tradeskill.recipes[2963].schematic.reagentSlotSchematics[1].quantityRequired = 3
    recipe, live = Prof.GetRecipe(2963, true)
    assert_true(live)
    assert_eq(recipe.reagents[1].quantity, 3)
    assert_eq(recipe.professionName, "Tailoring", "metadata merged from the cached entry")
    assert_eq(ns.db.recipes[2963].reagents[1].quantity, 3)
  end)

  it("updates learned flags on rescans and NEW_RECIPE_LEARNED", function()
    seedTailoring()
    scan()
    assert_eq(ns.chardb.knownRecipes[3755], false)
    Mock.FireEvent("NEW_RECIPE_LEARNED", 3755)
    assert_eq(ns.chardb.knownRecipes[3755], true)
    Mock.tradeskill.recipes[3755].info.learned = false
    scan()
    assert_eq(ns.chardb.knownRecipes[3755], false)
    assert_eq(ns.chardb.professions[197].recipeCount, 3)
  end)

  it("opens unrecorded professions for /fp scan and closes afterwards", function()
    local tailoring = seedTailoring()
    Mock.CloseProfession()
    Mock.AddRecipe({ recipeID = 2, name = "Copper Bar", outputItemID = 2840, reagents = { { itemID = 2770, quantity = 1 } } })
    local mining = { professionID = 186, name = "Mining", recipeIDs = { 2 } }
    Mock.tradeskill.openable[197] = tailoring
    Mock.tradeskill.openable[186] = mining
    Mock.SetProfessions({
      { slot = 1, name = "Tailoring", skillLevel = 75, maxSkillLevel = 150, skillLine = 197 },
      { slot = 2, name = "Mining", skillLevel = 10, maxSkillLevel = 75, skillLine = 186 },
      { slot = 5, name = "Cooking", skillLevel = 1, maxSkillLevel = 75, skillLine = 185 },
    })
    assert_eq(#Prof.GetCharacterProfessions(), 3)
    assert_true(Prof.RequestScan(false))
    Mock.RunTimers()
    assert_deep_eq(Mock.tradeskill.openCalls, { 197, 186, 185 })
    assert_not_nil(ns.chardb.professions[197])
    assert_not_nil(ns.chardb.professions[186])
    assert_output("Could not open Cooking")
    assert_eq(Mock.tradeskill.closeCalls, 1)
    assert_nil(Mock.tradeskill.open)
    -- Second run: everything recorded.
    Mock.tradeskill.openCalls = {}
    Mock.tradeskill.openable[185] = { professionID = 185, name = "Cooking", recipeIDs = {} }
    Prof.RequestScan(false)
    Mock.RunTimers()
    assert_deep_eq(Mock.tradeskill.openCalls, { 185 }, "only the unrecorded profession is opened")
  end)

  it("defers automatic scanning while in combat", function()
    local tailoring = seedTailoring()
    Mock.CloseProfession()
    Mock.tradeskill.openable[197] = tailoring
    Mock.SetProfessions({ { slot = 1, name = "Tailoring", skillLine = 197 } })
    Mock.combat = true
    Prof.RequestScan(false)
    Mock.RunTimers()
    assert_eq(#Mock.tradeskill.openCalls, 0)
    Mock.combat = false
    Mock.FireEvent("PLAYER_REGEN_ENABLED")
    Mock.RunTimers()
    assert_deep_eq(Mock.tradeskill.openCalls, { 197 })
  end)
end)
