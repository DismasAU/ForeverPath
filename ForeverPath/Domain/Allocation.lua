-- Inventory allocation ledger. Pure Lua, no API access.
--
-- A ledger remembers how much of each item has already been claimed, so the
-- same stack of Linen Cloth is not counted as "owned" by two goals (or by two
-- branches of one dependency tree). Claims are made in evaluation order:
-- higher-priority goals first, and within a tree in reagent order. Bags are
-- consumed before the bank.
local _, ns = ...

local Allocation = {}
ns.Allocation = Allocation

local Ledger = {}
Ledger.__index = Ledger

function Allocation.New()
  return setmetatable({ used = {} }, Ledger)
end

-- Normalizes a raw inventory count (number or counts table) into
-- { bags, bank|nil, bankSource }.
function Allocation.Normalize(counts)
  if type(counts) == "number" then
    return { bags = counts, bank = nil, bankSource = "none" }
  end
  if type(counts) ~= "table" then
    return { bags = 0, bank = nil, bankSource = "none" }
  end
  local bank = tonumber(counts.bank)
  return {
    bags = tonumber(counts.bags) or 0,
    bank = bank,
    bankSource = counts.bankSource or (bank and "unknown" or "none"),
    bankScannedAt = counts.bankScannedAt,
    alts = tonumber(counts.alts),
    altSources = counts.altSources,
  }
end

-- How much of itemID this ledger has already handed out.
function Ledger:Used(itemID)
  return self.used[itemID] or 0
end

-- What is still free: counts minus earlier claims. Bags are consumed first,
-- then the bank, then alts' snapshots (only when includeAlts is true).
-- Returns { bags, bank|nil, alts|nil, total, bankSource, reserved }.
function Ledger:Available(itemID, counts, includeBank, includeAlts)
  local c = Allocation.Normalize(counts)
  local used = self:Used(itemID)
  local bags = math.max(0, c.bags - used)
  local spill = math.max(0, used - c.bags)
  local bank = c.bank and math.max(0, c.bank - spill) or nil
  local bankSpill = c.bank and math.max(0, spill - c.bank) or spill
  local alts = c.alts and math.max(0, c.alts - bankSpill) or nil
  local total = bags
  if includeBank ~= false and bank then
    total = total + bank
  end
  if includeAlts == true and alts then
    total = total + alts
  end
  return { bags = bags, bank = bank, alts = alts, total = total, bankSource = c.bankSource, bankScannedAt = c.bankScannedAt,
    altSources = c.altSources, reserved = used }
end

-- Claims up to `wanted` units of itemID. Returns a counts table describing
-- what was taken: { bags, bank|nil, total, bankSource, reserved, availableBags,
-- availableBank, availableTotal } where `reserved` is how much earlier claims
-- had already removed and `available*` is what was free before this claim.
function Ledger:Take(itemID, counts, wanted, includeBank, includeAlts)
  local free = self:Available(itemID, counts, includeBank, includeAlts)
  wanted = math.max(0, tonumber(wanted) or 0)
  local fromBags = math.min(free.bags, wanted)
  local fromBank = 0
  if includeBank ~= false and free.bank then
    fromBank = math.min(free.bank, wanted - fromBags)
  end
  local fromAlts = 0
  if includeAlts == true and free.alts then
    fromAlts = math.min(free.alts, wanted - fromBags - fromBank)
  end
  local taken = fromBags + fromBank + fromAlts
  self.used[itemID] = self:Used(itemID) + taken
  return {
    bags = fromBags,
    bank = free.bank and fromBank or nil,
    alts = free.alts and fromAlts or nil,
    total = taken,
    bankSource = free.bankSource,
    bankScannedAt = free.bankScannedAt,
    altSources = free.altSources,
    reserved = free.reserved,
    availableBags = free.bags,
    availableBank = free.bank,
    availableAlts = free.alts,
    availableTotal = free.total,
  }
end

-- Gives units back (used when a branch is discarded).
function Ledger:Release(itemID, amount)
  self.used[itemID] = math.max(0, self:Used(itemID) - (tonumber(amount) or 0))
end
