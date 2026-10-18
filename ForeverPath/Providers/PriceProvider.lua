-- Pricing boundary used by CraftWise, the shopping list and the tables.
--
-- Sources register themselves (vendor recorder in 0.6.0, Auctionator in
-- 0.8.0). A lookup asks every source and returns the cheapest known price;
-- the others are kept on the result so the UI can say "vendor 10c, AH 8c".
--
--   PriceProvider.IsAvailable() -> boolean
--   PriceProvider.GetPrice(itemID) -> priceInfo | nil, reason
--     priceInfo = { copper, source = "vendor"|"auctionator", kind = "vendor"|"market",
--                   scannedAt, ageDays, avg7, listings, vendor, alternatives = { priceInfo } }
--
-- An unknown price is nil, never zero. Engines must treat nil as "unknown" and
-- surface it instead of silently pricing a material at 0.
local _, ns = ...

local Util = ns.Util

local PriceProvider = {
  sources = {},
}
ns.PriceProvider = PriceProvider

-- Freshness thresholds from the design: fresh under 3 h, aging 3-24 h, stale after.
PriceProvider.FRESH_SECONDS = 3 * 3600
PriceProvider.AGING_SECONDS = 24 * 3600

function PriceProvider.RegisterSource(name, source)
  if type(name) == "string" and type(source) == "table" and type(source.GetPrice) == "function" then
    for _, entry in ipairs(PriceProvider.sources) do
      if entry.name == name then
        entry.source = source
        return true
      end
    end
    PriceProvider.sources[#PriceProvider.sources + 1] = { name = name, source = source }
    return true
  end
  return false
end

function PriceProvider.Source(name)
  for _, entry in ipairs(PriceProvider.sources) do
    if entry.name == name then return entry.source end
  end
  return nil
end

function PriceProvider.IsAvailable()
  for _, entry in ipairs(PriceProvider.sources) do
    local ok, available = pcall(entry.source.IsAvailable or function() return true end)
    if ok and available then
      return true
    end
  end
  return false
end

-- Cheapest known price across sources; alternatives hold the rest.
function PriceProvider.GetPrice(itemID)
  local best
  local found = {}
  for _, entry in ipairs(PriceProvider.sources) do
    local ok, info = pcall(entry.source.GetPrice, itemID)
    if ok and type(info) == "table" and type(info.copper) == "number" and info.copper > 0 then
      info.source = info.source or entry.name
      found[#found + 1] = info
      if not best or info.copper < best.copper then best = info end
    end
  end
  if not best then
    return nil, #PriceProvider.sources == 0 and "no price source configured" or "no price recorded"
  end
  local alternatives = {}
  for _, info in ipairs(found) do
    if info ~= best then alternatives[#alternatives + 1] = info end
  end
  best.alternatives = alternatives
  return best
end

-- The Auction House price only (ignores vendors), for "buy the finished item".
function PriceProvider.GetMarket(itemID)
  local source = PriceProvider.Source("auctionator")
  if not source then return nil end
  local ok, info = pcall(source.GetPrice, itemID)
  if ok and type(info) == "table" and type(info.copper) == "number" then
    info.source = info.source or "auctionator"
    return info
  end
  return nil
end

-- { key = "vendor"|"fresh"|"aging"|"stale"|"unknown", label, kind (dot colour) }
function PriceProvider.Freshness(info, now)
  if not info then return { key = "unknown", label = "no price", kind = "text3" } end
  if info.kind == "vendor" then return { key = "vendor", label = "vendor", kind = "info" } end
  if not info.scannedAt then return { key = "unknown", label = "age unknown", kind = "partial" } end
  now = now or Util.Now()
  local age = math.max(0, now - info.scannedAt)
  local label = Util.FormatAgo(info.scannedAt, now)
  if age < PriceProvider.FRESH_SECONDS then
    return { key = "fresh", label = label, kind = "ok", age = age }
  elseif age < PriceProvider.AGING_SECONDS then
    return { key = "aging", label = label, kind = "partial", age = age }
  end
  return { key = "stale", label = label .. " - stale", kind = "missing", age = age }
end

-- Worst of several freshness keys (for a total built from many prices).
local RANK = { vendor = 0, fresh = 1, aging = 2, stale = 3, unknown = 4 }
function PriceProvider.WorstFreshness(a, b)
  if not a then return b end
  if not b then return a end
  return (RANK[b.key] or 0) > (RANK[a.key] or 0) and b or a
end

-- Status of the market source for the status bar and /fp prices.
-- { installed, available, lastScan, freshness, text }
function PriceProvider.Status(now)
  now = now or Util.Now()
  local source = PriceProvider.Source("auctionator")
  local status = { installed = false, available = false }
  if source then
    local ok, installed = pcall(source.installed or function() return false end)
    status.installed = ok and installed == true
    local okA, available = pcall(source.IsAvailable or function() return true end)
    status.available = okA and available == true
    if type(source.LastScan) == "function" then
      local okScan, t = pcall(source.LastScan)
      if okScan then status.lastScan = t end
    end
  end
  if not status.installed then
    status.text = "AH prices: Auctionator not installed"
    status.kind = "text3"
  elseif not status.available then
    status.text = "AH prices: Auctionator API unavailable"
    status.kind = "missing"
  elseif not status.lastScan then
    status.text = "AH prices: no scan yet - open the Auction House and scan"
    status.kind = "partial"
  else
    status.freshness = PriceProvider.Freshness({ kind = "market", scannedAt = status.lastScan }, now)
    status.text = "AH prices: cached scan - " .. status.freshness.label
    status.kind = status.freshness.kind
  end
  return status
end

-- Chat lines for /fp prices <item>.
function PriceProvider.Describe(itemID, moneyFn)
  moneyFn = moneyFn or function(c) return tostring(c) .. "c" end
  local lines = {}
  local best = PriceProvider.GetPrice(itemID)
  if not best then
    lines[1] = "no price recorded (vendors are recorded when you open them; AH prices come from Auctionator scans)"
    return lines
  end
  local function describe(info)
    local text = string.format("%s: %s each", info.kind == "vendor" and ("Vendor" .. (info.vendor and (" " .. info.vendor) or "")) or "Auction House", moneyFn(info.copper))
    if info.kind ~= "vendor" then
      local f = PriceProvider.Freshness(info)
      text = text .. " (" .. f.label .. ")"
      if info.avg7 then text = text .. ", 7-day average " .. moneyFn(info.avg7) end
      if info.listings then text = text .. string.format(", %d listed", info.listings) end
    end
    return text
  end
  lines[#lines + 1] = describe(best) .. " - cheapest"
  for _, alt in ipairs(best.alternatives or {}) do
    lines[#lines + 1] = describe(alt)
  end
  return lines
end
