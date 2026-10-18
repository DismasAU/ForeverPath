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
