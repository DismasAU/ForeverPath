-- Attunement chains through the Attune addon's data (read-only bridge).
--
-- Attune ships the chains as globals:
--   Attune_Data.attunes = { { ID, NAME, GROUP ("RAIDS"/"DUNGEONS"/...), FACTION, LEVELS, ICON, DESC, GROUPSIZE } }
--   Attune_Data.steps   = { { ID_ATTUNE, ID, TYPE, STEP, LOCATION, ID_WOWHEAD, ICON, FOLLOWS ("0" | "a&b"), STAGE, SIDE, COUNT } }
--   Attune_Data.quests  = { [questID] = { requiredLevel, groupSize } }
--   Attune_Data.npcs    = { [npcID] = { level, rank, name } }
--   AttuneLang["Q1_<questID>"] = quest name
--   Attune_DB.toons[charKey].done["<attune>-<step>"] = 1   (Attune's own survey, used for kills/interactions)
--
-- Progress is worked out from the client where it can be (quest flags, quest
-- log, level, bag counts) and from Attune's survey for the rest; a step is
-- also done when any step that follows it is done.
local _, ns = ...

local Compat = ns.Compat
local Log = ns.Log

local AttuneProvider = { cache = {} }
ns.AttuneProvider = AttuneProvider

AttuneProvider.TypeLabels = {
  Quest = "Quest", ["Pick Up"] = "Pick up", ["Turn In"] = "Turn in", Item = "Item", Kill = "Kill",
  Interact = "Talk to", Click = "Use", Level = "Level", Rep = "Reputation", Attune = "Attunement", End = "Attuned",
}
AttuneProvider.GroupOrder = { RAIDS = 1, DUNGEONS = 2 }

local function data()
  local d = _G.Attune_Data
  if type(d) == "table" and type(d.attunes) == "table" and type(d.steps) == "table" then return d end
  return nil
end

function AttuneProvider.IsAvailable()
  return data() ~= nil
end

function AttuneProvider.Faction()
  if type(UnitFactionGroup) == "function" then
    local ok, faction = pcall(UnitFactionGroup, "player")
    if ok and type(faction) == "string" then return faction end
  end
  return nil
end

local function lang(key, fallback)
  local l = _G.AttuneLang
  if type(l) == "table" then
    local value = rawget(l, key)
    if type(value) == "string" and value ~= key then return value end
    local ok, v = pcall(function() return l[key] end)
    if ok and type(v) == "string" and v ~= key then return v end
  end
  return fallback
end

local function normalizeAttune(raw)
  return {
    id = tostring(raw.ID), name = tostring(raw.NAME or ("Attunement " .. tostring(raw.ID))),
    group = tostring(raw.GROUP or ""), faction = raw.FACTION or "Both", levels = raw.LEVELS,
    icon = raw.ICON, desc = raw.DESC, groupSize = tonumber(raw.GROUPSIZE),
    class = type(raw.CLASS) == "string" and raw.CLASS ~= "" and string.upper(raw.CLASS) or nil,
  }
end

-- The player's class token ("SHAMAN"), or nil when the client cannot say.
function AttuneProvider.PlayerClass()
  if type(UnitClass) == "function" then
    local ok, _, file = pcall(UnitClass, "player")
    if ok and type(file) == "string" and file ~= "" then return string.upper(file) end
  end
  return nil
end

local function factionOK(raw, faction)
  return not faction or raw.FACTION == faction or raw.FACTION == "Both" or raw.FACTION == nil
end

local function classOK(raw, class)
  local wanted = type(raw.CLASS) == "string" and raw.CLASS ~= "" and string.upper(raw.CLASS) or nil
  return not wanted or not class or wanted == class
end

-- Attunements for a faction ("Alliance"/"Horde"; nil = all), raids first.
function AttuneProvider.List(faction)
  local d = data()
  local out = {}
  if not d then return out end
  faction = faction or AttuneProvider.Faction()
  for _, raw in ipairs(d.attunes) do
    if type(raw) == "table" and raw.ID and (not faction or raw.FACTION == faction or raw.FACTION == "Both" or raw.FACTION == nil) then
      out[#out + 1] = normalizeAttune(raw)
    end
  end
  table.sort(out, function(a, b)
    local ga = AttuneProvider.GroupOrder[string.upper(a.group)] or 9
    local gb = AttuneProvider.GroupOrder[string.upper(b.group)] or 9
    if ga ~= gb then return ga < gb end
    local la = tonumber(string.match(a.levels or "", "^(%d+)")) or 0
    local lb = tonumber(string.match(b.levels or "", "^(%d+)")) or 0
    if la ~= lb then return la < lb end
    return a.name < b.name
  end)
  return out
end

function AttuneProvider.Get(id)
  local d = data()
  if not d then return nil end
  id = tostring(id)
  for _, raw in ipairs(d.attunes) do
    if type(raw) == "table" and tostring(raw.ID) == id then return normalizeAttune(raw) end
  end
  return nil
end

-- Case-insensitive name match for the player's faction; exact name wins.
function AttuneProvider.Find(text, faction)
  if type(text) ~= "string" or text == "" then return nil end
  local needle = string.lower(text)
  local partial
  for _, attune in ipairs(AttuneProvider.List(faction)) do
    local name = string.lower(attune.name)
    if name == needle then return attune end
    if not partial and string.find(name, needle, 1, true) then partial = attune end
  end
  return partial
end

-- FOLLOWS = "a&b" (all of) where a part can be "x|y" (either of).
local function splitFollows(follows)
  local out = {}
  for part in string.gmatch(tostring(follows or "0"), "[^&]+") do
    if part ~= "0" and part ~= "" then out[#out + 1] = part end
  end
  return out
end

local function alternatives(part)
  local out = {}
  for id in string.gmatch(tostring(part), "[^|]+") do out[#out + 1] = id end
  return out
end

-- A predecessor part is satisfied when any of its alternatives is done
-- (an id no step carries never blocks).
local function followDone(byID, part)
  local known = false
  for _, id in ipairs(alternatives(part)) do
    local step = byID[id]
    if step then
      known = true
      if step.done then return true end
    end
  end
  return not known
end

local function stepName(step)
  if type(step.STEP) == "string" and step.STEP ~= "" and step.STEP ~= "Spacer" then return step.STEP end
  local t = step.TYPE
  local id = tostring(step.ID_WOWHEAD or "")
  if t == "Quest" or t == "Pick Up" or t == "Turn In" then
    local first = string.match(id, "^([^|]+)") or id
    return lang("Q1_" .. first, "Quest " .. first)
  elseif t == "Kill" or t == "Interact" or t == "Click" then
    local d = data()
    local npc = d and type(d.npcs) == "table" and d.npcs[tonumber(id)] or nil
    return type(npc) == "table" and tostring(npc[3] or ("NPC " .. id)) or ("NPC " .. id)
  elseif t == "Item" then
    return ns.ItemProvider and ns.ItemProvider.GetName(tonumber(id)) or ("Item " .. id)
  elseif t == "Level" then
    return "Reach level " .. id
  elseif t == "End" then
    return "Attuned"
  end
  return t or "Step"
end

-- Ordered steps of one attunement (Spacers dropped).
function AttuneProvider.Steps(id)
  local d = data()
  local out = {}
  if not d then return out end
  id = tostring(id)
  for _, raw in ipairs(d.steps) do
    if type(raw) == "table" and tostring(raw.ID_ATTUNE) == id and raw.TYPE ~= "Spacer" then
      local quest = (raw.TYPE == "Quest" or raw.TYPE == "Pick Up" or raw.TYPE == "Turn In") and type(d.quests) == "table"
        and d.quests[tonumber(string.match(tostring(raw.ID_WOWHEAD or ""), "^([^|]+)") or "")] or nil
      out[#out + 1] = {
        attuneID = id, id = tostring(raw.ID), key = id .. "-" .. tostring(raw.ID),
        type = raw.TYPE, typeLabel = AttuneProvider.TypeLabels[raw.TYPE] or raw.TYPE,
        name = stepName(raw), location = raw.LOCATION ~= "" and raw.LOCATION or nil,
        wowheadID = tostring(raw.ID_WOWHEAD or ""), icon = raw.ICON ~= "" and raw.ICON or nil,
        follows = splitFollows(raw.FOLLOWS), stage = tonumber(raw.STAGE) or 0, side = raw.SIDE == true,
        alternative = raw.OR == true,
        count = tonumber(raw.COUNT) or 1,
        questLevel = type(quest) == "table" and tonumber(quest[1]) or nil,
        groupSize = type(quest) == "table" and tonumber(quest[2]) or nil,
      }
    end
  end
  table.sort(out, function(a, b)
    if a.stage ~= b.stage then return a.stage < b.stage end
    return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
  end)
  return out
end

---------------------------------------------------------------------------
-- Progress
---------------------------------------------------------------------------
local function questIDs(step)
  local ids = {}
  for part in string.gmatch(step.wowheadID, "[^|]+") do
    local n = tonumber(part)
    if n then ids[#ids + 1] = n end
  end
  return ids
end

-- Attune's own survey for this character ("<attune>-<step>" = 1).
local function attuneSurvey()
  local db = _G.Attune_DB
  if type(db) ~= "table" or type(db.toons) ~= "table" then return nil end
  local name = type(UnitName) == "function" and select(1, UnitName("player")) or nil
  if not name then return nil end
  for key, toon in pairs(db.toons) do
    if type(key) == "string" and type(toon) == "table" and (key == name or string.find(key, "^" .. name:gsub("%p", "%%%0") .. "[ %-]")) then
      return type(toon.done) == "table" and toon.done or nil
    end
  end
  return nil
end

function AttuneProvider.DefaultContext()
  local survey = attuneSurvey()
  return {
    completedQuest = function(questID)
      if Compat.IsQuestFlaggedCompleted then
        local ok, done = pcall(Compat.IsQuestFlaggedCompleted, questID)
        return ok and done == true
      end
      return false
    end,
    onQuest = function(questID)
      if Compat.IsOnQuest then
        local ok, on = pcall(Compat.IsOnQuest, questID)
        return ok and on == true
      end
      return false
    end,
    level = (type(UnitLevel) == "function" and select(1, UnitLevel("player"))) or 0,
    itemCount = function(itemID)
      if ns.GoalCompletion then return ns.GoalCompletion.Count(itemID) end
      return 0
    end,
    surveyed = function(key) return survey ~= nil and survey[key] ~= nil end,
  }
end

-- Marks each step done/inLog and returns the summary:
--   { attune, steps, done, total, percent, current = { steps }, next = step, complete }
function AttuneProvider.Progress(id, ctx)
  local attune = AttuneProvider.Get(id)
  if not attune then return nil, "unknown attunement" end
  ctx = ctx or AttuneProvider.DefaultContext()
  local steps = AttuneProvider.Steps(id)
  local byID = {}
  for _, step in ipairs(steps) do byID[step.id] = step end

  for _, step in ipairs(steps) do
    local t = step.type
    step.done, step.inLog = false, false
    if t == "Quest" or t == "Turn In" or t == "Pick Up" then
      for _, questID in ipairs(questIDs(step)) do
        if ctx.completedQuest(questID) then step.done = true end
        if ctx.onQuest(questID) then step.inLog = true end
      end
      if t == "Pick Up" and step.inLog then step.done = true end
    elseif t == "Level" then
      step.done = (ctx.level or 0) >= (tonumber(step.wowheadID) or 0)
    elseif t == "Item" then
      step.done = ctx.itemCount(tonumber(step.wowheadID) or 0) >= step.count
    elseif t == "End" then
      step.done = false -- derived below
    else
      step.done = ctx.surveyed(step.key)
    end
  end

  -- End steps need every predecessor; anything a done step follows is done too.
  local changed = true
  local guard = 0
  while changed and guard < 50 do
    changed = false
    guard = guard + 1
    for _, step in ipairs(steps) do
      if step.type == "End" and not step.done then
        local all = #step.follows > 0
        for _, f in ipairs(step.follows) do
          if not followDone(byID, f) then all = false end
        end
        if all then step.done = true changed = true end
      end
      if step.done then
        for _, f in ipairs(step.follows) do
          -- An either/or predecessor cannot be inferred done: which branch was taken is unknown.
          local alts = alternatives(f)
          local prev = #alts == 1 and byID[alts[1]] or nil
          if prev and not prev.done then prev.done = true changed = true end
        end
      end
    end
  end

  local summary = { attune = attune, steps = steps, done = 0, total = 0, current = {}, complete = false }
  for _, step in ipairs(steps) do
    if step.type ~= "End" then
      summary.total = summary.total + 1
      if step.done then summary.done = summary.done + 1 end
    elseif step.done then
      summary.complete = true
    end
    if not step.done then
      local ready = true
      for _, f in ipairs(step.follows) do
        if not followDone(byID, f) then ready = false end
      end
      step.state = ready and "current" or "locked"
      if ready and step.type ~= "End" then summary.current[#summary.current + 1] = step end
    else
      step.state = "done"
    end
  end
  summary.percent = summary.total > 0 and math.floor(summary.done * 100 / summary.total + 0.5) or 0
  if summary.complete then summary.percent = 100 end
  -- Next: the first current main-line step, else the first current side step.
  for _, step in ipairs(summary.current) do
    if not step.side then summary.next = step break end
  end
  summary.next = summary.next or summary.current[1]
  return summary
end

---------------------------------------------------------------------------
-- Questlines: the part of an attunement that leads to one quest
---------------------------------------------------------------------------
local QUEST_TYPES = { Quest = true, ["Pick Up"] = true, ["Turn In"] = true }

local function stepHasQuest(raw, questID)
  if not QUEST_TYPES[raw.TYPE] then return false end
  for part in string.gmatch(tostring(raw.ID_WOWHEAD or ""), "[^|]+") do
    if tonumber(part) == questID then return true end
  end
  return false
end

-- Attunements whose chain includes questID, for the player's faction and
-- class (both default to the character's): { { attune, stepID } }, the
-- step being the last one that references the quest (its turn-in when the
-- chain splits pick-up and turn-in). Class chains come first.
function AttuneProvider.AttunementsWithQuest(questID, faction, class)
  local d = data()
  questID = tonumber(questID)
  if not d or not questID then return {} end
  faction = faction or AttuneProvider.Faction()
  class = class or AttuneProvider.PlayerClass()
  local byID = {}
  for _, raw in ipairs(d.attunes) do
    if type(raw) == "table" and raw.ID then byID[tostring(raw.ID)] = raw end
  end
  local found, order = {}, {}
  for _, raw in ipairs(d.steps) do
    if type(raw) == "table" and stepHasQuest(raw, questID) then
      local attuneRaw = byID[tostring(raw.ID_ATTUNE)]
      if attuneRaw and factionOK(attuneRaw, faction) and classOK(attuneRaw, class) then
        local key = tostring(raw.ID_ATTUNE)
        local hit = found[key]
        if not hit then
          hit = { attune = normalizeAttune(attuneRaw), stepID = tostring(raw.ID), stage = tonumber(raw.STAGE) or 0 }
          found[key] = hit
          order[#order + 1] = hit
        elseif (tonumber(raw.STAGE) or 0) >= hit.stage then
          hit.stepID, hit.stage = tostring(raw.ID), tonumber(raw.STAGE) or 0
        end
      end
    end
  end
  table.sort(order, function(a, b)
    local ca, cb = a.attune.class and 0 or 1, b.attune.class and 0 or 1
    if ca ~= cb then return ca < cb end
    return a.attune.id < b.attune.id
  end)
  return order
end

-- The chain that leads to questID: every step the quest's step follows
-- (transitively) plus the step itself, in chain order, with live progress.
-- { attune, steps, target, next, done, total, percent, complete }, or nil
-- when no attunement for this faction and class includes the quest.
function AttuneProvider.QuestlineFor(questID, opts)
  opts = opts or {}
  local hits = AttuneProvider.AttunementsWithQuest(questID, opts.faction, opts.class)
  local hit = hits[1]
  if not hit then return nil end
  local progress = AttuneProvider.Progress(hit.attune.id, opts.ctx)
  if not progress then return nil end
  local byID = {}
  for _, step in ipairs(progress.steps) do byID[step.id] = step end
  local target = byID[hit.stepID]
  if not target then return nil end
  local wanted = {}
  local function mark(step)
    if wanted[step.id] then return end
    wanted[step.id] = true
    for _, f in ipairs(step.follows) do
      for _, id in ipairs(alternatives(f)) do
        if byID[id] then mark(byID[id]) end
      end
    end
  end
  mark(target)
  -- Either/or stages ("Call of Air" from one of two givers): once a branch
  -- is done the untaken alternatives leave the line.
  local doneStage = {}
  for _, step in ipairs(progress.steps) do
    if wanted[step.id] and step.alternative and step.done then doneStage[step.stage] = true end
  end
  local line = { attune = hit.attune, steps = {}, target = target, done = 0, total = 0, complete = target.done == true }
  for _, step in ipairs(progress.steps) do
    if wanted[step.id] and step.type ~= "End" and not (step.alternative and not step.done and doneStage[step.stage]) then
      line.steps[#line.steps + 1] = step
      line.total = line.total + 1
      if step.done then line.done = line.done + 1 end
      if not line.next and step.state == "current" then line.next = step end
    end
  end
  line.percent = line.total > 0 and math.floor(line.done * 100 / line.total + 0.5) or 0
  if line.complete then line.percent = 100 end
  return line
end

-- "Quest: Jail Break - Blackrock Depths"
function AttuneProvider.StepText(step)
  if not step then return nil end
  local text = step.typeLabel .. ": " .. step.name
  if step.type == "Item" and step.count > 1 then text = text .. " x" .. step.count end
  if step.location then text = text .. " - " .. step.location end
  return text
end

function AttuneProvider.Status()
  if not AttuneProvider.IsAvailable() then return "Attune not installed" end
  return string.format("Attune: %d attunements for %s", #AttuneProvider.List(), AttuneProvider.Faction() or "all factions")
end

function AttuneProvider.Init()
  Log.Debug("Attune bridge: %s", AttuneProvider.Status())
end
