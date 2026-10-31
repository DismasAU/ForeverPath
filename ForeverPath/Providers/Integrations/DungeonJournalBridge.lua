-- ForeverDungeonJournal adapter: detection and the journal's tables, shared
-- by the item sources (boss loot, quest rewards), the quest index and item
-- name search. The one place that names the journal's global.
--
-- The journal keeps its data in a global namespace:
--   DB[dungeonName] = { bosses = { { name, npcID, trash, loot = { { itemID, name, slot, quality, mobName } } } },
--                       quests = { { id, name, faction, rewardChoice, rewardItems = { { itemID, name, quality } } } } }
--   SHARED_BY_BOSS[dungeonName][bossName] = { { itemID, name, slot, quality } }
local _, ns = ...

local DungeonJournalBridge = {}
ns.DungeonJournalBridge = DungeonJournalBridge

DungeonJournalBridge.GLOBAL = "ForeverDungeonJournal_NS"

-- The journal's namespace, or nil when it is not installed.
function DungeonJournalBridge.Get()
  local fdj = _G[DungeonJournalBridge.GLOBAL]
  if type(fdj) == "table" and type(fdj.DB) == "table" then return fdj end
  return nil
end

function DungeonJournalBridge.IsAvailable()
  return DungeonJournalBridge.Get() ~= nil
end

-- Every item name the journal carries (boss and trash loot, shared loot,
-- quest rewards), for name search; built once per session.
function DungeonJournalBridge.ItemNames()
  if DungeonJournalBridge.names then return DungeonJournalBridge.names end
  local names = {}
  local fdj = DungeonJournalBridge.Get()
  local function take(entry)
    if type(entry) == "table" and tonumber(entry[1]) and type(entry[2]) == "string" and entry[2] ~= "" then
      names[tonumber(entry[1])] = entry[2]
    end
  end
  for dungeonName, dungeon in pairs(fdj and fdj.DB or {}) do
    if type(dungeonName) == "string" and type(dungeon) == "table" then
      for _, boss in ipairs(type(dungeon.bosses) == "table" and dungeon.bosses or {}) do
        for _, entry in ipairs(type(boss) == "table" and type(boss.loot) == "table" and boss.loot or {}) do take(entry) end
      end
      local shared = type(fdj.SHARED_BY_BOSS) == "table" and fdj.SHARED_BY_BOSS[dungeonName] or nil
      for _, list in pairs(type(shared) == "table" and shared or {}) do
        for _, entry in ipairs(type(list) == "table" and list or {}) do take(entry) end
      end
      for _, quest in ipairs(type(dungeon.quests) == "table" and dungeon.quests or {}) do
        for _, reward in ipairs(type(quest) == "table" and type(quest.rewardItems) == "table" and quest.rewardItems or {}) do take(reward) end
      end
    end
  end
  DungeonJournalBridge.names = names
  return names
end
