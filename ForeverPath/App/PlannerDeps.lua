-- The Planner's composition root: its injected deps wired to the addon's
-- own providers and catalogue. The Planner itself (Domain/Planner*.lua)
-- only ever sees this table, so tests hand it doubles instead.
local _, ns = ...

function ns.Planner.DefaultDeps()
  return {
    item = ns.ItemProvider,
    profession = ns.ProfessionProvider,
    inventory = ns.InventoryProvider,
    catalogue = ns.Data.Recipes,
    characters = ns.CharacterProvider,
    sources = ns.SourceProvider,
    price = ns.PriceProvider,
    attune = ns.AttuneProvider,
    quest = ns.QuestProvider,
    reputation = ns.ReputationProvider,
    settings = ns.db and ns.db.settings or {},
  }
end
