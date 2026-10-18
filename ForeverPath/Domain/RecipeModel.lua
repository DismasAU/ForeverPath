-- Normalized recipe model.
--
-- Raw C_TradeSkillUI schematics are converted once into this shape so the
-- engines never touch API tables:
--   {
--     recipeID = 2963, name = "Bolt of Linen Cloth", icon = 132889,
--     outputItemID = 2996, quantityMin = 1, quantityMax = 1, recipeType = 1,
--     professionID = 197, professionName = "Tailoring",
--     reagents = { { itemID = 2589, quantity = 2, slotIndex = 1, alternatives = nil } },
--     source = "C_TradeSkillUI", scannedAt = 1792147990,
--   }
-- Only required "basic" reagent slots are kept. Optional, finishing and
-- modifying reagents are not needed to craft and are left out for now.
local _, ns = ...

local RecipeModel = {}
ns.RecipeModel = RecipeModel

local function isPositiveInt(v)
  return type(v) == "number" and v > 0 and v == math.floor(v)
end

RecipeModel.RECIPE_TYPE_ENCHANT = 3 -- Enum.TradeskillRecipeType.Enchant

-- Converts a CraftingRecipeSchematic (plus optional TradeSkillRecipeInfo) into
-- the normalized model. Returns nil, reason when the schematic describes
-- neither an item-producing recipe nor an enchant. A recipe without an item
-- output is an enchant when the schematic says so (recipeType) or when
-- opts.isEnchant(recipeID) does (the catalogue); it gets enchant = true and
-- a yield of one cast.
function RecipeModel.FromSchematic(schematic, recipeInfo, opts)
  opts = opts or {}
  if type(schematic) ~= "table" then
    return nil, "schematic missing"
  end
  local recipeID = schematic.recipeID or (recipeInfo and recipeInfo.recipeID)
  if not isPositiveInt(recipeID) then
    return nil, "recipe id missing"
  end
  local outputItemID = schematic.outputItemID
  local enchant = nil
  if not isPositiveInt(outputItemID) then
    local byCatalogue = type(opts.isEnchant) == "function" and opts.isEnchant(recipeID) == true
    if schematic.recipeType == RecipeModel.RECIPE_TYPE_ENCHANT or byCatalogue then
      enchant = true
      outputItemID = nil
    else
      return nil, "recipe has no item output"
    end
  end

  local basicType = opts.basicReagentType or 1
  local reagents = {}
  local slots = schematic.reagentSlotSchematics
  if type(slots) == "table" then
    for index, slot in ipairs(slots) do
      if type(slot) == "table" then
        local reagentType = slot.reagentType
        local isBasic = (reagentType == nil) or (reagentType == basicType)
        local required = slot.required
        if required == nil then
          required = isBasic
        end
        local candidates = slot.reagents
        if isBasic and required and type(candidates) == "table" and #candidates > 0 then
          local primary = candidates[1]
          local quantity = slot.quantityRequired
          if type(primary) == "table" and isPositiveInt(primary.itemID) and isPositiveInt(quantity) then
            local alternatives
            if #candidates > 1 then
              alternatives = {}
              for j = 2, #candidates do
                local alt = candidates[j]
                if type(alt) == "table" and isPositiveInt(alt.itemID) then
                  alternatives[#alternatives + 1] = alt.itemID
                end
              end
              if #alternatives == 0 then
                alternatives = nil
              end
            end
            reagents[#reagents + 1] = {
              itemID = primary.itemID,
              quantity = quantity,
              slotIndex = slot.slotIndex or index,
              alternatives = alternatives,
            }
          end
        end
      end
    end
  end

  local quantityMin = schematic.quantityMin
  if not isPositiveInt(quantityMin) or enchant then
    quantityMin = 1
  end
  local quantityMax = schematic.quantityMax
  if not isPositiveInt(quantityMax) or quantityMax < quantityMin or enchant then
    quantityMax = quantityMin
  end

  return {
    recipeID = recipeID,
    name = schematic.name or (recipeInfo and recipeInfo.name) or ("Recipe " .. recipeID),
    icon = schematic.icon or (recipeInfo and recipeInfo.icon) or nil,
    outputItemID = outputItemID,
    enchant = enchant,
    quantityMin = quantityMin,
    quantityMax = quantityMax,
    recipeType = schematic.recipeType,
    professionID = opts.professionID,
    professionName = opts.professionName,
    reagents = reagents,
    source = opts.source or "C_TradeSkillUI",
    scannedAt = opts.now,
  }
end

-- Validates a recipe table (typically one read back from SavedVariables).
function RecipeModel.Validate(recipe)
  if type(recipe) ~= "table" then
    return false, "recipe is not a table"
  end
  if not isPositiveInt(recipe.recipeID) then
    return false, "invalid recipeID"
  end
  if recipe.enchant == true then
    if recipe.outputItemID ~= nil then
      return false, "an enchant has no outputItemID"
    end
  elseif not isPositiveInt(recipe.outputItemID) then
    return false, "invalid outputItemID"
  end
  if not isPositiveInt(recipe.quantityMin) then
    return false, "invalid quantityMin"
  end
  if type(recipe.reagents) ~= "table" then
    return false, "reagents missing"
  end
  for i, reagent in ipairs(recipe.reagents) do
    if type(reagent) ~= "table" or not isPositiveInt(reagent.itemID) or not isPositiveInt(reagent.quantity) then
      return false, "invalid reagent #" .. i
    end
  end
  return true
end

-- Keeps profession metadata from an older entry when a refreshed schematic
-- does not carry it (live schematics have no profession fields).
function RecipeModel.Merge(existing, fresh)
  if type(existing) ~= "table" then
    return fresh
  end
  fresh.professionID = fresh.professionID or existing.professionID
  fresh.professionName = fresh.professionName or existing.professionName
  fresh.scannedAt = fresh.scannedAt or existing.scannedAt
  if fresh.name == nil or fresh.name:match("^Recipe %d+$") then
    fresh.name = existing.name or fresh.name
  end
  fresh.icon = fresh.icon or existing.icon
  fresh.enchant = fresh.enchant or existing.enchant
  return fresh
end
