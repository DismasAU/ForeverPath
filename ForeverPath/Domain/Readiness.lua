-- Readiness: whether the Planner could plan a goal, and if not why. Each value
-- is distinct so the UI never has to guess. (A goal's own lifecycle is
-- goal.status; a provider's diagnostics line is Provider.StatusLine.)
local _, ns = ...

--   OK
--   UNSUPPORTED_GOAL      goal type this version does not know
--   ITEM_INVALID          item ID does not exist on this client
--   ITEM_UNAVAILABLE      server returned no data for the item
--   PROVIDER_UNAVAILABLE  required API missing on this client
--   RECIPES_NOT_SCANNED   no profession data captured yet
--   RECIPE_NOT_FOUND      scanned data has no recipe for the item
--   RECIPE_NOT_LEARNED    a recipe exists, this character lacks it
--   RECIPE_DATA_INVALID   cached recipe failed validation
--   PROFESSION_MISSING    a skill goal for a profession this character lacks
-- A misspelt name raises (Util.StrictNames) instead of reading as nil.
local Readiness = ns.Util.StrictNames({
  "OK", "UNSUPPORTED_GOAL", "ITEM_INVALID", "ITEM_UNAVAILABLE", "PROVIDER_UNAVAILABLE",
  "RECIPES_NOT_SCANNED", "RECIPE_NOT_FOUND", "RECIPE_NOT_LEARNED", "RECIPE_DATA_INVALID",
  "PROFESSION_MISSING",
}, "readiness")
ns.Readiness = Readiness

-- Short labels for readiness indicators. Longer explanations come from the Planner.
local LABELS = {
  [Readiness.OK] = "Ready",
  [Readiness.UNSUPPORTED_GOAL] = "Unsupported goal",
  [Readiness.ITEM_INVALID] = "Invalid item",
  [Readiness.ITEM_UNAVAILABLE] = "Item data unavailable",
  [Readiness.PROVIDER_UNAVAILABLE] = "API unavailable",
  [Readiness.RECIPES_NOT_SCANNED] = "Recipes not scanned",
  [Readiness.RECIPE_NOT_FOUND] = "No known recipe",
  [Readiness.RECIPE_NOT_LEARNED] = "Recipe not learned",
  [Readiness.RECIPE_DATA_INVALID] = "Recipe data invalid",
  [Readiness.PROFESSION_MISSING] = "Profession not known",
}

-- The short label for a readiness value, or nil for an unknown one.
function Readiness.Label(readiness)
  return LABELS[readiness]
end
