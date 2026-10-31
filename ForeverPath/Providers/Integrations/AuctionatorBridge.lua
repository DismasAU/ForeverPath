-- Auction House prices through Auctionator's public API.
--
-- Auctionator keeps one price database per realm, filled by the player's own
-- scans, and exposes it as:
--   Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID) -> copper | nil
--     (the lowest buyout seen in the last scan that listed the item)
--   Auctionator.API.v1.GetAuctionAgeByItemID(callerID, itemID)   -> days | nil
--     (days since the item was last seen; nil when never seen or > 21 days)
-- Its database object also has GetMeanPrice(dbKey, days) and
-- GetPriceHistory(dbKey) (per-day lowest/highest/available); both are read
-- through Util.SafeCall because they are not part of the v1 contract.
-- AUCTIONATOR_SAVEDVARS.TimeOfLastBrowseScan is the time of the last full
-- browse scan on this account.
--
-- Nothing is written to Auctionator. Without it the source stays silent and
-- PriceProvider reports no market prices.
local _, ns = ...

local Log = ns.Log
local Util = ns.Util

local AuctionatorBridge = { CALLER = "ForeverPath" }
ns.AuctionatorBridge = AuctionatorBridge

local function api()
  local a = _G.Auctionator
  if type(a) ~= "table" or type(a.API) ~= "table" or type(a.API.v1) ~= "table" then return nil end
  return a.API.v1
end

function AuctionatorBridge.IsAvailable()
  local v1 = api()
  return v1 ~= nil and type(v1.GetAuctionPriceByItemID) == "function"
end

-- Time of the last browse scan, or nil.
function AuctionatorBridge.LastScan()
  local vars = _G.AUCTIONATOR_SAVEDVARS
  local t = type(vars) == "table" and tonumber(vars.TimeOfLastBrowseScan) or nil
  if t and t > 0 then return t end
  return nil
end

local function database()
  local a = _G.Auctionator
  return type(a) == "table" and type(a.Database) == "table" and a.Database or nil
end

-- { copper, kind = "market", ageDays, scannedAt, avg7, listings } | nil
function AuctionatorBridge.GetPrice(itemID)
  local v1 = api()
  if not v1 or type(itemID) ~= "number" then return nil end
  local copper = Util.SafeCall(v1.GetAuctionPriceByItemID, AuctionatorBridge.CALLER, itemID)
  if type(copper) ~= "number" or copper <= 0 then return nil end
  local info = { copper = copper, kind = "market", source = "auctionator" }
  local days = Util.SafeCall(v1.GetAuctionAgeByItemID, AuctionatorBridge.CALLER, itemID)
  if type(days) == "number" then info.ageDays = days end
  local now = Util.Now()
  local lastScan = AuctionatorBridge.LastScan()
  if info.ageDays == 0 and lastScan then
    info.scannedAt = lastScan
  elseif info.ageDays then
    info.scannedAt = now - info.ageDays * 86400
  elseif lastScan then
    info.scannedAt = lastScan
  end
  local db = database()
  if db then
    local mean = Util.SafeCall(db.GetMeanPrice, db, tostring(itemID), 7)
    if type(mean) == "number" and mean > 0 then info.avg7 = mean end
    local history = Util.SafeCall(db.GetPriceHistory, db, tostring(itemID))
    if type(history) == "table" and type(history[1]) == "table" then
      info.listings = tonumber(history[1].available)
    end
  end
  return info
end

function AuctionatorBridge.Init()
  ns.PriceProvider.RegisterSource("auctionator", {
    IsAvailable = AuctionatorBridge.IsAvailable,
    GetPrice = AuctionatorBridge.GetPrice,
    market = true,
    label = "Auctionator",
    StatusInfo = function()
      return { installed = _G.Auctionator ~= nil, available = AuctionatorBridge.IsAvailable(), lastScan = AuctionatorBridge.LastScan() }
    end,
  })
  Log.Debug("Auctionator price source: %s", AuctionatorBridge.IsAvailable() and "available" or "not available")
end
