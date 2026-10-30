-- AtlasLoot Classic adapter: detection, on-demand module loading and walks
-- over a module's loot tables, shared by the item sources (dungeon and raid
-- drops) and the reputation provider (faction rewards).
--
-- A loaded module's data sits in AtlasLoot.ItemDB.Storage[moduleName]:
--   storage[key] = content, key a string other than "__atlaslootdata";
--   content.items = { group }, a group a boss or a reputation tier;
--   group[difficulty] = { { slot, itemID, ... } } for numeric difficulties.
-- Modules load on demand through AtlasLoot.Loader:LoadModule(name, callback,
-- silent), which returns true while loading (callback later) or "InCombat"
-- when it waits for combat to end.
local _, ns = ...

local Util = ns.Util

local AtlasLoot = {}
ns.AtlasLoot = AtlasLoot

function AtlasLoot.IsInstalled()
  local atlas = _G.AtlasLoot
  return type(atlas) == "table" and type(atlas.ItemDB) == "table" and type(atlas.ItemDB.Storage) == "table"
end

-- The loaded data of a module, or nil.
function AtlasLoot.Storage(moduleName)
  if not AtlasLoot.IsInstalled() then return nil end
  local storage = _G.AtlasLoot.ItemDB.Storage[moduleName]
  return type(storage) == "table" and storage or nil
end

-- Loads a module and calls onLoaded(storage) once its data is there (now
-- when it already is). Returns "ready" (onLoaded ran), "loading" (it runs
-- later) or "missing" (not installed, not loadable, or the loader failed:
-- onLoaded never runs, so callers never wait on it).
function AtlasLoot.Load(moduleName, onLoaded)
  if not AtlasLoot.IsInstalled() then return "missing" end
  local storage = AtlasLoot.Storage(moduleName)
  if storage then
    onLoaded(storage)
    return "ready"
  end
  local loader = _G.AtlasLoot.Loader
  local result = type(loader) == "table" and Util.SafeCall(loader.LoadModule, loader, moduleName, function()
    local loaded = AtlasLoot.Storage(moduleName)
    if loaded then onLoaded(loaded) end
  end, true) or nil
  if result == true or result == "InCombat" then return "loading" end
  -- The loader answered at once: the module is either there now or not at all.
  storage = AtlasLoot.Storage(moduleName)
  if storage then
    onLoaded(storage)
    return "ready"
  end
  return "missing"
end

-- Iterator over a module's content tables: for key, content in AtlasLoot.Contents(storage).
function AtlasLoot.Contents(storage)
  local key
  return function()
    repeat
      local content
      key, content = next(storage, key)
      if type(key) == "string" and key ~= "__atlaslootdata" and type(content) == "table" and type(content.items) == "table" then
        return key, content
      end
    until key == nil
    return nil
  end
end

-- A content table's display name (an instance, a faction).
function AtlasLoot.ContentName(content)
  local name = Util.SafeCall(content.GetName, content, true)
  if type(name) == "string" then return name end
  return type(content.name) == "string" and content.name or "?"
end

-- Item ids of one group (a boss, a reputation tier) across its difficulties.
function AtlasLoot.ItemIDs(group)
  local out = {}
  if type(group) ~= "table" then return out end
  for difficulty, entries in pairs(group) do
    if type(difficulty) == "number" and type(entries) == "table" then
      for _, entry in ipairs(entries) do
        local itemID = type(entry) == "table" and entry[2] or nil
        if type(itemID) == "number" and itemID > 0 then out[#out + 1] = itemID end
      end
    end
  end
  return out
end
