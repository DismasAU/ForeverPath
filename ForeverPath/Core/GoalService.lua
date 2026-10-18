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

function GoalService.Init()
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
  if ns.ProfessionProvider and ns.ProfessionProvider.FindRecipesForItem then
    local ok, candidates = pcall(ns.ProfessionProvider.FindRecipesForItem, itemID)
    if ok and type(candidates) == "table" and #candidates > 0 then return "CRAFT_ITEM" end
  end
  local catalogue = ns.Data and ns.Data.Recipes
  if catalogue and catalogue.Lookup then
    local hints = catalogue.Lookup(itemID)
    if type(hints) == "table" and #hints > 0 then return "CRAFT_ITEM" end
  end
  local haveCatalogue = catalogue and catalogue.IsAvailable and catalogue.IsAvailable()
  if not haveCatalogue and ns.ProfessionProvider and ns.ProfessionProvider.HasScanData and not ns.ProfessionProvider.HasScanData() then
    return "CRAFT_ITEM"
  end
  return "OBTAIN_ITEM"
end

-- Creates or updates an item goal. goalType defaults to TypeForItem; an
-- existing goal for the item is updated whatever its type.
-- Returns goal, message, isNew.
function GoalService.AddItemGoal(itemID, quantity, goalType)
  local store = GoalService.Store()
  if not store then
    return nil, "ForeverPath is still loading."
  end
  quantity = Util.IsPositiveInt(quantity) and quantity or 1
  local explicit = goalType
  goalType = goalType or GoalService.TypeForItem(itemID)
  local existing = store:FindByItem("CRAFT_ITEM", itemID) or store:FindByItem("OBTAIN_ITEM", itemID)
  if existing then
    if explicit and existing.type ~= explicit then
      store:SetType(existing.id, explicit)
    end
    store:SetQuantity(existing.id, quantity)
    if not GoalModel.IsOpen(existing) then
      store:SetStatus(existing.id, GoalModel.Statuses.ACTIVE)
    end
    store:Select(existing.id)
    return existing, string.format("Updated goal: %s", GoalService.Title(existing)), false
  end
  local goal, err = store:Create(goalType, { itemID = itemID, quantity = quantity })
  if not goal then
    return nil, err
  end
  store:Select(goal.id)
  ItemProvider.Prefetch(itemID)
  return goal, string.format("Added goal: %s", GoalService.Title(goal)), true
end

function GoalService.AddCraftGoal(itemID, quantity)
  return GoalService.AddItemGoal(itemID, quantity, "CRAFT_ITEM")
end

function GoalService.FindAttunementGoal(attuneID)
  local store = GoalService.Store()
  if not store then return nil end
  attuneID = tostring(attuneID)
  for _, goal in ipairs(store:List()) do
    if goal.type == "COMPLETE_ATTUNEMENT" and goal.target and tostring(goal.target.attuneID) == attuneID then
      return goal
    end
  end
  return nil
end

-- Creates (or selects) an attunement goal from an Attune id. Returns goal, message, isNew.
function GoalService.AddAttunementGoal(attuneID)
  local store = GoalService.Store()
  if not store then
    return nil, "ForeverPath is still loading."
  end
  local attune = ns.AttuneProvider and ns.AttuneProvider.Get(attuneID)
  if not attune then
    return nil, ns.AttuneProvider and ns.AttuneProvider.IsAvailable() and "Unknown attunement." or "Attunement goals need the Attune addon."
  end
  local existing = GoalService.FindAttunementGoal(attune.id)
  if existing then
    if not GoalModel.IsOpen(existing) then
      store:SetStatus(existing.id, GoalModel.Statuses.ACTIVE)
    end
    store:Select(existing.id)
    return existing, string.format("Already a goal: %s", GoalService.Title(existing)), false
  end
  local goal, err = store:Create("COMPLETE_ATTUNEMENT", { attuneID = attune.id, name = attune.name, icon = attune.icon })
  if not goal then
    return nil, err
  end
  store:Select(goal.id)
  return goal, string.format("Added goal: %s", GoalService.Title(goal)), true
end

-- Attunement goal from free text (name, for the player's faction).
function GoalService.AddAttunementFromInput(text)
  if not ns.AttuneProvider or not ns.AttuneProvider.IsAvailable() then
    return false, "Attunement goals need the Attune addon installed and enabled."
  end
  local attune = ns.AttuneProvider.Find(Util.Trim(text or ""))
  if not attune then
    return false, string.format("No attunement called \"%s\" for your faction. /fp attunements lists them.", Util.Trim(text or ""))
  end
  local goal, message = GoalService.AddAttunementGoal(attune.id)
  if not goal then
    return false, message
  end
  return true, message, goal
end

---------------------------------------------------------------------------
-- Learn-recipe goals
---------------------------------------------------------------------------
function GoalService.FindRecipeGoal(spellID)
  local store = GoalService.Store()
  if not store then return nil end
  for _, goal in ipairs(store:List()) do
    if goal.type == "LEARN_RECIPE" and goal.target and goal.target.spellID == spellID then
      return goal
    end
  end
  return nil
end

local function recipeByID(spellID)
  local catalogue = ns.Data and ns.Data.Recipes
  local recipe = catalogue and catalogue.Get and catalogue.Get(spellID) or nil
  if not recipe and catalogue and catalogue.GetCombine then recipe = catalogue.GetCombine(spellID) end
  if not recipe and ns.db and ns.db.recipes then recipe = ns.db.recipes[spellID] end
  return recipe
end

-- Creates (or selects) a learn-recipe goal for a recipe spell id. Returns goal, message, isNew.
function GoalService.AddRecipeGoal(spellID)
  local store = GoalService.Store()
  if not store then
    return nil, "ForeverPath is still loading."
  end
  local recipe = recipeByID(spellID)
  if not recipe then
    return nil, string.format("No recipe with spell id %s is known (catalogue or recorded professions).", tostring(spellID))
  end
  if recipe.combine then
    return nil, string.format("%s is an item-use combine: anyone can do it, there is nothing to learn.", recipe.name or "That")
  end
  local existing = GoalService.FindRecipeGoal(spellID)
  if existing then
    if not GoalModel.IsOpen(existing) then
      store:SetStatus(existing.id, GoalModel.Statuses.ACTIVE)
    end
    store:Select(existing.id)
    return existing, string.format("Already a goal: %s", GoalService.Title(existing)), false
  end
  local goal, err = store:Create("LEARN_RECIPE", {
    spellID = spellID, name = recipe.name, professionName = recipe.professionName, professionID = recipe.professionID, icon = recipe.icon,
  })
  if not goal then
    return nil, err
  end
  store:Select(goal.id)
  if recipe.teachItemID then ItemProvider.Prefetch(recipe.teachItemID) end
  return goal, string.format("Added goal: %s", GoalService.Title(goal)), true
end

-- Learn-recipe goal from free text: a spell id, or a recipe name searched
-- in the catalogue (exact name first). Returns ok, message, goal.
function GoalService.AddRecipeFromInput(text)
  text = Util.Trim(text or "")
  if text == "" then
    return false, "Type a recipe name (or its spell id)."
  end
  local spellID = Util.ParseInt(text)
  local note = ""
  if not spellID then
    local catalogue = ns.Data and ns.Data.Recipes
    local hits = catalogue and catalogue.Search and catalogue.Search(text, 5) or {}
    if #hits == 0 then
      return false, string.format("No recipe called \"%s\" is in the catalogue.", text)
    end
    spellID = hits[1].spellID
    if #hits > 1 then
      local others = {}
      for i = 2, #hits do others[#others + 1] = hits[i].name .. " (" .. (hits[i].professionName or "?") .. ")" end
      note = string.format(" (using %s - %s; also matched: %s)", hits[1].name, hits[1].professionName or "?", Util.Join(others))
    end
  end
  local goal, message = GoalService.AddRecipeGoal(spellID)
  if not goal then
    return false, message
  end
  return true, message .. note, goal
end

---------------------------------------------------------------------------
-- Reach-skill goals
---------------------------------------------------------------------------
function GoalService.FindSkillGoal(professionName)
  local store = GoalService.Store()
  if not store then return nil end
  for _, goal in ipairs(store:List()) do
    if goal.type == "REACH_SKILL" and goal.target and goal.target.professionName == professionName then
      return goal
    end
  end
  return nil
end

-- This character's standing in a profession (live list first, then recorded windows).
local function professionStanding(name, professionID)
  if ns.Planner and ns.Planner.CurrentSkill then
    return ns.Planner.CurrentSkill(ns.Planner.DefaultDeps(), name, professionID)
  end
  return nil
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
  if not store then
    return nil, "ForeverPath is still loading."
  end
  local catalogue = ns.Data and ns.Data.Recipes
  local professionID, canonical
  if catalogue and catalogue.FindProfession then
    professionID, canonical = catalogue.FindProfession(professionName)
  end
  local standing = professionStanding(canonical or professionName, professionID)
  if not canonical then
    -- Not a catalogue profession: accept it when the character has it (e.g. a secondary skill).
    if standing then canonical = standing.name else
      return nil, string.format("No profession called \"%s\".", tostring(professionName))
    end
  end
  rank = Util.ParseInt(rank) or GoalService.NextSkillTarget(standing)
  local existing = GoalService.FindSkillGoal(canonical)
  if existing then
    store:SetRank(existing.id, rank)
    if not GoalModel.IsOpen(existing) then
      existing.target.startRank = standing and standing.skillLevel or existing.target.startRank
      store:SetStatus(existing.id, GoalModel.Statuses.ACTIVE)
    end
    store:Select(existing.id)
    return existing, string.format("Updated goal: %s", GoalService.Title(existing)), false
  end
  local goal, err = store:Create("REACH_SKILL", {
    professionID = professionID, professionName = canonical, rank = rank,
    startRank = standing and standing.skillLevel or nil, icon = standing and standing.icon or nil,
  })
  if not goal then
    return nil, err
  end
  store:Select(goal.id)
  local message = string.format("Added goal: %s", GoalService.Title(goal))
  if not standing then
    message = message .. string.format(" (%s is not one of this character's professions yet)", canonical)
  end
  return goal, message, true
end

-- "Tailoring 225", "tailoring", "225 Tailoring". Returns ok, message, goal.
function GoalService.AddSkillFromInput(text)
  text = Util.Trim(text or "")
  if text == "" then
    return false, "Type a profession, optionally with the skill to reach (Tailoring 225)."
  end
  local name, rank = text:match("^(.-)%s+(%d+)$")
  if not name then
    rank, name = text:match("^(%d+)%s+(.-)$")
  end
  name = Util.Trim(name or text)
  local goal, message = GoalService.AddSkillGoal(name, rank and tonumber(rank) or nil)
  if not goal then
    return false, message
  end
  return true, message, goal
end

function GoalService.SetRank(id, rank)
  local store = GoalService.Store()
  if not store then return false, "not loaded" end
  return store:SetRank(id, rank)
end

function GoalService.AddObtainGoal(itemID, quantity)
  return GoalService.AddItemGoal(itemID, quantity, "OBTAIN_ITEM")
end

-- Resolves free text (item ID, link or name) and adds an item goal (type
-- picked by TypeForItem unless given). Returns ok, message, goal.
function GoalService.AddFromInput(text, quantity, goalType)
  local parsed = ItemProvider.ParseInput(text)
  if not parsed then
    return false, "Enter an item ID, Shift-click an item link, or type an item name."
  end
  local itemID = parsed.itemID
  local note = ""
  if parsed.kind == "name" then
    local hits = ItemProvider.SearchByName(parsed.name, 5)
    if #hits == 0 then
      return false, string.format("No item named \"%s\" is known to ForeverPath (catalogue, recorded recipes and items seen). Use the item ID or Shift-click an item link.", parsed.name)
    end
    itemID = hits[1].itemID
    if #hits > 1 then
      local others = {}
      for i = 2, #hits do others[#others + 1] = hits[i].name end
      note = string.format(" (using %s; also matched: %s)", hits[1].name, Util.Join(others))
    end
  elseif parsed.name then
    ItemProvider.RememberName(itemID, parsed.name)
  end
  if ItemProvider.Exists(itemID) == false then
    return false, string.format("Item %d does not exist on this client.", itemID)
  end
  local goal, message = GoalService.AddItemGoal(itemID, quantity, goalType)
  if not goal then
    return false, message
  end
  return true, message .. note, goal
end

function GoalService.Remove(id)
  local store = GoalService.Store()
  if not store then return nil end
  return store:Remove(id)
end

function GoalService.Select(id)
  local store = GoalService.Store()
  if not store then return false end
  return store:Select(id)
end

function GoalService.SetQuantity(id, quantity)
  local store = GoalService.Store()
  if not store then return false, "not loaded" end
  return store:SetQuantity(id, quantity)
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

function GoalService.SetType(id, goalType)
  local store = GoalService.Store()
  return store and store:SetType(id, goalType)
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
