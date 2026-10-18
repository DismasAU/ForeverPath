-- Quest catalogue: curated facts about Forever quests the client cannot
-- tell an addon ahead of time - who gives each quest and where, who takes
-- it back, and the items it asks for. Read through
-- Providers/QuestFactsProvider.lua, which overlays what the account has
-- learned at quest windows on top of these rows.
--
-- [questID] = {
--   giver  = { name, mapID, x, y, zone },   -- x, y are 0-1 fractions of the uiMapID map
--   turnin = { name, mapID, x, y, zone },
--   items  = { { itemID = n, name = "...", count = n } },  -- what the quest asks the player to bring
--   note   = "...",                          -- free text shown with the step (optional)
-- }
local _, ns = ...

ns.Data = ns.Data or {}

ns.Data.QuestCatalogue = {
}
