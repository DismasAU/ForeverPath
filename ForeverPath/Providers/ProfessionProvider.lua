-- Profession and recipe data through C_TradeSkillUI.
--
-- The client only enumerates recipes (GetAllRecipeIDs) while a profession
-- window is open, so recipes are captured whenever the player opens one and
-- cached in ForeverPathDB.recipes (shared data) plus ForeverPathCharDB.knownRecipes
-- (per character "learned" flags). Later lookups use the cache and re-read the
-- schematic live when the API answers, so reagent lists stay current.
--
-- Scans are processed in chunks across frames to avoid a hitch on large lists.
local _, ns = ...

local Compat = ns.Compat
local Util = ns.Util
local Log = ns.Log
local Events = ns.Events
local RecipeModel = ns.RecipeModel

local ProfessionProvider = {
  scan = nil,          -- state of the scan in progress
  scanToken = 0,
  announced = {},      -- professionID -> true once a chat summary was shown this session
  scanQueue = nil,     -- professions still to open for /fp scan
  openedByUs = false,
}
ns.ProfessionProvider = ProfessionProvider

local CHUNK_SIZE = 40
local QUEUE_TIMEOUT = 8

local function api(name, ...)
  if type(C_TradeSkillUI) ~= "table" then
    return nil
  end
  local fn = C_TradeSkillUI[name]
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a, b = pcall(fn, ...)
  if not ok then
    Log.Debug("C_TradeSkillUI.%s failed: %s", name, tostring(a))
    return nil
  end
  return a, b
end

function ProfessionProvider.IsAvailable()
  return Compat.hasTradeSkillUI == true
end

function ProfessionProvider.HasScanData()
  return ns.chardb ~= nil and next(ns.chardb.professions) ~= nil
end

function ProfessionProvider.GetScannedProfessions()
  local list = {}
  if not ns.chardb then
    return list
  end
  for professionID, p in pairs(ns.chardb.professions) do
    list[#list + 1] = {
      professionID = professionID,
      name = p.name,
      skillLevel = p.skillLevel,
      maxSkillLevel = p.maxSkillLevel,
      scannedAt = p.scannedAt,
      recipeCount = p.recipeCount,
      learnedCount = p.learnedCount,
    }
  end
  table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
  return list
end

function ProfessionProvider.IsLearned(recipeID)
  return ns.chardb ~= nil and ns.chardb.knownRecipes[recipeID] == true
end

-- All cached recipes that produce itemID, with this character's learned flag.
function ProfessionProvider.FindRecipesForItem(itemID)
  local out = {}
  if not ns.db then
    return out
  end
  local ids = ns.db.itemRecipes[itemID]
  if type(ids) ~= "table" then
    return out
  end
  for recipeID in pairs(ids) do
    local recipe = ns.db.recipes[recipeID]
    if recipe then
      out[#out + 1] = { recipe = recipe, learned = ProfessionProvider.IsLearned(recipeID) }
    end
  end
  table.sort(out, function(a, b) return a.recipe.recipeID < b.recipe.recipeID end)
  return out
end

-- Returns recipe, isLive. With refresh=true the schematic is re-read from the
-- API; an empty answer (window closed, data not loaded) keeps the cached copy.
function ProfessionProvider.GetRecipe(recipeID, refresh)
  local cached = ns.db and ns.db.recipes[recipeID] or nil
  if refresh and ProfessionProvider.IsAvailable() then
    local schematic = api("GetRecipeSchematic", recipeID, false)
    if type(schematic) == "table" and type(schematic.reagentSlotSchematics) == "table" and #schematic.reagentSlotSchematics > 0 then
      local fresh = RecipeModel.FromSchematic(schematic, nil, {
        basicReagentType = Compat.reagentTypeBasic,
        now = cached and cached.scannedAt or nil,
        isEnchant = ns.Data and ns.Data.Recipes and ns.Data.Recipes.IsEnchant or nil,
      })
      if fresh and #fresh.reagents > 0 then
        fresh = RecipeModel.Merge(cached, fresh)
        if ns.db then
          ns.db.recipes[recipeID] = fresh
        end
        return fresh, true
      end
    end
  end
  return cached, false
end

-- Professions from the spell book (name, skill levels, skillLine id).
function ProfessionProvider.GetCharacterProfessions()
  local list = {}
  if not Compat.hasProfessionList then
    return list
  end
  local ok, a, b, c, d, e, f = pcall(GetProfessions)
  if not ok then
    return list
  end
  local indices = { a, b, c, d, e, f }
  for slot = 1, 6 do
    local index = indices[slot]
    if index then
      local ok2, name, icon, skillLevel, maxSkillLevel, _, _, skillLine = pcall(GetProfessionInfo, index)
      if ok2 and name then
        list[#list + 1] = {
          name = name, icon = icon, skillLevel = skillLevel, maxSkillLevel = maxSkillLevel,
          skillLine = skillLine, slot = slot,
        }
      end
    end
  end
  return list
end

local function currentProfessionInfo()
  local info = api("GetChildProfessionInfo")
  if type(info) ~= "table" or not info.professionID or info.professionID == 0 then
    info = api("GetBaseProfessionInfo")
  end
  if type(info) ~= "table" or not info.professionID or info.professionID == 0 then
    return nil
  end
  return info
end

-- Starts scanning the profession currently shown in the tradeskill window.
-- Returns true when a scan started, otherwise false plus a reason.
function ProfessionProvider.ScanOpenProfession()
  if not ProfessionProvider.IsAvailable() or not ns.db or not ns.chardb then
    return false, "unavailable"
  end
  if api("IsNPCCrafting") then
    return false, "npc crafting"
  end
  if api("IsTradeSkillGuild") then
    return false, "guild view"
  end
  if api("IsTradeSkillLinked") then
    return false, "linked profession"
  end
  local info = currentProfessionInfo()
  if not info then
    return false, "no profession open"
  end
  local ids = api("GetAllRecipeIDs")
  if type(ids) ~= "table" or #ids == 0 then
    ids = api("GetFilteredRecipeIDs")
  end
  if type(ids) ~= "table" or #ids == 0 then
    return false, "recipe list empty"
  end

  local parentID = info.parentProfessionID
  local professionID = (type(parentID) == "number" and parentID ~= 0) and parentID or info.professionID
  local name = info.parentProfessionName or info.professionName or ("Profession " .. tostring(professionID))

  ProfessionProvider.scanToken = ProfessionProvider.scanToken + 1
  ProfessionProvider.scan = {
    token = ProfessionProvider.scanToken,
    professionID = professionID,
    childProfessionID = info.professionID,
    name = name,
    skillLevel = info.skillLevel,
    maxSkillLevel = info.maxSkillLevel,
    ids = ids,
    index = 1,
    count = 0,
    learned = 0,
    skipped = 0,
    startedAt = Util.Now(),
  }
  Log.Debug("Scanning %s: %d recipe ids", name, #ids)
  ProfessionProvider.ProcessScanChunk(ProfessionProvider.scanToken)
  return true
end

local function scheduleChunk(token)
  if Compat.After then
    Compat.After(0, function()
      Log.Call(ProfessionProvider.ProcessScanChunk, token)
    end)
  else
    ProfessionProvider.ProcessScanChunk(token)
  end
end

function ProfessionProvider.ProcessScanChunk(token)
  local state = ProfessionProvider.scan
  if not state or state.token ~= token then
    return
  end
  local last = math.min(state.index + CHUNK_SIZE - 1, #state.ids)
  local now = Util.Now()
  for i = state.index, last do
    local recipeID = state.ids[i]
    local recipeInfo = api("GetRecipeInfo", recipeID)
    local schematic = api("GetRecipeSchematic", recipeID, false)
    local recipe = RecipeModel.FromSchematic(schematic, recipeInfo, {
      professionID = state.professionID,
      professionName = state.name,
      basicReagentType = Compat.reagentTypeBasic,
      now = now,
      isEnchant = ns.Data and ns.Data.Recipes and ns.Data.Recipes.IsEnchant or nil,
    })
    -- A recipe without reagents means the schematic was not fully loaded;
    -- keep whatever we had rather than storing an empty reagent list.
    if recipe and #recipe.reagents > 0 then
      ns.db.recipes[recipeID] = RecipeModel.Merge(ns.db.recipes[recipeID], recipe)
      -- Enchants make no item: they are found by spell id, never by output.
      if recipe.outputItemID then
        local index = ns.db.itemRecipes[recipe.outputItemID]
        if not index then
          index = {}
          ns.db.itemRecipes[recipe.outputItemID] = index
        end
        index[recipeID] = true
        ns.ItemProvider.Prefetch(recipe.outputItemID)
      else
        state.enchants = (state.enchants or 0) + 1
      end
      local learned = (type(recipeInfo) == "table" and recipeInfo.learned) and true or false
      ns.chardb.knownRecipes[recipeID] = learned
      state.count = state.count + 1
      if learned then
        state.learned = state.learned + 1
      end
    else
      state.skipped = state.skipped + 1
    end
  end
  state.index = last + 1
  if state.index <= #state.ids then
    scheduleChunk(token)
  else
    ProfessionProvider.FinishScan(state)
  end
end

function ProfessionProvider.FinishScan(state)
  if ProfessionProvider.scan ~= state then
    return
  end
  ProfessionProvider.scan = nil
  if state.count == 0 then
    Log.Debug("Scan of %s produced no recipes (%d skipped)", state.name, state.skipped)
    return
  end
  ns.chardb.professions[state.professionID] = {
    name = state.name,
    childProfessionID = state.childProfessionID,
    skillLevel = state.skillLevel,
    maxSkillLevel = state.maxSkillLevel,
    scannedAt = Util.Now(),
    recipeCount = state.count,
    learnedCount = state.learned,
  }
  if not ProfessionProvider.announced[state.professionID] then
    ProfessionProvider.announced[state.professionID] = true
    Log.Print("Recorded %s: %d recipes%s (%d learned).", state.name, state.count,
      (state.enchants or 0) > 0 and string.format(" (%d enchants)", state.enchants) or "", state.learned)
  else
    Log.Debug("Rescanned %s: %d recipes (%d learned, %d skipped)", state.name, state.count, state.learned, state.skipped)
  end
  Events.Fire("FP_RECIPES_UPDATED", state.professionID)
  if ProfessionProvider.scanQueue then
    ProfessionProvider.waitingFor = nil
    if Compat.After then
      Compat.After(0.5, function() Log.Call(ProfessionProvider.NextQueuedScan) end)
    else
      ProfessionProvider.NextQueuedScan()
    end
  end
end

local function isScanned(profession)
  if not ns.chardb then
    return false
  end
  if profession.skillLine and ns.chardb.professions[profession.skillLine] then
    return true
  end
  for _, p in pairs(ns.chardb.professions) do
    if p.name == profession.name then
      return true
    end
  end
  return false
end

-- /fp scan: opens each unscanned profession window so the list update event
-- triggers a scan. Whether OpenTradeSkill works from addon code on Forever is
-- not verified; failures fall back to asking the player to open windows manually.
function ProfessionProvider.RequestScan(force)
  if not ProfessionProvider.IsAvailable() then
    Log.Print("The profession API (C_TradeSkillUI) is not available on this client.")
    return false
  end
  if not Compat.hasProfessionList or type(C_TradeSkillUI.OpenTradeSkill) ~= "function" then
    Log.Print("Open each profession window once; ForeverPath records recipes whenever a window is open.")
    return false
  end
  local queue = {}
  for _, profession in ipairs(ProfessionProvider.GetCharacterProfessions()) do
    if profession.skillLine and (force or not isScanned(profession)) then
      queue[#queue + 1] = profession
    end
  end
  if #queue == 0 then
    Log.Print("All professions are already recorded. Use /fp scan all to rescan.")
    return true
  end
  ProfessionProvider.scanQueue = queue
  ProfessionProvider.openedByUs = false
  ProfessionProvider.NextQueuedScan()
  return true
end

function ProfessionProvider.NextQueuedScan()
  local queue = ProfessionProvider.scanQueue
  if not queue or #queue == 0 then
    ProfessionProvider.scanQueue = nil
    if ProfessionProvider.openedByUs then
      ProfessionProvider.openedByUs = false
      api("CloseTradeSkill")
    end
    return
  end
  local profession = table.remove(queue, 1)
  Events.RunOutOfCombat(function()
    local opened = api("OpenTradeSkill", profession.skillLine)
    if opened then
      ProfessionProvider.openedByUs = true
      ProfessionProvider.waitingFor = profession.skillLine
      Log.Print("Opening %s to record its recipes...", profession.name)
      if Compat.After then
        local expected = profession.skillLine
        Compat.After(QUEUE_TIMEOUT, function()
          if ProfessionProvider.waitingFor == expected then
            Log.Print("No recipe list arrived for %s. Open the window manually to record it.", profession.name)
            ProfessionProvider.waitingFor = nil
            Log.Call(ProfessionProvider.NextQueuedScan)
          end
        end)
      end
    else
      Log.Print("Could not open %s automatically. Open it manually to record its recipes.", profession.name)
      ProfessionProvider.NextQueuedScan()
    end
  end)
end

local function onTradeSkillUpdate()
  Events.Debounce("profession-scan", 0.5, function()
    local ok, reason = ProfessionProvider.ScanOpenProfession()
    if not ok then
      Log.Debug("Profession scan skipped: %s", tostring(reason))
    end
  end)
end

function ProfessionProvider.Init()
  if not ProfessionProvider.IsAvailable() then
    Log.Debug("C_TradeSkillUI missing; profession provider disabled")
    return
  end
  Events.RegisterWoW("TRADE_SKILL_LIST_UPDATE", onTradeSkillUpdate)
  Events.RegisterWoW("TRADE_SKILL_SHOW", onTradeSkillUpdate)
  Events.RegisterWoW("TRADE_SKILL_DATA_SOURCE_CHANGED", onTradeSkillUpdate)
  Events.RegisterWoW("NEW_RECIPE_LEARNED", function(recipeID)
    if ns.chardb and Util.IsPositiveInt(recipeID) then
      ns.chardb.knownRecipes[recipeID] = true
      Events.Fire("FP_RECIPES_UPDATED", nil)
    end
  end)
end
