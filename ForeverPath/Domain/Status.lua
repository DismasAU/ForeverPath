-- Evaluation statuses. These are deliberately distinct so the UI never has to
-- guess why a goal cannot be planned.
local _, ns = ...

local Status = {
  OK = "OK",
  UNSUPPORTED_GOAL = "UNSUPPORTED_GOAL",         -- goal type not implemented yet
  ITEM_INVALID = "ITEM_INVALID",                 -- item ID does not exist on this client
  ITEM_UNAVAILABLE = "ITEM_UNAVAILABLE",         -- server returned no data for the item
  PROVIDER_UNAVAILABLE = "PROVIDER_UNAVAILABLE", -- required API missing on this client
  RECIPES_NOT_SCANNED = "RECIPES_NOT_SCANNED",   -- no profession data captured yet
  RECIPE_NOT_FOUND = "RECIPE_NOT_FOUND",         -- scanned data has no recipe for the item
  RECIPE_NOT_LEARNED = "RECIPE_NOT_LEARNED",     -- a recipe exists, this character lacks it
  RECIPE_DATA_INVALID = "RECIPE_DATA_INVALID",   -- cached recipe failed validation
}
ns.Status = Status

-- Short labels for status indicators. Longer explanations come from the Planner.
ns.StatusLabel = {
  [Status.OK] = "Ready",
  [Status.UNSUPPORTED_GOAL] = "Unsupported goal",
  [Status.ITEM_INVALID] = "Invalid item",
  [Status.ITEM_UNAVAILABLE] = "Item data unavailable",
  [Status.PROVIDER_UNAVAILABLE] = "API unavailable",
  [Status.RECIPES_NOT_SCANNED] = "Recipes not scanned",
  [Status.RECIPE_NOT_FOUND] = "No known recipe",
  [Status.RECIPE_NOT_LEARNED] = "Recipe not learned",
  [Status.RECIPE_DATA_INVALID] = "Recipe data invalid",
}

-- Colors as hex strings for chat / font colouring.
ns.StatusColor = {
  [Status.OK] = "|cff40ff40",
  [Status.RECIPE_NOT_LEARNED] = "|cffffcc00",
  [Status.RECIPES_NOT_SCANNED] = "|cffffcc00",
}

function ns.ColorStatus(status, text)
  local color = ns.StatusColor[status] or "|cffff6060"
  return color .. tostring(text) .. "|r"
end
