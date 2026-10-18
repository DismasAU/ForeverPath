-- Crafting calculations. Pure Lua, no API access.
--
-- Version 0.1 handles direct recipe requirements only. The function shapes are
-- chosen so recursive resolution (intermediate crafts), allocation across
-- goals and cost comparison can be layered on top without changing callers:
-- a plan is just data describing crafts, materials and where they come from.
local _, ns = ...

local RecipeModel = ns.RecipeModel

local CraftingEngine = {}
ns.CraftingEngine = CraftingEngine

local function ceilDiv(a, b)
  return math.floor((a + b - 1) / b)
end

-- Number of crafts needed to obtain `quantityWanted` items when each craft
-- yields at least `outputPerCraft`. Planning uses the guaranteed minimum so a
-- recipe with a random 2-4 yield is never under-provisioned.
function CraftingEngine.CraftsNeeded(quantityWanted, outputPerCraft)
  if type(quantityWanted) ~= "number" or quantityWanted <= 0 then
    return 0
  end
  if type(outputPerCraft) ~= "number" or outputPerCraft < 1 then
    outputPerCraft = 1
  end
  return ceilDiv(quantityWanted, outputPerCraft)
end

-- Builds the raw requirement list for crafting `quantityWanted` of a recipe's output.
-- Returns nil, reason for invalid input.
function CraftingEngine.ComputeRequirements(recipe, quantityWanted)
  local ok, err = RecipeModel.Validate(recipe)
  if not ok then
    return nil, err
  end
  if type(quantityWanted) ~= "number" or quantityWanted <= 0 or quantityWanted ~= math.floor(quantityWanted) then
    return nil, "quantity must be a positive integer"
  end
  local crafts = CraftingEngine.CraftsNeeded(quantityWanted, recipe.quantityMin)
  local materials = {}
  local byItem = {}
  for _, reagent in ipairs(recipe.reagents) do
    local entry = byItem[reagent.itemID]
    if entry then
      -- The same item in two slots is unusual but legal; merge it.
      entry.perCraft = entry.perCraft + reagent.quantity
      entry.required = entry.perCraft * crafts
    else
      entry = {
        itemID = reagent.itemID,
        perCraft = reagent.quantity,
        required = reagent.quantity * crafts,
        alternatives = reagent.alternatives,
      }
      byItem[reagent.itemID] = entry
      materials[#materials + 1] = entry
    end
  end
  return {
    recipeID = recipe.recipeID,
    outputItemID = recipe.outputItemID,
    quantityWanted = quantityWanted,
    craftsNeeded = crafts,
    outputPerCraft = recipe.quantityMin,
    outputPerCraftMax = recipe.quantityMax,
    expectedOutput = crafts * recipe.quantityMin,
    materials = materials,
  }
end

-- Normalizes whatever the inventory lookup returns into { bags, bank, alts, total, bankSource }.
local function normalizeCounts(counts, includeBank, includeAlts)
  if type(counts) == "number" then
    return { bags = counts, bank = nil, total = counts, bankSource = "none" }
  end
  if type(counts) ~= "table" then
    return { bags = 0, bank = nil, total = 0, bankSource = "none" }
  end
  local bags = tonumber(counts.bags) or 0
  local bank = tonumber(counts.bank)
  local alts = tonumber(counts.alts)
  local total = bags
  if includeBank ~= false and bank then
    total = total + bank
  end
  if includeAlts == true and alts then
    total = total + alts
  end
  return { bags = bags, bank = bank, alts = alts, total = total, bankSource = counts.bankSource or (bank and "unknown" or "none"),
    altSources = counts.altSources, reserved = tonumber(counts.reserved) or 0 }
end

-- Combines requirements with inventory counts.
-- lookup(itemID) -> number or { bags = n, bank = m|nil, bankSource = "live"|"cached"|"client"|"none" }
-- Missing = max(0, required - owned).
function CraftingEngine.ApplyInventory(requirements, lookup, opts)
  opts = opts or {}
  local includeBank = opts.includeBank
  local includeAlts = opts.includeAlts
  local plan = {
    recipeID = requirements.recipeID,
    outputItemID = requirements.outputItemID,
    quantityWanted = requirements.quantityWanted,
    craftsNeeded = requirements.craftsNeeded,
    outputPerCraft = requirements.outputPerCraft,
    outputPerCraftMax = requirements.outputPerCraftMax,
    expectedOutput = requirements.expectedOutput,
    materials = {},
    totals = { required = 0, owned = 0, missing = 0, materialsMissing = 0 },
  }
  for _, material in ipairs(requirements.materials) do
    local counts = normalizeCounts(lookup and lookup(material.itemID) or 0, includeBank, includeAlts)
    local missing = material.required - counts.total
    if missing < 0 then
      missing = 0
    end
    plan.materials[#plan.materials + 1] = {
      itemID = material.itemID,
      perCraft = material.perCraft,
      required = material.required,
      owned = counts.total,
      ownedBags = counts.bags,
      ownedBank = counts.bank,
      ownedAlts = counts.alts,
      altSources = counts.altSources,
      bankSource = counts.bankSource,
      reserved = counts.reserved,
      missing = missing,
      alternatives = material.alternatives,
    }
    plan.totals.required = plan.totals.required + material.required
    plan.totals.owned = plan.totals.owned + math.min(counts.total, material.required)
    plan.totals.missing = plan.totals.missing + missing
    if missing > 0 then
      plan.totals.materialsMissing = plan.totals.materialsMissing + 1
    end
  end
  plan.isComplete = plan.totals.missing == 0
  return plan
end

-- Convenience: requirements + inventory in one call.
function CraftingEngine.BuildPlan(recipe, quantityWanted, lookup, opts)
  local requirements, err = CraftingEngine.ComputeRequirements(recipe, quantityWanted)
  if not requirements then
    return nil, err
  end
  return CraftingEngine.ApplyInventory(requirements, lookup, opts)
end
