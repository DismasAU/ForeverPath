-- Vendor recorder. Every time a merchant window opens, the items it sells are
-- written into the account database with the NPC, zone and unit price. This
-- is the only vendor data that is guaranteed to match this build of Forever,
-- and it also registers as a price source: vendor prices are exact.
local _, ns = ...

local Compat = ns.Compat
local Util = ns.Util
local Log = ns.Log
local Events = ns.Events

local VendorProvider = { open = false }
ns.VendorProvider = VendorProvider

function VendorProvider.IsAvailable()
  return Compat.GetMerchantNumItems ~= nil and Compat.GetMerchantItemLink ~= nil and Compat.GetMerchantItem ~= nil
end

function VendorProvider.Store()
  if not ns.db then return nil end
  ns.db.vendors = ns.db.vendors or {}
  return ns.db.vendors
end

local function itemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  local id = link:match("|Hitem:(%d+)")
  return id and tonumber(id) or nil
end

local function currentNPC()
  local name
  if type(UnitName) == "function" then
    local ok, n = pcall(UnitName, "npc")
    if ok then name = n end
  end
  if not name or name == "" then return nil end
  return name
end

local function currentZone()
  local zone, sub
  if type(GetZoneText) == "function" then
    local ok, z = pcall(GetZoneText)
    if ok then zone = z end
  end
  if type(GetSubZoneText) == "function" then
    local ok, s = pcall(GetSubZoneText)
    if ok and s ~= "" then sub = s end
  end
  return zone, sub
end

-- Records the open merchant. Returns the number of items recorded.
function VendorProvider.ScanMerchant()
  local store = VendorProvider.Store()
  if not store or not VendorProvider.IsAvailable() or not VendorProvider.open then
    return 0
  end
  local npc = currentNPC()
  if not npc then
    return 0
  end
  local okCount, count = pcall(Compat.GetMerchantNumItems)
  if not okCount or type(count) ~= "number" then
    return 0
  end
  local zone, subzone = currentZone()
  local now = Util.Now()
  local recorded = 0
  for index = 1, count do
    local okLink, link = pcall(Compat.GetMerchantItemLink, index)
    local itemID = okLink and itemIDFromLink(link) or nil
    local okInfo, info = pcall(Compat.GetMerchantItem, index)
    if itemID and okInfo and type(info) == "table" then
      local stack = (tonumber(info.stack) and info.stack > 0) and info.stack or 1
      local entry = {
        price = (not info.hasExtendedCost and tonumber(info.price) and info.price > 0) and math.floor(info.price / stack) or nil,
        stack = stack,
        limited = (tonumber(info.numAvailable) or -1) >= 0,
        extended = info.hasExtendedCost and true or nil,
        zone = zone,
        subzone = subzone,
        seenAt = now,
      }
      store[itemID] = store[itemID] or {}
      store[itemID][npc] = entry
      if ns.ItemProvider and info.name then ns.ItemProvider.RememberName(itemID, info.name) end
      recorded = recorded + 1
    end
  end
  Log.Debug("Recorded vendor %s (%s): %d items", npc, zone or "?", recorded)
  if recorded > 0 then
    Events.Fire("FP_SOURCES_UPDATED", "vendor", npc)
  end
  return recorded
end

-- Vendors known to sell itemID: { { name, price (copper per unit or nil), stack, zone, subzone, seenAt, limited, extended } }
-- sorted by price, cheapest first.
function VendorProvider.VendorsFor(itemID)
  local store = VendorProvider.Store()
  local out = {}
  local byNPC = store and store[itemID]
  if type(byNPC) ~= "table" then return out end
  for npc, entry in pairs(byNPC) do
    out[#out + 1] = { name = npc, price = entry.price, stack = entry.stack, zone = entry.zone, subzone = entry.subzone,
      seenAt = entry.seenAt, limited = entry.limited, extended = entry.extended }
  end
  table.sort(out, function(a, b)
    local pa, pb = a.price or math.huge, b.price or math.huge
    if pa ~= pb then return pa < pb end
    return a.name < b.name
  end)
  return out
end

-- Resolver hints.
function VendorProvider.Sources(itemID)
  local options = {}
  for _, vendor in ipairs(VendorProvider.VendorsFor(itemID)) do
    local where = vendor.zone or "?"
    if vendor.subzone then where = where .. " (" .. vendor.subzone .. ")" end
    local cost
    if vendor.price then
      cost = ns.UI and ns.UI.Widgets and ns.UI.Widgets.Money(vendor.price, true) or (vendor.price .. "c")
    elseif vendor.extended then
      cost = "costs other items"
    else
      cost = "price unknown"
    end
    options[#options + 1] = {
      kind = "vendor", name = vendor.name, price = vendor.price, zone = vendor.zone,
      label = "Buy from " .. vendor.name,
      detail = string.format("%s - %s each%s", where, cost, vendor.limited and " (limited stock)" or ""),
    }
  end
  return options
end

-- Cheapest known vendor price for the PriceProvider boundary.
function VendorProvider.GetPrice(itemID)
  local vendors = VendorProvider.VendorsFor(itemID)
  local best = vendors[1]
  if best and best.price then
    return { copper = best.price, source = "vendor", timestamp = best.seenAt, kind = "vendor", vendor = best.name }
  end
  -- Nothing recorded on this client: the classic vendor price, if any vendor
  -- this faction can use sells it (a merchant window visit replaces it).
  local CDB = ns.ClassicDB
  if CDB and CDB.IsAvailable() then
    local price, vendor = CDB.VendorPrice(itemID)
    if price then
      return { copper = price, source = "vendor", kind = "vendor", vendor = vendor.npc.name, classic = true }
    end
  end
  return nil, "no vendor recorded"
end

function VendorProvider.Count()
  local store = VendorProvider.Store()
  local items, vendors, seen = 0, 0, {}
  for _, byNPC in pairs(store or {}) do
    items = items + 1
    for npc in pairs(byNPC) do
      if not seen[npc] then seen[npc] = true; vendors = vendors + 1 end
    end
  end
  return items, vendors
end

function VendorProvider.Init()
  if ns.PriceProvider then
    ns.PriceProvider.RegisterSource("vendor", { IsAvailable = function() return true end, GetPrice = VendorProvider.GetPrice })
  end
  if not VendorProvider.IsAvailable() then
    Log.Debug("Merchant API unavailable; vendor recording disabled")
    return
  end
  Events.RegisterWoW("MERCHANT_SHOW", function()
    VendorProvider.open = true
    VendorProvider.ScanMerchant()
    -- Item data for merchant slots can arrive a moment after the frame opens.
    if Compat.After then
      Compat.After(0.5, function() Log.Call(VendorProvider.ScanMerchant) end)
    end
  end)
  Events.RegisterWoW("MERCHANT_UPDATE", function()
    if VendorProvider.open then
      Events.Debounce("merchant-scan", 0.3, VendorProvider.ScanMerchant)
    end
  end)
  Events.RegisterWoW("MERCHANT_CLOSED", function()
    VendorProvider.open = false
  end)
end
