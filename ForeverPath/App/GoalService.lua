-- Application service shared by the UI and slash commands: owns the GoalStore
-- instance bound to the character database and turns player input into goals.
local _, ns = ...

local GoalStore = ns.GoalStore
local GoalModel = ns.GoalModel
local ItemProvider = ns.ItemProvider
local Events = ns.Events
local Util = ns.Util

local GoalService = {}
ns.GoalService = GoalService

-- Open goals as a character snapshot records them (for alts' cards).
function GoalService.OpenGoalSummaries()
  local out = {}
  for _, goal in ipairs(GoalService.List({ open = true })) do
    out[#out + 1] = { id = goal.id, title = GoalService.Title(goal), status = goal.status, itemID = goal.target and goal.target.itemID }
  end
  return out
end

function GoalService.Init()
  ns.CharacterProvider.SetGoalSource(GoalService.OpenGoalSummaries)
  if not ns.chardb then
    return nil
  end
  ns.goals = GoalStore.New(ns.chardb, {
    onChange = function(event, goal)
      Events.Fire("FP_GOALS_CHANGED", event, goal)
    end,
  })
  if ns.goals.dropped > 0 then
    ns.Log.Print("Dropped %d malformed saved goal(s).", ns.goals.dropped)
  end
  return ns.goals
end

function GoalService.Store()
  if not ns.goals and ns.chardb then
    GoalService.Init()
  end
  return ns.goals
end

-- The existing goal of `goalType` aimed at target[field] == value, if any.
local function findGoal(goalType, field, value, normalize)
  local store = GoalService.Store()
  return store and store:FindByTarget(goalType, field, value, normalize) or nil
end

local LOADING = "ForeverPath is still loading."

-- An Add* call for a goal that already exists: retarget it (update(goal,
-- reopening) -> ok, err, when given), reopen it if it was completed, select
-- it. Returns goal, message, false, or nil, err when the update is refused.
local function reuseGoal(store, existing, update)
  local reopening = not GoalModel.IsOpen(existing)
  if update then
    local ok, err = update(existing, reopening)
    if not ok then return nil, err end
  end
  if reopening then store:SetStatus(existing.id, GoalModel.Statuses.ACTIVE) end
  store:Select(existing.id)
  return existing, string.format("%s: %s", update and "Updated goal" or "Already a goal", GoalService.Title(existing)), false
end

-- Creates and selects a goal. Returns goal, message, true, or nil, error.
local function createGoal(store, goalType, target)
  local goal, err = store:Create(goalType, target)
  if not goal then return nil, err end
  store:Select(goal.id)
  return goal, string.format("Added goal: %s", GoalService.Title(goal)), true
end

-- " (using <first>; also matched: <rest>)" when a name search hit several
-- entries, else "". chosen and other describe a hit.
local function matchNote(hits, chosen, other)
  if #hits < 2 then return "" end
  local others = {}
  for i = 2, #hits do others[#others + 1] = other(hits[i]) end
  return string.format(" (using %s; also matched: %s)", chosen(hits[1]), Util.Join(others))
end
local function hitName(hit) return hit.name end

-- Goal input grammar shared by the *FromInput functions and Suggest, so a
-- suggestion is offered for exactly what Enter accepts.

-- "Tailoring 225", "225 Tailoring" or "Tailoring" -> name, rank or nil.
local function parseSkillInput(text)
  local name, rank = text:match("^(.-)%s+(%d+)$")
  if not name then rank, name = text:match("^(%d+)%s+(.-)$") end
  return Util.Trim(name or text), rank and tonumber(rank) or nil
end

-- "Argent Dawn Exalted", "Exalted Argent Dawn" or "Argent Dawn" -> name,
-- standing or nil.
local function parseReputationInput(text, RP)
  local head, tail = text:match("^(.-)%s+(%a+)$")
  if head and RP.StandingByName(tail) then return Util.Trim(head), RP.StandingByName(tail) end
  local first, rest = text:match("^(%a+)%s+(.-)$")
  if first and RP.StandingByName(first) then return Util.Trim(rest), RP.StandingByName(first) end
  return text, nil
end

function GoalService.Title(goal)
  return GoalModel.Title(goal, ItemProvider.GetCachedName)
end

function GoalService.Name(goal)
  return GoalModel.Name(goal, ItemProvider.GetCachedName)
end

-- Goal type for an item: crafting when any recipe (recorded or catalogue)
-- produces it, otherwise obtaining it (drop, vendor, quest, alt...). Without
-- the catalogue and before any profession has been scanned nothing is known
-- either way, so goals stay crafting goals and the planner asks for a scan.
function GoalService.TypeForItem(itemID)
  local candidates = ns.Log.Try(ns.ProfessionProvider.FindRecipesForItem, itemID)
  if type(candidates) == "table" and #candidates > 0 then return GoalModel.TypeIDs.CRAFT_ITEM end
  local catalogue = ns.Data.Recipes
  if catalogue and catalogue.Lookup then
    local hints = catalogue.Lookup(itemID)
    if type(hints) == "table" and #hints > 0 then return GoalModel.TypeIDs.CRAFT_ITEM end
  end
  local haveCatalogue = catalogue and catalogue.IsAvailable and catalogue.IsAvailable()
  if not haveCatalogue and not ns.ProfessionProvider.HasScanData() then
    return GoalModel.TypeIDs.CRAFT_ITEM
  end
  return GoalModel.TypeIDs.OBTAIN_ITEM
end

-- Creates or updates an item goal. goalType defaults to TypeForItem; an
-- existing goal for the item is updated whatever its type.
-- Returns goal, message, isNew.
function GoalService.AddItemGoal(itemID, quantity, goalType)
  local store = GoalService.Store()
  if not store then return nil, LOADING end
  quantity = Util.IsPositiveInt(quantity) and quantity or 1
  local explicit = goalType
  goalType = goalType or GoalService.TypeForItem(itemID)
  local existing = GoalService.FindItemGoal(itemID)
  if existing then
    return reuseGoal(store, existing, function(goal)
      if explicit and goal.type ~= explicit then
        local ok, err = store:SetType(goal.id, explicit)
        if not ok then return false, err end
      end
      return store:SetQuantity(goal.id, quantity)
    end)
  end
  ItemProvider.Prefetch(itemID)
  return createGoal(store, goalType, { itemID = itemID, quantity = quantity })
end

-- Attune ids arrive as numbers or strings; compare them as strings.
function GoalService.FindAttunementGoal(attuneID)
  return findGoal(GoalModel.TypeIDs.COMPLETE_ATTUNEMENT, "attuneID", attuneID, tostring)
end

-- Creates (or selects) an attunement goal from an Attune id. Returns goal, message, isNew.
function GoalService.AddAttunementGoal(attuneID)
  local store = GoalService.Store()
  if not store then return nil, LOADING end
  local attune = ns.AttuneProvider.Get(attuneID)
  if not attune then
    return nil, ns.AttuneProvider.IsAvailable() and "Unknown attunement." or "Attunement goals need the Attune addon."
  end
  local existing = GoalService.FindAttunementGoal(attune.id)
  if existing then return reuseGoal(store, existing) end
  return createGoal(store, GoalModel.TypeIDs.COMPLETE_ATTUNEMENT, { attuneID = attune.id, name = attune.name, icon = attune.icon })
end

-- Attunement goal from free text (name, for the player's faction).
function GoalService.AddAttunementFromInput(text)
  if not ns.AttuneProvider.IsAvailable() then
    return nil, "Attunement goals need the Attune addon installed and enabled."
  end
  local attune = ns.AttuneProvider.Find(Util.Trim(text or ""))
  if not attune then
    return nil, string.format("No attunement called \"%s\" for your faction. /fp attunements lists them.", Util.Trim(text or ""))
  end
  return GoalService.AddAttunementGoal(attune.id)
end

---------------------------------------------------------------------------
-- Learn-recipe goals
---------------------------------------------------------------------------
function GoalService.FindRecipeGoal(spellID)
  return findGoal(GoalModel.TypeIDs.LEARN_RECIPE, "spellID", spellID)
end


-- Creates (or selects) a learn-recipe goal for a recipe spell id. Returns goal, message, isNew.
function GoalService.AddRecipeGoal(spellID)
  local store = GoalService.Store()
  if not store then return nil, LOADING end
  local recipe = ns.Planner.RecipeByID(spellID)
  if not recipe then
    return nil, string.format("No recipe with spell id %s is known (catalogue or recorded professions).", tostring(spellID))
  end
  if recipe.combine then
    return nil, string.format("%s is an item-use combine: anyone can do it, there is nothing to learn.", recipe.name or "That")
  end
  local existing = GoalService.FindRecipeGoal(spellID)
  if existing then return reuseGoal(store, existing) end
  if recipe.teachItemID then ItemProvider.Prefetch(recipe.teachItemID) end
  return createGoal(store, GoalModel.TypeIDs.LEARN_RECIPE, {
    spellID = spellID, name = recipe.name, professionName = recipe.professionName, professionID = recipe.professionID, icon = recipe.icon,
  })
end

-- Spell id from an enchant or spell link (Shift-click in a profession
-- window or the spellbook), or "enchant:1234" / "spell:1234" text.
function GoalService.SpellIDFromText(text)
  if type(text) ~= "string" then return nil end
  local id = text:match("|Henchant:(%d+)") or text:match("|Hspell:(%d+)")
    or text:match("^%s*[Ee][Nn][Cc][Hh][Aa][Nn][Tt]:(%d+)%s*$") or text:match("^%s*[Ss][Pp][Ee][Ll][Ll]:(%d+)%s*$")
  return id and tonumber(id) or nil
end

-- Learn-recipe goal from free text: a spell id or link, or a recipe name
-- searched in the catalogue (exact name first). Returns goal, message, isNew.
function GoalService.AddRecipeFromInput(text)
  text = Util.Trim(text or "")
  if text == "" then
    return nil, "Type a recipe name (or its spell id)."
  end
  local spellID = GoalService.SpellIDFromText(text) or Util.ParseInt(text)
  local note = ""
  if not spellID then
    local catalogue = ns.Data.Recipes
    local hits = catalogue and catalogue.Search and catalogue.Search(text, 5) or {}
    if #hits == 0 then
      return nil, string.format("No recipe called \"%s\" is in the catalogue.", text)
    end
    spellID = hits[1].spellID
    note = matchNote(hits, function(hit) return hit.name .. " - " .. (hit.professionName or "?") end,
      function(hit) return hit.name .. " (" .. (hit.professionName or "?") .. ")" end)
  end
  local goal, message, isNew = GoalService.AddRecipeGoal(spellID)
  if not goal then
    return nil, message
  end
  return goal, message .. note, isNew
end

---------------------------------------------------------------------------
-- Enchant goals
---------------------------------------------------------------------------
function GoalService.FindEnchantGoal(spellID)
  return findGoal(GoalModel.TypeIDs.APPLY_ENCHANT, "spellID", spellID)
end

-- Creates (or updates) an enchant goal: cast the enchant `quantity` times.
-- Returns goal, message, isNew.
function GoalService.AddEnchantGoal(spellID, quantity)
  local store = GoalService.Store()
  if not store then return nil, LOADING end
  local recipe = ns.Planner.RecipeByID(spellID)
  if not recipe then
    return nil, string.format("No enchant with spell id %s is known (catalogue or recorded professions).", tostring(spellID))
  end
  if not recipe.enchant then
    return nil, string.format("%s makes an item: add it as a crafting goal (Shift-click the item, or /fp add).", recipe.name or "That recipe")
  end
  quantity = Util.IsPositiveInt(quantity) and quantity or 1
  local existing = GoalService.FindEnchantGoal(spellID)
  if existing then
    return reuseGoal(store, existing, function(goal) return store:SetQuantity(goal.id, quantity) end)
  end
  if recipe.teachItemID then ItemProvider.Prefetch(recipe.teachItemID) end
  return createGoal(store, GoalModel.TypeIDs.APPLY_ENCHANT, {
    spellID = spellID, name = recipe.name, professionName = recipe.professionName, professionID = recipe.professionID, icon = recipe.icon,
    quantity = quantity, casts = 0,
  })
end

-- Enchant goal from free text: an enchant or spell link, a spell id, or an
-- enchant name searched in the catalogue. Returns goal, message, isNew.
function GoalService.AddEnchantFromInput(text, quantity)
  text = Util.Trim(text or "")
  if text == "" then
    return nil, "Type an enchant name (Enchant Weapon - Crusader), or Shift-click it in your Enchanting window."
  end
  local spellID = GoalService.SpellIDFromText(text) or Util.ParseInt(text)
  local note = ""
  if not spellID then
    local catalogue = ns.Data.Recipes
    local hits = catalogue and catalogue.Search and catalogue.Search(text, 5, nil, "enchant") or {}
    if #hits == 0 then
      return nil, string.format("No enchant called \"%s\" is in the catalogue.", text)
    end
    spellID = hits[1].spellID
    note = matchNote(hits, hitName, hitName)
  end
  local goal, message, isNew = GoalService.AddEnchantGoal(spellID, quantity)
  if not goal then
    return nil, message
  end
  return goal, message .. note, isNew
end

---------------------------------------------------------------------------
-- Reach-skill goals
---------------------------------------------------------------------------
function GoalService.FindSkillGoal(professionName)
  return findGoal(GoalModel.TypeIDs.REACH_SKILL, "professionName", professionName)
end

-- The next classic cap above the current one (75, 150, 225, 300), or the
-- current cap when it is not reached yet.
function GoalService.NextSkillTarget(standing)
  if not standing then return 75 end
  local current, max = standing.skillLevel or 0, standing.maxSkillLevel or 0
  if max > current then return max end
  local next = (math.floor(max / 75) + 1) * 75
  return math.max(next, current + 1)
end

-- Creates (or updates) a reach-skill goal. rank defaults to the next cap.
-- Returns goal, message, isNew.
function GoalService.AddSkillGoal(professionName, rank)
  local store = GoalService.Store()
  if not store then return nil, LOADING end
  local catalogue = ns.Data.Recipes
  local professionID, canonical
  if catalogue and catalogue.FindProfession then
    professionID, canonical = catalogue.FindProfession(professionName)
  end
  local standing = ns.Planner.CurrentSkill(canonical or professionName, professionID)
  if not canonical then
    -- Not a catalogue profession: accept it when the character has it (e.g. a secondary skill).
    if standing then canonical = standing.name else
      return nil, string.format("No profession called \"%s\".", tostring(professionName))
    end
  end
  rank = Util.ParseInt(rank) or GoalService.NextSkillTarget(standing)
  local existing = GoalService.FindSkillGoal(canonical)
  if existing then
    return reuseGoal(store, existing, function(goal, reopening)
      local ok, err = store:SetRank(goal.id, rank)
      if ok and reopening then goal.target.startRank = standing and standing.skillLevel or goal.target.startRank end
      return ok, err
    end)
  end
  local goal, message, isNew = createGoal(store, GoalModel.TypeIDs.REACH_SKILL, {
    professionID = professionID, professionName = canonical, rank = rank,
    startRank = standing and standing.skillLevel or nil, icon = standing and standing.icon or nil,
  })
  if goal and not standing then
    message = message .. string.format(" (%s is not one of this character's professions yet)", canonical)
  end
  return goal, message, isNew
end

-- "Tailoring 225", "tailoring", "225 Tailoring". Returns goal, message, isNew.
function GoalService.AddSkillFromInput(text)
  text = Util.Trim(text or "")
  if text == "" then
    return nil, "Type a profession, optionally with the skill to reach (Tailoring 225)."
  end
  return GoalService.AddSkillGoal(parseSkillInput(text))
end

function GoalService.SetRank(id, rank)
  local store = GoalService.Store()
  if not store then return false, "not loaded" end
  return store:SetRank(id, rank)
end

---------------------------------------------------------------------------
-- Quest goals
---------------------------------------------------------------------------
function GoalService.FindQuestGoal(questID)
  return findGoal(GoalModel.TypeIDs.COMPLETE_QUEST, "questID", questID)
end

-- Creates (or selects) a quest goal. Returns goal, message, isNew.
function GoalService.AddQuestGoal(questID)
  local store = GoalService.Store()
  if not store then return nil, LOADING end
  local QP = ns.QuestProvider
  if not QP or not QP.IsAvailable() then
    return nil, "Quest goals need the quest API (C_QuestLog), which this client lacks."
  end
  local existing = GoalService.FindQuestGoal(questID)
  if existing then return reuseGoal(store, existing) end
  local entry = QP.Get(questID)
  for _, reward in ipairs(entry and entry.rewards or {}) do ItemProvider.Prefetch(reward.itemID) end
  return createGoal(store, GoalModel.TypeIDs.COMPLETE_QUEST, {
    questID = questID, name = QP.Name(questID), level = entry and entry.level or nil, instance = entry and entry.instance or nil, icon = QP.ICON,
  })
end

-- Quest goal from free text: a quest id, or a name searched in the known
-- quests (dungeon and attunement quests, and your quest log). Returns goal, message, isNew.
function GoalService.AddQuestFromInput(text)
  text = Util.Trim(text or "")
  if text == "" then
    return nil, "Type a quest name (or its id)."
  end
  local QP = ns.QuestProvider
  if not QP or not QP.IsAvailable() then
    return nil, "Quest goals need the quest API (C_QuestLog), which this client lacks."
  end
  local questID = Util.ParseInt(text)
  local note = ""
  if not questID then
    local hits = QP.Search(text, 5)
    if #hits == 0 then
      return nil, string.format("No quest called \"%s\" is known (dungeon quests, attunement quests, your quest log).", text)
    end
    questID = hits[1].questID
    note = matchNote(hits, function(hit) return hit.name .. " - " .. (hit.where or "?") end, hitName)
  end
  local goal, message, isNew = GoalService.AddQuestGoal(questID)
  if not goal then
    return nil, message
  end
  return goal, message .. note, isNew
end

---------------------------------------------------------------------------
-- Reputation goals
---------------------------------------------------------------------------
function GoalService.FindReputationGoal(factionID)
  return findGoal(GoalModel.TypeIDs.REACH_REPUTATION, "factionID", factionID)
end

-- Creates (or retargets) a reputation goal. standing defaults to the next one up.
-- Returns goal, message, isNew.
function GoalService.AddReputationGoal(factionID, standing)
  local store = GoalService.Store()
  if not store then return nil, LOADING end
  local RP = ns.ReputationProvider
  if not RP or not RP.IsAvailable() then
    return nil, "Reputation goals need the faction API, which this client lacks."
  end
  local record = RP.Get(factionID)
  if not record then
    return nil, string.format("No faction with id %s is known.", tostring(factionID))
  end
  standing = Util.ParseInt(standing) or RP.NextStanding(record)
  if standing < 1 or standing > 8 then
    return nil, "The standing must be between Hated and Exalted."
  end
  local existing = GoalService.FindReputationGoal(record.factionID)
  if existing then
    return reuseGoal(store, existing, function(goal, reopening)
      local ok, err = store:SetStanding(goal.id, standing)
      if ok and reopening then goal.target.startValue = record.value end
      return ok, err
    end)
  end
  local goal, message, isNew = createGoal(store, GoalModel.TypeIDs.REACH_REPUTATION, {
    factionID = record.factionID, name = record.name, standing = standing, startValue = record.value, icon = RP.ICON,
  })
  if goal and (record.standing or 0) >= standing then message = message .. " (already there)" end
  return goal, message, isNew
end

-- "argent dawn exalted", "argent dawn" (next standing), "exalted argent dawn". Returns goal, message, isNew.
function GoalService.AddReputationFromInput(text)
  text = Util.Trim(text or "")
  if text == "" then
    return nil, "Type a faction, optionally with the standing to reach (Argent Dawn Exalted)."
  end
  local RP = ns.ReputationProvider
  if not RP or not RP.IsAvailable() then
    return nil, "Reputation goals need the faction API, which this client lacks."
  end
  local name, standing = parseReputationInput(text, RP)
  local hits = RP.Search(name, 5)
  if #hits == 0 then
    return nil, string.format("No faction called \"%s\" in your reputation list.", name)
  end
  local note = matchNote(hits, hitName, hitName)
  local goal, message, isNew = GoalService.AddReputationGoal(hits[1].factionID, standing)
  if not goal then
    return nil, message
  end
  return goal, message .. note, isNew
end

-- Resolves free text (item ID, link or name) and adds an item goal (type
-- picked by TypeForItem unless given). An enchant or spell link becomes an
-- enchant goal, or a crafting goal for the item the recipe makes.
-- Returns goal, message, isNew.
function GoalService.AddFromInput(text, quantity, goalType)
  local spellID = GoalService.SpellIDFromText(text)
  if spellID then
    local recipe = ns.Planner.RecipeByID(spellID)
    if not recipe then
      return nil, string.format("No recipe with spell id %d is in the catalogue or your recorded professions.", spellID)
    end
    if recipe.enchant then
      return GoalService.AddEnchantGoal(spellID, quantity)
    end
    if recipe.outputItemID then
      return GoalService.AddFromInput(tostring(recipe.outputItemID), quantity, goalType)
    end
    -- A recipe link that makes no item: the goal is to learn it.
    return GoalService.AddRecipeGoal(spellID)
  end
  local parsed = ItemProvider.ParseInput(text)
  if not parsed then
    return nil, "Enter an item ID, Shift-click an item link, or type an item name."
  end
  local itemID = parsed.itemID
  local note = ""
  if parsed.kind == "name" then
    local hits = ItemProvider.SearchByName(parsed.name, 5)
    if #hits == 0 then
      return nil, string.format("No item named \"%s\" is known to ForeverPath (catalogue, recorded recipes and items seen). Use the item ID or Shift-click an item link.", parsed.name)
    end
    itemID = hits[1].itemID
    note = matchNote(hits, hitName, hitName)
  elseif parsed.name then
    ItemProvider.RememberName(itemID, parsed.name)
  end
  if ItemProvider.Exists(itemID) == false then
    return nil, string.format("Item %d does not exist on this client.", itemID)
  end
  local goal, message, isNew = GoalService.AddItemGoal(itemID, quantity, goalType)
  if not goal then
    return nil, message
  end
  return goal, message .. note, isNew
end

-- Goal input for one kind ("item", "recipe", "enchant", "skill", "quest",
-- "reputation", "attunement"); amount is the quantity or cast count for the
-- kinds that count one (items, enchants) and ignored by the rest, whose
-- target sits in the text. Returns goal, message, isNew.
local FROM_INPUT = {
  item = function(text, amount) return GoalService.AddFromInput(text, amount) end,
  recipe = function(text) return GoalService.AddRecipeFromInput(text) end,
  enchant = function(text, amount) return GoalService.AddEnchantFromInput(text, amount) end,
  skill = function(text) return GoalService.AddSkillFromInput(text) end,
  quest = function(text) return GoalService.AddQuestFromInput(text) end,
  reputation = function(text) return GoalService.AddReputationFromInput(text) end,
  attunement = function(text) return GoalService.AddAttunementFromInput(text) end,
}

function GoalService.AddByKind(kind, text, amount)
  return (FROM_INPUT[kind] or FROM_INPUT.item)(text, amount)
end

---------------------------------------------------------------------------
-- Type-ahead: what partial text in a goal input could mean
---------------------------------------------------------------------------
-- Suggestions for one goal kind ("item", "recipe", "enchant", "skill",
-- "quest", "reputation", "attunement") or "all" (a few of each, for the
-- header search). Each hit: { kind, text, meta, add = function(quantity) ->
-- goal, message, isNew } plus the id it stands for.
function GoalService.Suggest(kind, text, limit)
  text = Util.Trim(text or "")
  limit = limit or 6
  local out = {}
  if #text < 2 or text:find("|H", 1, true) then return out end
  local function push(hit)
    if #out < limit then out[#out + 1] = hit end
  end
  local catalogue = ns.Data.Recipes
  local function items(n)
    for _, hit in ipairs(ItemProvider.SearchByName(text, n)) do
      local itemID = hit.itemID
      push({ kind = "item", text = hit.name, meta = "Item", itemID = itemID, add = function(quantity) return GoalService.AddItemGoal(itemID, quantity) end })
    end
  end
  local function recipes(n, which)
    for _, hit in ipairs(catalogue and catalogue.Search and catalogue.Search(text, n, nil, which) or {}) do
      local spellID = hit.spellID
      if which == "enchant" then
        push({ kind = "enchant", text = hit.name, meta = hit.professionName or "Enchant", spellID = spellID, add = function(quantity) return GoalService.AddEnchantGoal(spellID, quantity) end })
      else
        push({ kind = "recipe", text = hit.name, meta = (hit.professionName or "Recipe") .. " recipe", spellID = spellID, add = function() return GoalService.AddRecipeGoal(spellID) end })
      end
    end
  end
  local function skills(n)
    local name, target = parseSkillInput(text)
    local needle = string.lower(name)
    local count = 0
    for _, p in ipairs(catalogue and catalogue.Professions and catalogue.Professions() or {}) do
      if count < n and needle ~= "" and string.find(string.lower(p.name or ""), needle, 1, true) then
        count = count + 1
        local standing = ns.Planner.CurrentSkill(p.name, p.id)
        push({ kind = "skill", text = p.name .. (target and (" " .. target) or ""), meta = standing and string.format("You are at %d", standing.skillLevel or 0) or "Profession",
          professionName = p.name, add = function() return GoalService.AddSkillGoal(p.name, target) end })
      end
    end
  end
  local function quests(n)
    local QP = ns.QuestProvider
    if not QP or not QP.IsAvailable or not QP.IsAvailable() then return end
    for _, hit in ipairs(QP.Search(text, n)) do
      local questID = hit.questID
      push({ kind = "quest", text = hit.name, meta = hit.where or "Quest", questID = questID, add = function() return GoalService.AddQuestGoal(questID) end })
    end
  end
  local function factions(n)
    local RP = ns.ReputationProvider
    if not RP or not RP.IsAvailable() then return end
    local name, standing = parseReputationInput(text, RP)
    for _, hit in ipairs(RP.Search(name, n)) do
      local factionID = hit.factionID
      local record = hit.record or RP.Get(factionID)
      push({ kind = "reputation", text = hit.name .. (standing and (" - " .. RP.StandingLabel(standing)) or ""), factionID = factionID,
        meta = hit.unmet and "Not met yet" or (record and record.standingLabel or "Faction"),
        add = function() return GoalService.AddReputationGoal(factionID, standing) end })
    end
  end
  local function attunements(n)
    local AP = ns.AttuneProvider
    if not AP or not AP.IsAvailable() then return end
    local needle = string.lower(text)
    local count = 0
    for _, attune in ipairs(AP.List()) do
      if count < n and string.find(string.lower(attune.name or ""), needle, 1, true) then
        count = count + 1
        local id = attune.id
        push({ kind = "attunement", text = attune.name, meta = (attune.group and attune.group ~= "") and attune.group or "Attunement", attuneID = id,
          add = function() return GoalService.AddAttunementGoal(id) end })
      end
    end
  end
  if kind == "item" then items(limit)
  elseif kind == "recipe" then recipes(limit)
  elseif kind == "enchant" then recipes(limit, "enchant")
  elseif kind == "skill" then skills(limit)
  elseif kind == "quest" then quests(limit)
  elseif kind == "reputation" then factions(limit)
  elseif kind == "attunement" then attunements(limit)
  else
    items(3)
    recipes(2, "item")
    recipes(1, "enchant")
    factions(2)
    quests(2)
    attunements(1)
    skills(1)
  end
  return out
end

-- Returns the removed goal, or nil, reason.
function GoalService.Remove(id)
  local store = GoalService.Store()
  if not store then return nil, "not loaded" end
  return store:Remove(id)
end

function GoalService.Select(id)
  local store = GoalService.Store()
  if not store then return false, "not loaded" end
  return store:Select(id)
end

function GoalService.SetQuantity(id, quantity)
  local store = GoalService.Store()
  if not store then return false, "not loaded" end
  return store:SetQuantity(id, quantity)
end

function GoalService.SetCasts(id, casts)
  local store = GoalService.Store()
  if not store then return false, "not loaded" end
  return store:SetCasts(id, casts)
end

function GoalService.SetStatus(id, status)
  local store = GoalService.Store()
  if not store then return false, "not loaded" end
  return store:SetStatus(id, status)
end

function GoalService.SetTracked(id, tracked)
  local store = GoalService.Store()
  if not store then return false, "not loaded" end
  return store:SetTracked(id, tracked)
end

-- Sets whatever the goal counts (quantity, casts or target skill).
function GoalService.SetAmount(id, value)
  local goal = GoalService.Get(id)
  local amount = goal and ns.GoalModel.Amount(goal)
  if not amount then return false, "nothing to count" end
  if amount.field == "rank" then return GoalService.SetRank(id, value) end
  return GoalService.SetQuantity(id, value)
end

function GoalService.SetRoute(id, itemID, route)
  local store = GoalService.Store()
  if not store then return false, "not loaded" end
  return store:SetRoute(id, itemID, route)
end

function GoalService.SetPriority(id, position)
  local store = GoalService.Store()
  if not store then return false, "not loaded" end
  return store:SetPriority(id, position)
end

function GoalService.List(filter)
  local store = GoalService.Store()
  if not store then return {} end
  return store:List(filter)
end

function GoalService.Count(filter)
  local store = GoalService.Store()
  if not store then return 0 end
  return store:Count(filter)
end

function GoalService.GetSelected()
  local store = GoalService.Store()
  if not store then return nil end
  return store:GetSelected()
end

function GoalService.GetSelectedID()
  local store = GoalService.Store()
  if not store then return nil end
  return store:GetSelectedID()
end

function GoalService.Get(id)
  local store = GoalService.Store()
  if not store then return nil end
  return store:Get(id)
end

-- The goal for an item, whether it is a craft or an obtain goal.
function GoalService.FindItemGoal(itemID)
  return findGoal(GoalModel.TypeIDs.CRAFT_ITEM, "itemID", itemID) or findGoal(GoalModel.TypeIDs.OBTAIN_ITEM, "itemID", itemID)
end

---------------------------------------------------------------------------
-- Planning settings
---------------------------------------------------------------------------
-- Whether alts' snapshotted bags and banks count as owned in every goal.
function GoalService.IncludesAlts()
  return ns.db ~= nil and ns.db.settings.includeAlts == true
end

-- Sets includeAlts and announces it. Returns the message to show, or nil, reason.
function GoalService.SetIncludeAlts(on)
  if not ns.db then return nil, "not loaded" end
  ns.db.settings.includeAlts = on and true or false
  Events.Fire("FP_SETTINGS_CHANGED", "includeAlts")
  return on and "Alts' bags and banks now count as owned." or "Only this character's bags and bank count as owned."
end

---------------------------------------------------------------------------
-- Shopping list state: ns.chardb.shopping, shaped by Database.DEFAULTS
---------------------------------------------------------------------------
-- { bought, included, sort, filter } for this character, or nil before load.
function GoalService.ShoppingState()
  return ns.chardb and ns.chardb.shopping
end

-- Whether a goal's materials are on the shopping list: the player's choice
-- for it, else ShoppingList.DefaultIncluded (active and queued goals).
function GoalService.InShopping(goal)
  local state = GoalService.ShoppingState()
  local choice = state and state.included[goal.id]
  if choice ~= nil then return choice end
  return ns.ShoppingList.DefaultIncluded(goal)
end

function GoalService.SetInShopping(goalID, included)
  local state = GoalService.ShoppingState()
  if not state then return false, "not loaded" end
  state.included[goalID] = included
  return true
end

---------------------------------------------------------------------------
-- Evaluated views: what the Planner made of every open goal
---------------------------------------------------------------------------
GoalService.views = {}

-- Re-evaluates every open goal once (one shared inventory ledger) and keeps
-- the result. The window and the tracker call it when they refresh.
function GoalService.EvaluateViews()
  GoalService.views = ns.Planner.EvaluateAll(GoalService.List({ open = true }))
  return GoalService.views
end

-- goalID -> view from the last evaluation.
function GoalService.Views()
  return GoalService.views
end

-- One goal's view, evaluated now when the last evaluation did not include it.
function GoalService.View(goalID)
  local view = GoalService.views[goalID]
  if view then return view end
  local goal = GoalService.Get(goalID)
  return goal and ns.Planner.Evaluate(goal) or nil
end

-- The shopping list over every open goal's last evaluated view, with this
-- character's ticks, inclusion choices, prices and gold (Domain/ShoppingList).
function GoalService.ShoppingList()
  local state = GoalService.ShoppingState()
  local entries = {}
  for _, goal in ipairs(GoalService.List({ open = true })) do
    entries[#entries + 1] = { goal = goal, view = GoalService.View(goal.id) }
  end
  return ns.ShoppingList.Build(entries, {
    included = GoalService.InShopping, bought = state and state.bought or {}, nameOf = ItemProvider.GetName, sort = state and state.sort,
    priceOf = ns.PriceProvider.GetPrice,
    gold = ns.CharacterProvider.AccountGold(),
  })
end

---------------------------------------------------------------------------
-- Goal attribution: which quests and equipment slots serve which goals
---------------------------------------------------------------------------
-- Which quests feed open goals: { [questID] = { entry, goals = { { goal, name,
-- itemID, count } | { goal, name, reputation, faction } } } }, from the
-- missing leaves of each goal's tree (quest rewards) and, for reputation
-- goals, every open quest that gives reputation with the faction.
-- goals default to the open goals, views to the last evaluation.
function GoalService.QuestFeeds(goals, views)
  goals = goals or GoalService.List({ open = true })
  views = views or GoalService.views
  local feeds = {}
  local function feedFor(entry)
    local feed = feeds[entry.id]
    if not feed then
      feed = { entry = entry, goals = {} }
      feeds[entry.id] = feed
    end
    return feed
  end
  for _, goal in ipairs(goals) do
    local view = views[goal.id]
    local name = GoalService.Name(goal)
    if goal.type == GoalModel.TypeIDs.REACH_REPUTATION then
      local quests = view and view.reputation and view.reputation.quests
        or ns.Log.Try(ns.ReputationProvider.QuestsFor, goal.target.name, goal.target.factionID)
      for _, quest in ipairs(quests or {}) do
        if quest.entry and not (quest.state and quest.state.completed) then
          local feed = feedFor(quest.entry)
          feed.goals[#feed.goals + 1] = { goal = goal, name = name, reputation = quest.amount, faction = goal.target.name }
        end
      end
    else
      local leaves = view and view.tree and view.tree.summary.missingLeaves or {}
      for _, leaf in ipairs(leaves) do
        if leaf.itemID then
          for _, entry in ipairs(ns.QuestProvider.QuestsRewarding(leaf.itemID)) do
            local feed = feedFor(entry)
            feed.goals[#feed.goals + 1] = { goal = goal, name = name, itemID = leaf.itemID, count = leaf.count }
          end
        end
      end
    end
  end
  return feeds
end

-- The Quests screen's board for a tab ("zone", "goal" or "completed"):
-- { groups = { { key, label, rows = { { questID, name, level, label, kind,
-- state, entry, feeds = { goal names }, feed, goal } } } }, feeds, feedCount,
-- total, questGoals }. Zone groups are instances or log zones; goal groups
-- are named after the goals a quest serves, journal and quest-log quests
-- alike. feedOnly keeps only quests that serve a goal on the zone tab.
function GoalService.QuestBoard(tab, feedOnly)
  local QP = ns.QuestProvider
  local feeds = GoalService.QuestFeeds()
  local questGoals = {}
  for _, goal in ipairs(GoalService.List()) do
    if goal.type == GoalModel.TypeIDs.COMPLETE_QUEST then questGoals[goal.target.questID] = goal end
  end
  -- The goals a quest serves, its own quest goal first.
  local function servedGoals(questID)
    local names = {}
    if questGoals[questID] then names[1] = GoalService.Name(questGoals[questID]) end
    for _, f in ipairs(feeds[questID] and feeds[questID].goals or {}) do names[#names + 1] = f.name end
    return names
  end
  local playerLevel = ns.Compat.PlayerLevel()
  local groups, byLabel, seen = {}, {}, {}
  local function add(groupLabel, questID, name, level, state, entry)
    if seen[questID] then return end
    seen[questID] = true
    local g = byLabel[groupLabel]
    if not g then
      g = { key = groupLabel, label = groupLabel, rows = {} }
      byLabel[groupLabel] = g
      groups[#groups + 1] = g
    end
    local label, kind, key = QP.StateLabel(state, entry, playerLevel)
    local goal = questGoals[questID]
    local feedNames = servedGoals(questID)
    if goal then feedNames[1] = "goal: " .. feedNames[1] end
    g.rows[#g.rows + 1] = {
      questID = questID, name = name, level = level, label = label, kind = kind, stateKey = key, state = state, entry = entry,
      feeds = feedNames, feed = feeds[questID], goal = goal,
    }
  end
  local function serves(questID) return feeds[questID] ~= nil or questGoals[questID] ~= nil end
  for _, entry in ipairs(QP.List()) do
    local state = QP.State(entry.id)
    local include
    if tab == "completed" then include = state.completed
    elseif tab == "goal" then include = serves(entry.id) and not state.completed
    else include = not state.completed and (not feedOnly or serves(entry.id)) end
    if include then
      add(tab == "goal" and table.concat(servedGoals(entry.id), ", ") or (entry.instance or "?"), entry.id, entry.name, entry.level, state, entry)
    end
  end
  if tab ~= "completed" then
    for _, log in ipairs(QP.LogEntries()) do
      if not seen[log.questID] and ((tab == "goal" and serves(log.questID)) or (tab ~= "goal" and (not feedOnly or serves(log.questID)))) then
        add(tab == "goal" and table.concat(servedGoals(log.questID), ", ") or (log.zone or "Quest log"), log.questID,
          log.title or QP.Name(log.questID), log.level, QP.State(log.questID), QP.Get(log.questID))
      end
    end
  end
  table.sort(groups, function(a, b) return tostring(a.label) < tostring(b.label) end)
  local total = 0
  for _, g in ipairs(groups) do
    table.sort(g.rows, function(a, b)
      if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
      if a.name ~= b.name then return tostring(a.name) < tostring(b.name) end
      return a.questID < b.questID
    end)
    total = total + #g.rows
  end
  return { groups = groups, feeds = feeds, feedCount = Util.Count(feeds), total = total, questGoals = questGoals }
end

-- EquipmentProvider.Analyze with the open item goals placed on the slots
-- their items fit: each slot entry gains goal, goalView, goalItemID, and the
-- result trackedGoals (item goals that are gear) and upgradesPlanned.
-- source filters GearQuest candidates.
function GoalService.Equipment(source, goals, views)
  goals = goals or GoalService.List({ open = true })
  views = views or GoalService.views
  local EP = ns.EquipmentProvider
  local analysis = EP.Analyze({ source = source })
  local goalSlots, tracked = {}, 0
  for _, goal in ipairs(goals) do
    if GoalModel.Types[goal.type].targetKind == "item" then
      local keys = EP.SlotKeysFor(goal.target.itemID)
      if #keys > 0 then
        tracked = tracked + 1
        local placed = false
        for _, key in ipairs(keys) do
          if not placed and not goalSlots[key] then
            goalSlots[key] = goal
            placed = true
          end
        end
        if not placed then goalSlots[keys[1]] = goalSlots[keys[1]] or goal end
      end
    end
  end
  analysis.trackedGoals, analysis.upgradesPlanned = tracked, 0
  for _, entry in ipairs(analysis.slots) do
    local goal = goalSlots[entry.slot.key]
    if goal then
      entry.goal, entry.goalView, entry.goalItemID = goal, views[goal.id], goal.target.itemID
      analysis.upgradesPlanned = analysis.upgradesPlanned + 1
    end
  end
  return analysis
end

---------------------------------------------------------------------------
-- Cross-goal summaries the screens render
---------------------------------------------------------------------------
-- What the active goals still need beyond this character's own bags and
-- bank, per item: needs[itemID] = units, and order (most needed first).
-- Alts' snapshots are added back, so the answer is the same whether they
-- count as owned or not. Train and quest steps carry no item and are left
-- out, as are crafts done for skill points (their reagents are needed, the
-- outputs are not), the same rule as the shopping list.
function GoalService.Needs()
  local needs, order = {}, {}
  for _, view in pairs(GoalService.views) do
    if view.goal and view.goal.status == GoalModel.Statuses.ACTIVE and view.tree then
      for _, node in pairs(view.tree.byKey) do
        local short = node.depth > 0 and node.itemID and not node.forSkill and (node.missing + (node.ownedAlts or 0)) or 0
        if short > 0 then
          if not needs[node.itemID] then order[#order + 1] = node.itemID end
          needs[node.itemID] = (needs[node.itemID] or 0) + short
        end
      end
    end
  end
  table.sort(order, function(a, b)
    if needs[a] ~= needs[b] then return needs[a] > needs[b] end
    return a < b
  end)
  return needs, order
end

-- The Dashboard overview (Domain/Overview) over the active goals' views.
function GoalService.Overview()
  local entries = {}
  for _, goal in ipairs(GoalService.List({ status = GoalModel.Statuses.ACTIVE })) do
    entries[#entries + 1] = { goal = goal, view = GoalService.views[goal.id] }
  end
  return ns.Overview.Build(entries, {
    nameOf = ItemProvider.GetName,
    craftableBy = function(itemID)
      for _, candidate in ipairs(ns.ProfessionProvider.FindRecipesForItem(itemID)) do
        if candidate.learned then return candidate.recipe.professionName end
      end
      return nil
    end,
    completedCount = GoalService.Count({ status = GoalModel.Statuses.COMPLETED }),
  })
end

-- Prices for a material list ({ { itemID, missing } }): byItem[itemID] =
-- priceInfo, and the cost of buying everything missing (buyTotal) over the
-- priced rows, with how many missing rows have no price (unpriced).
function GoalService.PriceMaterials(materials)
  local result = { byItem = {}, buyTotal = 0, priced = 0, unpriced = 0 }
  for _, material in ipairs(materials) do
    local price = ns.PriceProvider.GetPrice(material.itemID)
    result.byItem[material.itemID] = price
    if price then
      result.priced = result.priced + 1
      if material.missing > 0 then result.buyTotal = result.buyTotal + price.copper * material.missing end
    elseif material.missing > 0 then
      result.unpriced = result.unpriced + 1
    end
  end
  return result
end

-- Tracked, open goals in priority order (drives the tracker and header pill).
function GoalService.TrackedGoals()
  return GoalService.List({ open = true, tracked = true })
end

-- Resolves "2" (index in the open list) or a goal id.
function GoalService.Resolve(ref)
  local store = GoalService.Store()
  if not store or ref == nil then return nil end
  local index = Util.ParseInt(ref)
  if index then
    return store:List({ open = true })[index]
  end
  return store:Get(ref)
end
