-- Observable item quantities: character bags live, bank when available.
--
-- Bags are indexed by scanning container slots once per change event
-- (BAG_UPDATE_DELAYED), never per frame. Bank contents are scanned while the
-- bank window is open and kept as a timestamped snapshot per character; the
-- UI always says whether a bank figure is live, cached or unknown.
local _, ns = ...

local Compat = ns.Compat
local Util = ns.Util
local Log = ns.Log
local Events = ns.Events

local InventoryProvider = {
  bags = { items = {}, scannedAt = nil, dirty = true },
  bankOpen = false,
}
ns.InventoryProvider = InventoryProvider

function InventoryProvider.IsAvailable()
  return (Compat.GetContainerSlot ~= nil and Compat.GetContainerNumSlots ~= nil) or Compat.GetItemCount ~= nil
end

local function canScanContainers()
  return Compat.GetContainerSlot ~= nil and Compat.GetContainerNumSlots ~= nil
end

function InventoryProvider.BagIDs()
  local ids = {}
  for bag = 0, Compat.numBagSlots do
    ids[#ids + 1] = bag
  end
  if Compat.numReagentBagSlots > 0 then
    ids[#ids + 1] = Compat.reagentBagIndex
  end
  return ids
end

function InventoryProvider.BankIDs()
  if Compat.hasBankTabs then
    local ok, tabs = pcall(C_Bank.FetchPurchasedBankTabIDs, Compat.bankTypeCharacter)
    if ok and type(tabs) == "table" then
      return tabs
    end
    return {}
  end
  -- Legacy layout (clients without bank tabs): main bank container plus bank bags.
  local ids = { -1 }
  local numBankBags = tonumber(_G.NUM_BANKBAGSLOTS) or 0
  for i = 1, numBankBags do
    ids[#ids + 1] = Compat.numBagSlots + i
  end
  return ids
end

local function scanContainers(ids)
  local items, slots = {}, 0
  for _, bag in ipairs(ids) do
    local ok, numSlots = pcall(Compat.GetContainerNumSlots, bag)
    if ok and type(numSlots) == "number" then
      for slot = 1, numSlots do
        local ok2, itemID, count = pcall(Compat.GetContainerSlot, bag, slot)
        if ok2 and itemID then
          items[itemID] = (items[itemID] or 0) + (count or 1)
        end
        slots = slots + 1
      end
    end
  end
  return items, slots
end

function InventoryProvider.ScanBags()
  if not canScanContainers() then
    return false
  end
  local items, slots = scanContainers(InventoryProvider.BagIDs())
  InventoryProvider.bags.items = items
  InventoryProvider.bags.scannedAt = Util.Now()
  InventoryProvider.bags.dirty = false
  Log.Debug("Scanned bags: %d slots, %d distinct items", slots, Util.Count(items))
  return true
end

-- Current bag contents for a snapshot. Rescans when the index is stale but
-- leaves the dirty flag alone, so the next lookup still refreshes itself.
function InventoryProvider.ReadBags()
  if not canScanContainers() then
    return {}, nil
  end
  if not InventoryProvider.bags.dirty then
    return InventoryProvider.bags.items, InventoryProvider.bags.scannedAt
  end
  local items = scanContainers(InventoryProvider.BagIDs())
  return items, Util.Now()
end

function InventoryProvider.ScanBank()
  if not InventoryProvider.bankOpen or not ns.chardb or not canScanContainers() then
    return false
  end
  local items, slots = scanContainers(InventoryProvider.BankIDs())
  ns.chardb.bankCache = { items = items, scannedAt = Util.Now() }
  Log.Debug("Scanned bank: %d slots, %d distinct items", slots, Util.Count(items))
  Events.Fire("FP_INVENTORY_UPDATED")
  return true
end

function InventoryProvider.GetBagCount(itemID)
  if canScanContainers() then
    if InventoryProvider.bags.dirty then
      InventoryProvider.ScanBags()
    end
    return InventoryProvider.bags.items[itemID] or 0
  end
  if Compat.GetItemCount then
    local ok, count = pcall(Compat.GetItemCount, itemID, false)
    if ok and type(count) == "number" then
      return count
    end
  end
  return 0
end

-- Returns { bags, bank, bankSource, bankScannedAt, total }.
-- bankSource: "live" (bank open), "cached" (snapshot), "client" (GetItemCount
-- reported more with the bank included; unverified on Forever), or "none".
function InventoryProvider.GetCounts(itemID)
  local bags = InventoryProvider.GetBagCount(itemID)
  local result = { bags = bags, bank = nil, bankSource = "none", bankScannedAt = nil }
  local cache = ns.chardb and ns.chardb.bankCache or nil
  if cache and cache.scannedAt then
    result.bank = cache.items[itemID] or 0
    result.bankSource = InventoryProvider.bankOpen and "live" or "cached"
    result.bankScannedAt = cache.scannedAt
  elseif Compat.GetItemCount then
    local ok1, withBank = pcall(Compat.GetItemCount, itemID, true)
    local ok2, without = pcall(Compat.GetItemCount, itemID, false)
    if ok1 and ok2 and type(withBank) == "number" and type(without) == "number" and withBank > without then
      result.bank = withBank - without
      result.bankSource = "client"
    end
  end
  -- Alts' snapshots (never the current character). Always reported so the UI
  -- can say "Miravelle has 6"; only counted as owned when settings.includeAlts.
  local characters = ns.CharacterProvider
  if characters and characters.AltTotal then
    local includeBank = not (ns.db and ns.db.settings and ns.db.settings.includeBank == false)
    local total, alts = characters.AltTotal(itemID, includeBank)
    if total > 0 then
      result.alts = total
      result.altSources = {}
      for i, alt in ipairs(alts) do result.altSources[i] = { name = alt.name, count = alt.total, freshness = alt.freshness } end
    end
  end
  result.total = bags + (result.bank or 0)
  return result
end

function InventoryProvider.MarkDirty()
  InventoryProvider.bags.dirty = true
end

local function notifyChanged()
  Events.Debounce("inventory-changed", 0.2, function()
    Events.Fire("FP_INVENTORY_UPDATED")
  end)
end

function InventoryProvider.Init()
  Events.RegisterWoW("BAG_UPDATE_DELAYED", function()
    InventoryProvider.MarkDirty()
    if InventoryProvider.bankOpen then
      Events.Debounce("bank-scan", 0.2, InventoryProvider.ScanBank)
    end
    notifyChanged()
  end)
  Events.RegisterWoW("BANKFRAME_OPENED", function()
    InventoryProvider.bankOpen = true
    InventoryProvider.ScanBank()
    -- Some clients populate bank tabs slightly after the frame opens.
    if Compat.After then
      Compat.After(0.5, function() Log.Call(InventoryProvider.ScanBank) end)
    end
  end)
  Events.RegisterWoW("BANKFRAME_CLOSED", function()
    InventoryProvider.bankOpen = false
    notifyChanged()
  end)
  Events.RegisterWoW("PLAYERBANKSLOTS_CHANGED", function()
    if InventoryProvider.bankOpen then
      Events.Debounce("bank-scan", 0.2, InventoryProvider.ScanBank)
    end
  end)
  Events.RegisterWoW("BANK_TABS_CHANGED", function()
    if InventoryProvider.bankOpen then
      Events.Debounce("bank-scan", 0.2, InventoryProvider.ScanBank)
    end
  end)
  Events.RegisterWoW("PLAYER_ENTERING_WORLD", function()
    InventoryProvider.MarkDirty()
  end)
end
