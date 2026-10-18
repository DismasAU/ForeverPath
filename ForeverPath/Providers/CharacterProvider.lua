-- Account-wide character snapshots.
--
-- Every character writes a snapshot of itself into the account database
-- (ForeverPathDB.characters[key]): identity, level, gold, professions, the
-- recipes it has learned, its bag and bank contents and its open goals. Other
-- characters read those snapshots to answer "which alt already has this" and
-- "which alt can craft this". Snapshots are refreshed on login, on logout and
-- (debounced) whenever bags, goals or recipes change.
local _, ns = ...

local Util = ns.Util
local Events = ns.Events
local Log = ns.Log

local CharacterProvider = {}
ns.CharacterProvider = CharacterProvider

CharacterProvider.SNAPSHOT_FRESH = 24 * 3600   -- younger: "snapshot"; older: "cached"
CharacterProvider.Levels = { LIVE = "live", SNAPSHOT = "snapshot", CACHED = "cached" }

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
  return nil
end

-- Who the logged-in character is. Pure data; the UI adds colours.
function CharacterProvider.Identity()
  local info = { name = "Adventurer", realm = "", level = 0, class = "", classFile = nil, race = "", gold = nil }
  info.name = call(UnitName, "player") or info.name
  info.level = call(UnitLevel, "player") or 0
  local className, classFile = call(UnitClass, "player")
  info.class = className or ""
  info.classFile = classFile
  info.race = call(UnitRace, "player") or ""
  info.realm = call(GetRealmName) or ""
  info.gold = call(GetMoney)
  return info
end

-- Gold you can reach: this character live, plus every alt's snapshot.
-- { current, account, alts = { { name, gold } }, altsTotal }
function CharacterProvider.AccountGold()
  local current = call(GetMoney)
  local out = { current = tonumber(current), alts = {}, altsTotal = 0 }
  for _, entry in ipairs(CharacterProvider.List()) do
    local record = entry.record
    if not entry.isCurrent and type(record) == "table" and type(record.gold) == "number" then
      out.alts[#out.alts + 1] = { name = record.name, gold = record.gold }
      out.altsTotal = out.altsTotal + record.gold
    end
  end
  table.sort(out.alts, function(a, b) return a.gold > b.gold end)
  if out.current then
    out.account = out.current + out.altsTotal
  elseif #out.alts > 0 then
    out.account = out.altsTotal
  end
  return out
end

function CharacterProvider.Key(name, realm)
  return tostring(name) .. "-" .. tostring(realm or "")
end

function CharacterProvider.CurrentKey()
  local id = CharacterProvider.Identity()
  return CharacterProvider.Key(id.name, id.realm)
end

function CharacterProvider.Store()
  if not ns.db then return nil end
  ns.db.characters = ns.db.characters or {}
  return ns.db.characters
end

-- Writes this character's snapshot. Returns the record or nil, reason.
function CharacterProvider.Snapshot()
  local store = CharacterProvider.Store()
  if not store or not ns.chardb then
    return nil, "not loaded"
  end
  local id = CharacterProvider.Identity()
  local key = CharacterProvider.Key(id.name, id.realm)
  local inventory = ns.InventoryProvider
  local bags = { items = {}, scannedAt = nil }
  if inventory and inventory.ReadBags then
    local items, scannedAt = inventory.ReadBags()
    bags.items = Util.DeepCopy(items or {})
    bags.scannedAt = scannedAt
  end
  local bank
  local cache = ns.chardb.bankCache
  if cache and cache.scannedAt then
    bank = { items = Util.DeepCopy(cache.items or {}), scannedAt = cache.scannedAt }
  end
  local professions, professionSource = CharacterProvider.CollectProfessions()
  local previous = store[key]
  if #professions == 0 and previous and previous.professions and #previous.professions > 0 then
    -- The client reports no professions right after login; keep what we had.
    professions = previous.professions
    professionSource = (previous.professionSource or "earlier") .. " (kept)"
  end
  local knownRecipes = {}
  for recipeID, learned in pairs(ns.chardb.knownRecipes or {}) do
    if learned == true then knownRecipes[recipeID] = true end
  end
  local goals = {}
  if ns.GoalService then
    for _, goal in ipairs(ns.GoalService.List({ open = true })) do
      goals[#goals + 1] = { id = goal.id, title = ns.GoalService.Title(goal), status = goal.status, itemID = goal.target and goal.target.itemID }
    end
  end
  local record = {
    key = key, name = id.name, realm = id.realm, level = id.level, class = id.class, classFile = id.classFile, race = id.race,
    gold = id.gold, lastSeen = Util.Now(), bags = bags, bank = bank, professions = professions, professionSource = professionSource,
    knownRecipes = knownRecipes, goals = goals,
  }
  store[key] = record
  Log.Debug("Snapshot saved for %s (%d bag items, %d professions, %d goals)", key, Util.Count(bags.items), #professions, #goals)
  Events.Fire("FP_CHARACTERS_UPDATED", key)
  return record
end

-- Professions from the live list (GetProfessions) merged with the ones recorded
-- from profession windows (chardb.professions). Returns list, source text.
function CharacterProvider.CollectProfessions()
  local list, byName = {}, {}
  local live = 0
  if ns.ProfessionProvider then
    for _, p in ipairs(ns.ProfessionProvider.GetCharacterProfessions()) do
      if p.name and not byName[p.name] then
        local entry = { name = p.name, skillLevel = p.skillLevel, maxSkillLevel = p.maxSkillLevel, skillLine = p.skillLine, icon = p.icon, slot = p.slot }
        byName[p.name] = entry
        list[#list + 1] = entry
        live = live + 1
      end
    end
  end
  local scanned = 0
  for professionID, p in pairs(ns.chardb and ns.chardb.professions or {}) do
    if p.name and not byName[p.name] then
      local entry = { name = p.name, skillLevel = p.skillLevel, maxSkillLevel = p.maxSkillLevel, skillLine = professionID, scanned = true }
      byName[p.name] = entry
      list[#list + 1] = entry
      scanned = scanned + 1
    end
  end
  -- Primary professions (slots 1-2) first, then the secondaries in client
  -- order, then anything known only from a recorded window.
  table.sort(list, function(a, b)
    local sa, sb = a.slot or 99, b.slot or 99
    if sa ~= sb then return sa < sb end
    return (a.name or "") < (b.name or "")
  end)
  local source
  if live > 0 and scanned > 0 then source = "client list + recorded windows"
  elseif live > 0 then source = "client list"
  elseif scanned > 0 then source = "recorded windows only (client list empty)"
  else source = "none (client list empty, no windows recorded)" end
  return list, source
end

function CharacterProvider.Get(key)
  local store = CharacterProvider.Store()
  return store and store[key] or nil
end

function CharacterProvider.Remove(key)
  local store = CharacterProvider.Store()
  if not store or not store[key] then
    return false, "no such character"
  end
  if key == CharacterProvider.CurrentKey() then
    return false, "cannot forget the current character"
  end
  store[key] = nil
  Events.Fire("FP_CHARACTERS_UPDATED", key)
  return true
end

-- "live" for the current character, "snapshot" under 24 h, "cached" beyond.
function CharacterProvider.Freshness(record, now)
  if record.key == CharacterProvider.CurrentKey() then
    return CharacterProvider.Levels.LIVE
  end
  now = now or Util.Now()
  local age = now - (record.lastSeen or 0)
  if age < CharacterProvider.SNAPSHOT_FRESH then
    return CharacterProvider.Levels.SNAPSHOT
  end
  return CharacterProvider.Levels.CACHED
end

-- All known characters, current first, then most recently seen. Each entry is
-- the stored record plus isCurrent / freshness (not persisted).
function CharacterProvider.List()
  local store = CharacterProvider.Store()
  local list = {}
  if not store then return list end
  local current = CharacterProvider.CurrentKey()
  for _, record in pairs(store) do
    list[#list + 1] = record
  end
  table.sort(list, function(a, b)
    if (a.key == current) ~= (b.key == current) then return a.key == current end
    if (a.lastSeen or 0) ~= (b.lastSeen or 0) then return (a.lastSeen or 0) > (b.lastSeen or 0) end
    return a.key < b.key
  end)
  local out = {}
  for i, record in ipairs(list) do
    out[i] = { record = record, key = record.key, isCurrent = record.key == current, freshness = CharacterProvider.Freshness(record) }
  end
  return out
end

function CharacterProvider.Count()
  return #CharacterProvider.List()
end

local function recordCount(record, itemID, includeBank)
  local bags = record.bags and record.bags.items and record.bags.items[itemID] or 0
  local bank = record.bank and record.bank.items and record.bank.items[itemID] or 0
  if includeBank == false then bank = 0 end
  return bags, bank
end

-- Alts (never the current character) holding itemID.
-- Returns list { { record, name, bags, bank, total, freshness } } sorted by total desc.
function CharacterProvider.Alts(itemID, includeBank)
  local out = {}
  for _, entry in ipairs(CharacterProvider.List()) do
    if not entry.isCurrent then
      local bags, bank = recordCount(entry.record, itemID, includeBank)
      if bags + bank > 0 then
        out[#out + 1] = { record = entry.record, name = entry.record.name, key = entry.key, bags = bags, bank = bank, total = bags + bank, freshness = entry.freshness }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.total ~= b.total then return a.total > b.total end
    return a.name < b.name
  end)
  return out
end

-- Units of itemID held by alts, plus the per-alt list.
function CharacterProvider.AltTotal(itemID, includeBank)
  local alts = CharacterProvider.Alts(itemID, includeBank)
  local total = 0
  for _, alt in ipairs(alts) do total = total + alt.total end
  return total, alts
end

-- Characters with a profession, by name (or skill line id): this character
-- first from the live list, then the snapshotted alts.
-- Returns { { name, skillLevel, maxSkillLevel, isCurrent } }.
function CharacterProvider.WithProfession(name, skillLine)
  local out, seen = {}, {}
  if not name and not skillLine then return out end
  local function matches(p)
    return (name and p.name == name) or (skillLine and skillLine ~= 0 and p.skillLine == skillLine)
  end
  local currentName = CharacterProvider.Identity().name
  if ns.ProfessionProvider and ns.ProfessionProvider.GetCharacterProfessions then
    for _, p in ipairs(ns.ProfessionProvider.GetCharacterProfessions() or {}) do
      if matches(p) and currentName and not seen[currentName] then
        out[#out + 1] = { name = currentName, skillLevel = p.skillLevel, maxSkillLevel = p.maxSkillLevel, isCurrent = true }
        seen[currentName] = true
      end
    end
  end
  for _, entry in ipairs(CharacterProvider.List()) do
    local record = entry.record
    if type(record) == "table" and record.name and not seen[record.name] then
      for _, p in ipairs(record.professions or {}) do
        if matches(p) then
          out[#out + 1] = { name = record.name, skillLevel = p.skillLevel, maxSkillLevel = p.maxSkillLevel, isCurrent = entry.isCurrent }
          seen[record.name] = true
          break
        end
      end
    end
  end
  return out
end

-- Alts that have learned a recipe producing itemID.
-- Returns { { record, name, recipe, professionName, skillLevel } }.
function CharacterProvider.CanCraft(itemID)
  local out = {}
  if not ns.db or type(ns.db.itemRecipes) ~= "table" then return out end
  local ids = ns.db.itemRecipes[itemID]
  if type(ids) ~= "table" then return out end
  for _, entry in ipairs(CharacterProvider.List()) do
    if not entry.isCurrent then
      for recipeID in pairs(ids) do
        local recipe = ns.db.recipes[recipeID]
        if recipe and entry.record.knownRecipes and entry.record.knownRecipes[recipeID] then
          local skill
          for _, p in ipairs(entry.record.professions or {}) do
            if p.name == recipe.professionName then skill = p.skillLevel end
          end
          out[#out + 1] = { record = entry.record, name = entry.record.name, key = entry.key, recipe = recipe, professionName = recipe.professionName, skillLevel = skill }
          break
        end
      end
    end
  end
  return out
end

-- Source hints for the dependency resolver: "an alt has it" and "an alt can
-- craft it". Informational routes; the planner only counts alt stock as owned
-- when settings.includeAlts is on.
function CharacterProvider.Sources(itemID)
  local options = {}
  local includeBank = not (ns.db and ns.db.settings and ns.db.settings.includeBank == false)
  for _, alt in ipairs(CharacterProvider.Alts(itemID, includeBank)) do
    options[#options + 1] = {
      kind = "alt", name = alt.name, count = alt.total,
      label = "Mail from " .. alt.name,
      detail = string.format("%s has %d (%s)", alt.name, alt.total, alt.freshness),
    }
  end
  for _, crafter in ipairs(CharacterProvider.CanCraft(itemID)) do
    options[#options + 1] = {
      kind = "altcraft", name = crafter.name,
      label = "Craft on " .. crafter.name,
      detail = string.format("%s - %s%s", crafter.recipe.name or "recipe", crafter.professionName or "?", crafter.skillLevel and (" " .. crafter.skillLevel) or ""),
    }
  end
  return options
end

-- For the Characters banner: which alt covers the most of the given needs.
-- needs: { [itemID] = count }. Returns { name, key, record, covered, items = { { itemID, count } } } or nil.
function CharacterProvider.BestCoverage(needs)
  local includeBank = not (ns.db and ns.db.settings and ns.db.settings.includeBank == false)
  local best
  for _, entry in ipairs(CharacterProvider.List()) do
    if not entry.isCurrent then
      local covered, items = 0, {}
      for itemID, count in pairs(needs or {}) do
        local bags, bank = recordCount(entry.record, itemID, includeBank)
        local has = math.min(count, bags + bank)
        if has > 0 then
          covered = covered + has
          items[#items + 1] = { itemID = itemID, count = has }
        end
      end
      if covered > 0 and (not best or covered > best.covered) then
        table.sort(items, function(a, b)
          if a.count ~= b.count then return a.count > b.count end
          return a.itemID < b.itemID
        end)
        best = { name = entry.record.name, key = entry.key, record = entry.record, covered = covered, items = items }
      end
    end
  end
  return best
end

local function scheduleSnapshot()
  Events.Debounce("character-snapshot", 3, CharacterProvider.Snapshot)
end

function CharacterProvider.Init()
  Events.On("FP_READY", function()
    Events.Debounce("character-snapshot", 1, CharacterProvider.Snapshot)
  end)
  Events.On("FP_INVENTORY_UPDATED", scheduleSnapshot)
  Events.On("FP_GOALS_CHANGED", scheduleSnapshot)
  Events.On("FP_RECIPES_UPDATED", scheduleSnapshot)
  Events.RegisterWoW("PLAYER_LOGOUT", function()
    CharacterProvider.Snapshot()
  end)
  -- Profession data can arrive after login; both of these catch it.
  Events.RegisterWoW("SKILL_LINES_CHANGED", scheduleSnapshot)
  Events.RegisterWoW("PLAYER_ENTERING_WORLD", function()
    Events.Debounce("character-snapshot-late", 8, CharacterProvider.Snapshot)
  end)
end
