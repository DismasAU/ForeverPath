-- Item resolution: parses player input and wraps C_Item with async loading.
--
-- Item data on modern clients is loaded lazily from the server. GetItemInfo
-- returns nil until the item is cached; RequestLoadItemDataByID triggers the
-- fetch and ITEM_DATA_LOAD_RESULT reports completion. Names seen once are kept
-- in ForeverPathDB.itemNames so goals stay readable and name search works
-- without a full item database (which the client does not expose).
local _, ns = ...

local Compat = ns.Compat
local Util = ns.Util
local Log = ns.Log
local Events = ns.Events

local ItemProvider = {
  pending = {},   -- itemID -> true while a load request is outstanding
  failed = {},    -- itemID -> true when the server reported no data this session
}
ns.ItemProvider = ItemProvider

-- Parses an item ID, an item link, "item:1234", or a free-text name.
-- Pure function. Returns nil for empty or invalid input.
function ItemProvider.ParseInput(text)
  if type(text) == "number" then
    if Util.IsPositiveInt(text) then
      return { kind = "id", itemID = text }
    end
    return nil
  end
  if type(text) ~= "string" then
    return nil
  end
  local s = Util.Trim(text)
  if s == "" then
    return nil
  end
  local linkID = s:match("|Hitem:(%d+)")
  if linkID then
    local name = s:match("|h%[(.-)%]|h")
    return { kind = "link", itemID = tonumber(linkID), name = name, link = s }
  end
  local prefixed = s:match("^[Ii][Tt][Ee][Mm]:(%d+)$")
  if prefixed then
    return { kind = "id", itemID = tonumber(prefixed) }
  end
  local id = Util.ParseInt(s)
  if id then
    if id > 0 then
      return { kind = "id", itemID = id }
    end
    return nil
  end
  return { kind = "name", name = s }
end

local function nameCache()
  return ns.db and ns.db.itemNames or nil
end

function ItemProvider.RememberName(itemID, name)
  local cache = nameCache()
  if cache and type(name) == "string" and name ~= "" then
    cache[itemID] = name
  end
end

-- A name seen on this client, else the catalogue's (the client's own item
-- table at extraction time), else nil.
function ItemProvider.GetCachedName(itemID)
  local cache = nameCache()
  local name = cache and cache[itemID] or nil
  if name then return name end
  local catalogue = ns.Data and ns.Data.Recipes
  return catalogue and catalogue.ItemName and catalogue.ItemName(itemID) or nil
end

-- true / false, or nil when the client cannot say.
function ItemProvider.Exists(itemID)
  if not Util.IsPositiveInt(itemID) then
    return false
  end
  if Compat.DoesItemExistByID then
    local ok, exists = pcall(Compat.DoesItemExistByID, itemID)
    if ok and exists ~= nil then
      return exists and true or false
    end
  end
  if Compat.GetItemInfoInstant then
    local ok, id = pcall(Compat.GetItemInfoInstant, itemID)
    if ok then
      return id ~= nil
    end
  end
  return nil
end

function ItemProvider.RequestLoad(itemID)
  if ItemProvider.pending[itemID] or ItemProvider.failed[itemID] then
    return false
  end
  if not Compat.RequestLoadItemDataByID then
    return false
  end
  ItemProvider.pending[itemID] = true
  local ok, err = pcall(Compat.RequestLoadItemDataByID, itemID)
  if not ok then
    ItemProvider.pending[itemID] = nil
    Log.Debug("RequestLoadItemDataByID(%s) failed: %s", tostring(itemID), tostring(err))
    return false
  end
  return true
end

-- Returns { itemID, exists, loaded, name, link, icon, quality, unavailable }.
-- Never blocks: when data is missing it requests a load and the caller
-- refreshes on FP_ITEM_LOADED.
function ItemProvider.GetItem(itemID)
  local info = { itemID = itemID, exists = nil, loaded = false }
  if not Util.IsPositiveInt(itemID) then
    info.exists = false
    return info
  end
  info.exists = ItemProvider.Exists(itemID)
  if info.exists == false then
    return info
  end
  if Compat.GetItemInfoInstant then
    local ok, _, _, _, _, icon = pcall(Compat.GetItemInfoInstant, itemID)
    if ok then
      info.icon = icon
    end
  end
  if Compat.GetItemInfo then
    local ok, name, link, quality, _, _, _, _, _, _, texture = pcall(Compat.GetItemInfo, itemID)
    if ok and name then
      info.loaded = true
      info.name = name
      info.link = link
      info.quality = quality
      info.icon = info.icon or texture
      ItemProvider.RememberName(itemID, name)
      return info
    end
  end
  info.name = ItemProvider.GetCachedName(itemID)
  local catalogue = ns.Data and ns.Data.Recipes
  if catalogue and catalogue.ItemQuality then
    info.quality = catalogue.ItemQuality(itemID)
  end
  if ItemProvider.failed[itemID] then
    info.unavailable = true
  else
    ItemProvider.RequestLoad(itemID)
  end
  return info
end

-- Display name with a readable fallback.
function ItemProvider.GetName(itemID)
  local info = ItemProvider.GetItem(itemID)
  return info.name or ("Item " .. tostring(itemID))
end

-- Warms the name cache without forcing a UI refresh.
function ItemProvider.Prefetch(itemID)
  if not Util.IsPositiveInt(itemID) or ItemProvider.GetCachedName(itemID) then
    return
  end
  ItemProvider.GetItem(itemID)
end

-- Name search over cached names and scanned recipe names. Exact matches rank
-- first, then prefix matches, then substring matches. Limited to `limit` hits.
function ItemProvider.SearchByName(query, limit)
  limit = limit or 10
  local results = {}
  local needle = Util.Trim(query):lower()
  if needle == "" then
    return results
  end
  local seen = {}
  local exact, prefix, partial = {}, {}, {}
  local function consider(itemID, name)
    if seen[itemID] or type(name) ~= "string" then
      return
    end
    local lower = name:lower()
    local bucket
    if lower == needle then
      bucket = exact
    elseif lower:sub(1, #needle) == needle then
      bucket = prefix
    elseif lower:find(needle, 1, true) then
      bucket = partial
    end
    if bucket then
      seen[itemID] = true
      bucket[#bucket + 1] = { itemID = itemID, name = name }
    end
  end
  local cache = nameCache()
  if cache then
    for itemID, name in pairs(cache) do
      consider(itemID, name)
    end
  end
  if ns.db and ns.db.recipes then
    for _, recipe in pairs(ns.db.recipes) do
      if recipe.outputItemID then
        consider(recipe.outputItemID, recipe.name)
      end
    end
  end
  -- The catalogue names every item a recipe makes or needs.
  local catalogue = ns.Data and ns.Data.Recipes
  if catalogue and catalogue.Items then
    for itemID, row in pairs(catalogue.Items()) do
      consider(itemID, row[1])
    end
  end
  local function byName(a, b) return a.name < b.name end
  table.sort(exact, byName)
  table.sort(prefix, byName)
  table.sort(partial, byName)
  for _, bucket in ipairs({ exact, prefix, partial }) do
    for _, hit in ipairs(bucket) do
      if #results >= limit then
        return results
      end
      results[#results + 1] = hit
    end
  end
  return results
end

function ItemProvider.OnItemDataLoadResult(itemID, success)
  if not ItemProvider.pending[itemID] then
    return
  end
  ItemProvider.pending[itemID] = nil
  if success == false then
    ItemProvider.failed[itemID] = true
  elseif Compat.GetItemInfo then
    local ok, name = pcall(Compat.GetItemInfo, itemID)
    if ok and name then
      ItemProvider.RememberName(itemID, name)
    end
  end
  Events.Fire("FP_ITEM_LOADED", itemID, success ~= false)
end

function ItemProvider.Init()
  Events.RegisterWoW("ITEM_DATA_LOAD_RESULT", ItemProvider.OnItemDataLoadResult)
  Events.RegisterWoW("GET_ITEM_INFO_RECEIVED", ItemProvider.OnItemDataLoadResult)
end
