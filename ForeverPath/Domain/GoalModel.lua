-- Generic goal model.
--
-- A goal is plain data so it serializes straight into SavedVariables:
--   {
--     id = "fp-1792147990-3-0421", type = "CRAFT_ITEM", status = "ACTIVE",
--     target = { itemID = 2996, quantity = 2 },
--     tracked = true, priority = 1,
--     createdAt = 1792147990, updatedAt = 1792147990, completedAt = nil, notes = nil,
--   }
-- `target` is type specific:
--   CRAFT_ITEM / OBTAIN_ITEM   { itemID, quantity }
--   COMPLETE_ATTUNEMENT        { attuneID, name, icon }
--   LEARN_RECIPE               { spellID, name, professionName, professionID, icon }
--   REACH_SKILL                { professionID, professionName, rank, startRank, icon }
-- COMPLETE_QUEST and REACH_REPUTATION are registered so saved data, UI and
-- planners can grow into them.
local _, ns = ...

local GoalModel = {}
ns.GoalModel = GoalModel

local Util = ns.Util

GoalModel.Types = {
  CRAFT_ITEM = { label = "Craft item", badge = "Crafting", supported = true, targetKind = "item" },
  OBTAIN_ITEM = { label = "Obtain item", badge = "Item", supported = true, targetKind = "item" },
  COMPLETE_QUEST = { label = "Complete quest", badge = "Quest", supported = false, targetKind = "quest" },
  REACH_REPUTATION = { label = "Reach reputation", badge = "Reputation", supported = false, targetKind = "faction" },
  LEARN_RECIPE = { label = "Learn recipe", badge = "Recipe", supported = true, targetKind = "recipe" },
  COMPLETE_ATTUNEMENT = { label = "Complete attunement", badge = "Attunement", supported = true, targetKind = "attunement" },
  REACH_SKILL = { label = "Reach profession skill", badge = "Skill", supported = true, targetKind = "skill" },
}

GoalModel.MAX_SKILL = 1000

GoalModel.Statuses = { ACTIVE = "ACTIVE", QUEUED = "QUEUED", PAUSED = "PAUSED", COMPLETED = "COMPLETED" }
GoalModel.StatusOrder = { ACTIVE = 1, QUEUED = 2, PAUSED = 3, COMPLETED = 4 }
GoalModel.StatusLabel = { ACTIVE = "Active", QUEUED = "Queued", PAUSED = "Paused", COMPLETED = "Completed" }

local counter = 0

-- Stable unique id: timestamp + per-session counter + random suffix.
function GoalModel.GenerateID(now, random)
  counter = counter + 1
  now = now or Util.Now()
  local rnd = random and random(0, 9999) or math.random(0, 9999)
  return string.format("fp-%d-%d-%04d", now, counter, rnd)
end

local function validateItemTarget(target)
  if type(target) ~= "table" then
    return false, "target missing"
  end
  if not Util.IsPositiveInt(target.itemID) then
    return false, "itemID must be a positive integer"
  end
  if not Util.IsPositiveInt(target.quantity) then
    return false, "quantity must be a positive integer"
  end
  if target.quantity > 100000 then
    return false, "quantity is unreasonably large"
  end
  return true
end

local function validateAttunementTarget(target)
  if type(target) ~= "table" then
    return false, "target missing"
  end
  if (type(target.attuneID) ~= "string" and type(target.attuneID) ~= "number") or tostring(target.attuneID) == "" then
    return false, "attuneID must be set"
  end
  return true
end

local function validateRecipeTarget(target)
  if type(target) ~= "table" then
    return false, "target missing"
  end
  if not Util.IsPositiveInt(target.spellID) then
    return false, "spellID must be a positive integer"
  end
  return true
end

local function validateSkillTarget(target)
  if type(target) ~= "table" then
    return false, "target missing"
  end
  if type(target.professionName) ~= "string" or target.professionName == "" then
    return false, "professionName must be set"
  end
  if not Util.IsPositiveInt(target.rank) or target.rank > GoalModel.MAX_SKILL then
    return false, "rank must be a positive integer"
  end
  return true
end

local validators = {
  CRAFT_ITEM = validateItemTarget,
  OBTAIN_ITEM = validateItemTarget,
  COMPLETE_ATTUNEMENT = validateAttunementTarget,
  LEARN_RECIPE = validateRecipeTarget,
  REACH_SKILL = validateSkillTarget,
}

function GoalModel.IsSupported(goalType)
  local def = GoalModel.Types[goalType]
  return def ~= nil and def.supported == true
end

function GoalModel.ValidateTarget(goalType, target)
  local def = GoalModel.Types[goalType]
  if not def then
    return false, "unknown goal type"
  end
  local validator = validators[goalType]
  if validator then
    return validator(target)
  end
  if type(target) ~= "table" then
    return false, "target missing"
  end
  return true
end

-- Creates a new goal. opts.now / opts.random allow deterministic tests.
function GoalModel.New(goalType, target, opts)
  opts = opts or {}
  local ok, err = GoalModel.ValidateTarget(goalType, target)
  if not ok then
    return nil, err
  end
  local now = opts.now or Util.Now()
  return {
    id = GoalModel.GenerateID(now, opts.random),
    type = goalType,
    status = GoalModel.Statuses.ACTIVE,
    target = Util.DeepCopy(target),
    tracked = opts.tracked ~= false,
    priority = opts.priority,
    createdAt = now,
    updatedAt = now,
    notes = opts.notes,
  }
end

-- Validates a goal read from saved data.
function GoalModel.Validate(goal)
  if type(goal) ~= "table" then
    return false, "goal is not a table"
  end
  if type(goal.id) ~= "string" or goal.id == "" then
    return false, "missing id"
  end
  if type(goal.type) ~= "string" or not GoalModel.Types[goal.type] then
    return false, "unknown type"
  end
  local ok, err = GoalModel.ValidateTarget(goal.type, goal.target)
  if not ok then
    return false, err
  end
  if goal.status ~= nil and not GoalModel.Statuses[goal.status] then
    return false, "unknown status"
  end
  if goal.createdAt ~= nil and type(goal.createdAt) ~= "number" then
    return false, "createdAt not a number"
  end
  if goal.tracked ~= nil and type(goal.tracked) ~= "boolean" then
    return false, "tracked not a boolean"
  end
  if goal.priority ~= nil and type(goal.priority) ~= "number" then
    return false, "priority not a number"
  end
  if goal.routes ~= nil then
    if type(goal.routes) ~= "table" then
      return false, "routes not a table"
    end
    for itemID, route in pairs(goal.routes) do
      if type(itemID) ~= "number" or (route ~= "craft" and route ~= "buy") then
        return false, "invalid route"
      end
    end
  end
  return true
end

function GoalModel.SetQuantity(goal, quantity, now)
  if not Util.IsPositiveInt(quantity) then
    return false, "quantity must be a positive integer"
  end
  if type(goal.target) ~= "table" then
    return false, "goal has no target"
  end
  goal.target.quantity = quantity
  goal.updatedAt = now or Util.Now()
  return true
end

-- Target skill of a REACH_SKILL goal.
function GoalModel.SetRank(goal, rank, now)
  if goal.type ~= "REACH_SKILL" then
    return false, "not a skill goal"
  end
  if not Util.IsPositiveInt(rank) or rank > GoalModel.MAX_SKILL then
    return false, "rank must be a positive integer"
  end
  goal.target.rank = rank
  goal.updatedAt = now or Util.Now()
  return true
end

function GoalModel.SetStatus(goal, status, now)
  if not GoalModel.Statuses[status] then
    return false, "unknown status"
  end
  goal.status = status
  goal.updatedAt = now or Util.Now()
  if status == GoalModel.Statuses.COMPLETED then
    goal.completedAt = goal.updatedAt
  else
    goal.completedAt = nil
  end
  return true
end

function GoalModel.IsOpen(goal)
  return goal.status ~= GoalModel.Statuses.COMPLETED
end

-- Short title such as "Craft 2x Bolt of Linen Cloth". nameLookup(itemID) is optional.
function GoalModel.Title(goal, nameLookup)
  local def = GoalModel.Types[goal.type]
  local label = def and def.label or goal.type
  if def and def.targetKind == "item" and goal.target then
    local name = nameLookup and nameLookup(goal.target.itemID) or nil
    name = name or ("Item " .. tostring(goal.target.itemID))
    local verb = goal.type == "CRAFT_ITEM" and "Craft" or "Obtain"
    return string.format("%s %dx %s", verb, goal.target.quantity or 1, name)
  end
  if goal.type == "REACH_SKILL" and goal.target then
    return string.format("Reach %s %d", goal.target.professionName or "skill", goal.target.rank or 0)
  end
  if goal.target and type(goal.target.name) == "string" then
    return string.format("%s: %s", label, goal.target.name)
  end
  return label
end

-- Name only (for the design's name-first rows); falls back to "Item 1234".
function GoalModel.Name(goal, nameLookup)
  if goal.target and goal.target.itemID then
    return (nameLookup and nameLookup(goal.target.itemID)) or ("Item " .. tostring(goal.target.itemID))
  end
  if goal.type == "REACH_SKILL" and goal.target then
    return string.format("%s %d", goal.target.professionName or "Skill", goal.target.rank or 0)
  end
  if goal.target and type(goal.target.name) == "string" then
    return goal.target.name
  end
  local def = GoalModel.Types[goal.type]
  return def and def.label or goal.type
end
