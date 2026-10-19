-- Trainer recorder. Each time a profession trainer window opens, every recipe
-- on offer is written into the account database with the skill it requires,
-- its cost and the trainer's name and zone. The client's own tables do not
-- carry trainer requirements (they are server data, sent only while the
-- window is open), so this is the one place the catalogue's "learned from a
-- trainer" recipes get an exact required skill. One visit per trainer, by
-- any character on the account, is enough.
local _, ns = ...

local Compat = ns.Compat
local Util = ns.Util
local Log = ns.Log
local Events = ns.Events

local TrainerProvider = { open = false, restoreFilters = nil }
ns.TrainerProvider = TrainerProvider

TrainerProvider.FILTERS = { "available", "unavailable", "used" }

function TrainerProvider.IsAvailable()
  return type(_G.GetNumTrainerServices) == "function" and type(_G.GetTrainerServiceInfo) == "function"
end

-- spellID -> { skill, rank, cost, trainer, zone, subzone, seenAt }
function TrainerProvider.Store()
  if not ns.db then return nil end
  ns.db.trainers = ns.db.trainers or {}
  return ns.db.trainers
end

-- trainer name -> { zone, subzone, recipes, seenAt }
function TrainerProvider.Trainers()
  if not ns.db then return nil end
  ns.db.trainerNPCs = ns.db.trainerNPCs or {}
  return ns.db.trainerNPCs
end

local function call(name, ...)
  local fn = _G[name]
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

local function currentNPC()
  local name = call("UnitName", "npc")
  if type(name) ~= "string" or name == "" then return nil end
  return name
end

local function currentZone()
  local zone = call("GetZoneText")
  local sub = call("GetSubZoneText")
  if sub == "" then sub = nil end
  return zone, sub
end

local function spellIDFromLink(link)
  if type(link) ~= "string" then return nil end
  local id = link:match("|Henchant:(%d+)") or link:match("|Hspell:(%d+)")
  return id and tonumber(id) or nil
end

-- The service type ("available", "unavailable", "used", "header") is the
-- second return on this client (Forever addons read it there); older clients
-- put it third, so both positions are accepted.
local KNOWN_TYPES = { available = true, unavailable = true, used = true, header = true }
local function serviceType(a, b)
  if KNOWN_TYPES[a] then return a end
  if KNOWN_TYPES[b] then return b end
  return nil
end

-- Reads one trainer line. Returns a record or nil.
function TrainerProvider.ReadService(index)
  local name, second, third = call("GetTrainerServiceInfo", index)
  if type(name) ~= "string" then return nil end
  local kind = serviceType(second, third)
  if kind == "header" then return nil end
  local record = { name = name, kind = kind }
  local skill, rank, hasReq = call("GetTrainerServiceSkillReq", index)
  if type(skill) == "string" and skill ~= "" and (hasReq ~= false) and tonumber(rank) then
    record.skill = skill
    record.rank = tonumber(rank)
  end
  -- The spell link names the recipe exactly; without one, the catalogue is
  -- searched by recipe name within the required profession.
  local spellID = spellIDFromLink(call("GetTrainerServiceItemLink", index))
  if not spellID and ns.Data and ns.Data.Recipes and ns.Data.Recipes.SpellIDByName then
    spellID = ns.Data.Recipes.SpellIDByName(name, record.skill)
    record.byName = spellID ~= nil or nil
  end
  if not spellID then return nil end
  record.spellID = spellID
  local cost = call("GetTrainerServiceCost", index)
  if tonumber(cost) then record.cost = tonumber(cost) end
  return record
end

-- Shows every line (available, too advanced, already known) so the whole
-- offer is recorded; the previous filters are put back when the window closes.
function TrainerProvider.EnsureFilters()
  if type(_G.GetTrainerServiceTypeFilter) ~= "function" or type(_G.SetTrainerServiceTypeFilter) ~= "function" then
    return false
  end
  local changed = false
  for _, filter in ipairs(TrainerProvider.FILTERS) do
    local on = call("GetTrainerServiceTypeFilter", filter)
    if not on or on == 0 then
      TrainerProvider.restoreFilters = TrainerProvider.restoreFilters or {}
      TrainerProvider.restoreFilters[filter] = true
      call("SetTrainerServiceTypeFilter", filter, 1)
      changed = true
    end
  end
  return changed
end

function TrainerProvider.RestoreFilters()
  local restore = TrainerProvider.restoreFilters
  TrainerProvider.restoreFilters = nil
  if not restore then return end
  for filter in pairs(restore) do
    call("SetTrainerServiceTypeFilter", filter, 0)
  end
end

-- True when the open window belongs to a profession trainer (or the client
-- cannot say, in which case every recipe with a profession requirement counts).
local function isProfessionTrainer()
  if type(_G.IsTradeskillTrainer) == "function" then
    local ok, result = pcall(_G.IsTradeskillTrainer)
    if ok and result ~= nil then return result and true or false end
  end
  return nil
end

local function isProfessionSkill(name)
  local catalogue = ns.Data and ns.Data.Recipes
  if catalogue and catalogue.ProfessionID and catalogue.ProfessionID(name) then return true end
  return false
end

-- Records the open trainer. Returns the number of recipes recorded.
function TrainerProvider.ScanTrainer()
  local store = TrainerProvider.Store()
  if not store or not TrainerProvider.open or not TrainerProvider.IsAvailable() then return 0 end
  local npc = currentNPC()
  if not npc then return 0 end
  local count = call("GetNumTrainerServices")
  if type(count) ~= "number" then return 0 end
  local tradeskill = isProfessionTrainer()
  if tradeskill == false then return 0 end
  local zone, subzone = currentZone()
  local now = Util.Now()
  local recorded, changed = 0, false
  local catalogue = ns.Data and ns.Data.Recipes
  for index = 1, count do
    local record = TrainerProvider.ReadService(index)
    if record and record.rank then
      local known = catalogue and catalogue.Get and catalogue.Get(record.spellID) ~= nil
      if tradeskill or known or isProfessionSkill(record.skill) then
        local previous = store[record.spellID]
        if not previous or previous.rank ~= record.rank or previous.trainer ~= npc or previous.cost ~= record.cost then
          changed = true
        end
        store[record.spellID] = {
          skill = record.skill, rank = record.rank, cost = record.cost,
          trainer = npc, zone = zone, subzone = subzone, seenAt = now,
        }
        recorded = recorded + 1
      end
    end
  end
  if recorded > 0 then
    local trainers = TrainerProvider.Trainers()
    if trainers then
      trainers[npc] = { zone = zone, subzone = subzone, recipes = recorded, seenAt = now }
    end
    Log.Debug("Recorded trainer %s (%s): %d recipes", npc, zone or "?", recorded)
    if changed then
      if catalogue and catalogue.Invalidate then catalogue.Invalidate() end
      Events.Fire("FP_TRAINERS_UPDATED", npc)
    end
  end
  return recorded
end

-- Requirement recorded for a recipe spell, else the classic trainer data
-- (classic = true), or nil.
function TrainerProvider.Requirement(spellID)
  local store = TrainerProvider.Store()
  local recorded = store and store[spellID] or nil
  if recorded then return recorded end
  -- A trainer another player recorded and shared (Core/Share.lua).
  local shared
  if ns.Share then
    ns.Share.EachImported("trainers", function(_, trainers)
      local entry = trainers[spellID]
      if not shared and type(entry) == "table" then shared = entry end
    end)
  end
  if shared then return shared end
  local CDB = ns.ClassicDB
  if CDB and CDB.IsAvailable() then
    local ok, record = pcall(CDB.Trainer, spellID)
    if ok and record then return record end
  end
  return nil
end

-- "Georgio Bolero (Stormwind City), needs Tailoring 125, 1g"
function TrainerProvider.Describe(spellID, moneyFn)
  local record = TrainerProvider.Requirement(spellID)
  if not record then return nil end
  local where = record.zone or "?"
  if record.subzone then where = where .. " - " .. record.subzone end
  local text = string.format("%s (%s), needs %s %d", record.trainer or "trainer", where, record.skill or "skill", record.rank or 0)
  if record.cost and record.cost > 0 then
    text = text .. ", " .. (moneyFn and moneyFn(record.cost) or (record.cost .. "c"))
  end
  if record.classic then text = text .. " (classic data)" end
  return text
end

function TrainerProvider.Count()
  local recipes, trainers = 0, 0
  for _ in pairs(TrainerProvider.Store() or {}) do recipes = recipes + 1 end
  for _ in pairs(TrainerProvider.Trainers() or {}) do trainers = trainers + 1 end
  return recipes, trainers
end

function TrainerProvider.Status()
  if not TrainerProvider.IsAvailable() then
    return "Trainer windows: API unavailable on this client; trainer requirements cannot be recorded."
  end
  local recipes, trainers = TrainerProvider.Count()
  if recipes == 0 then
    return "Trainer requirements: none recorded yet (open a profession trainer once on any character)."
  end
  return string.format("Trainer requirements: %d recipe%s from %d trainer%s.", recipes, recipes == 1 and "" or "s", trainers, trainers == 1 and "" or "s")
end

function TrainerProvider.Init()
  if ns.Data and ns.Data.Recipes then
    ns.Data.Recipes.trainerLookup = TrainerProvider.Requirement
  end
  Events.RegisterWoW("TRAINER_SHOW", function()
    TrainerProvider.open = true
    TrainerProvider.EnsureFilters()
    TrainerProvider.ScanTrainer()
    -- Lines can fill in a moment after the frame opens.
    if Compat.After then
      Compat.After(0.5, function() Log.Call(TrainerProvider.ScanTrainer) end)
    end
  end)
  Events.RegisterWoW("TRAINER_UPDATE", function()
    if TrainerProvider.open then
      Events.Debounce("trainer-scan", 0.3, TrainerProvider.ScanTrainer)
    end
  end)
  Events.RegisterWoW("TRAINER_CLOSED", function()
    TrainerProvider.open = false
    TrainerProvider.RestoreFilters()
  end)
end
