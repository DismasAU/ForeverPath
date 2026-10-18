-- Quest catalogue: curated facts about Forever quests the client cannot
-- tell an addon ahead of time - who gives each quest and where, who takes
-- it back, and the items it asks for. Read through
-- Providers/QuestFactsProvider.lua, which overlays what the account has
-- learned at quest windows on top of these rows.
--
-- [questID] = {
--   giver  = { name, mapID, x, y, zone },   -- x, y are 0-1 fractions of the uiMapID map
--   turnin = { name, mapID, x, y, zone },
--   items  = { { itemID = n, name = "...", count = n, source = "where it comes from" } },
--   note   = "...",                          -- free text shown with the step (optional)
-- }
--
-- Sources (checked 2026-10-18, Forever beta build 1.60.1.70450):
--   Attune (AttuneClassQuests.lua, Forever class chains): quest ids, giver
--     pins and turn-in notes for the shaman "Call of Air" chain, both factions.
--   Wowhead Forever quest pages (quest=79360 ... quest=96016): objectives,
--     required and provided items with ids, series order.
--   expcarry.com "The Tempest's Weapons" guide, warcraft.wiki.gg NPC pages:
--     NPC positions and where the Twisted Totems drop.
-- Positions are map percent / 100 on the zone's uiMapID (Orgrimmar 1454,
-- Thunder Bluff 1456, Thousand Needles 1441, Alterac Mountains 1416,
-- Ironforge 1455, Arathi Highlands 1417). Not yet verified on the beta: a
-- quest window opened in game overrides a row's position for the account.
local _, ns = ...

ns.Data = ns.Data or {}

local PRATE = { name = "Prate Cloudseer", mapID = 1441, x = 0.536, y = 0.428, zone = "Thousand Needles" }
local RAU = { name = "Rau Cliffrunner", mapID = 1441, x = 0.460, y = 0.516, zone = "Thousand Needles" }
local BATHRAH = { name = "Bath'rah the Windwatcher", mapID = 1416, x = 0.804, y = 0.668, zone = "Alterac Mountains" }
local VEYRIC = { name = "Veyric Thunderhame", mapID = 1417, x = 0.598, y = 0.276, zone = "Arathi Highlands" }
local SEARN = { name = "Searn Firewarder", mapID = 1454, x = 0.378, y = 0.374, zone = "Orgrimmar" }
local XANIS = { name = "Xanis Flameweaver", mapID = 1456, x = 0.252, y = 0.210, zone = "Thunder Bluff" }
local ELDRUN = { name = "Eldrun Stormbreaker", mapID = 1455, x = 0.474, y = 0.136, zone = "Ironforge" }

local TATTERED_NOTE = {
  { itemID = 274463, name = "Tattered Note", count = 1, source = "Charlga Razorflank, Razorfen Kraul" },
}
local TWISTED_TOTEMS = {
  { itemID = 274044, name = "Twisted Fire Totem", count = 5, source = "Stonevault troggs and Dustbelcher ogres, Agmond's End, Badlands" },
  { itemID = 274045, name = "Twisted Earth Totem", count = 5, source = "Lost Ones, Fallow Sanctuary, Swamp of Sorrows" },
  { itemID = 274047, name = "Twisted Air Totem", count = 5, source = "Maraudine centaurs, Valley of Spears, Desolace" },
  { itemID = 274046, name = "Twisted Water Totem", count = 5, source = "Mirefin murlocs, Dreadmurk Shore, Dustwallow Marsh" },
}
local EYE_OF_THE_TEMPEST = {
  { itemID = 212792, name = "Eye of the Tempest", count = 1, source = "the quilboar ritual at the steam pools west of Freewind Post, Thousand Needles (use the Corrupted Totems, elite waves)" },
}

ns.Data.QuestCatalogue = {
  -- Shaman: Call of Air (Horde), level 30 - ends in The Tempest's Weapons
  -- (Rage of the Storm / Lightning's Grasp / Tidebringer's Claw + Rune of the Storm).
  [1531] = { giver = SEARN, turnin = PRATE, items = {} },                      -- Call of Air (Orgrimmar)
  [1532] = { giver = XANIS, turnin = PRATE, items = {} },                      -- Call of Air (Thunder Bluff)
  [79360] = { giver = PRATE, turnin = RAU, items = TATTERED_NOTE },            -- Elemental Aid
  [79364] = { giver = RAU, turnin = PRATE, items = {} },                       -- Eyes on the Sky
  [79361] = { giver = PRATE, turnin = PRATE, items = TWISTED_TOTEMS },         -- Storm, Earth, and Fire
  [79366] = { giver = PRATE, turnin = RAU, items = EYE_OF_THE_TEMPEST },       -- Heed My Call
  [79442] = { giver = RAU, turnin = BATHRAH, items = {} },                     -- The Tempest's Weapons
  -- Shaman: Call of Air (Alliance), level 30 - ends in The Tempest's Weapons
  -- (same weapons + Elementalist's Guard).
  [94789] = { giver = ELDRUN, turnin = VEYRIC, items = {} },                   -- Call of Air
  [96264] = { giver = VEYRIC, turnin = VEYRIC, items = TATTERED_NOTE },        -- Elemental Aid
  [79358] = { giver = VEYRIC, turnin = VEYRIC, items = TWISTED_TOTEMS },       -- Storm, Earth, and Fire
  [96135] = { giver = VEYRIC, turnin = VEYRIC, items = EYE_OF_THE_TEMPEST },   -- Heed My Call
  [96016] = { giver = VEYRIC, turnin = BATHRAH, items = {} },                  -- The Tempest's Weapons
}
