-- The Planner's composition root: its injected deps wired to the addon's
-- own providers and catalogue, installed through Planner.SetDefaultDeps.
-- The Planner itself (Domain/Planner*.lua) only ever sees this table, so
-- tests hand it doubles instead.
local _, ns = ...

ns.Planner.SetDefaultDeps(function()
  return {
    item = ns.ItemProvider,
    profession = ns.ProfessionProvider,
    inventory = ns.InventoryProvider,
    catalogue = ns.Recipes,
    characters = ns.CharacterProvider,
    sources = ns.SourceProvider,
    price = ns.PriceProvider,
    attune = ns.AttuneBridge,
    quest = ns.QuestProvider,
    reputation = ns.ReputationProvider,
    settings = {
      includeBank = ns.Database.Setting("includeBank"),
      includeAlts = ns.Database.Setting("includeAlts"),
    },
  }
end)
