-- Goal collection over a storage table (the per-character SavedVariables).
-- Pure Lua: the storage table is injected, change notifications go through an
-- optional callback so this file has no dependency on the event bus or UI.
local _, ns = ...

local GoalModel = ns.GoalModel
local Util = ns.Util

local GoalStore = {}
GoalStore.__index = GoalStore
ns.GoalStore = GoalStore

-- storage: table with `goals` (id -> goal) and `selectedGoalId`.
-- opts.onChange(event, goal) is called after every mutation.
-- opts.now() overrides the clock.
function GoalStore.New(storage, opts)
  opts = opts or {}
  if type(storage) ~= "table" then
    storage = {}
  end
  if type(storage.goals) ~= "table" then
    storage.goals = {}
  end
  local self = setmetatable({
    storage = storage,
    onChange = opts.onChange,
    now = opts.now or Util.Now,
    dropped = 0,
  }, GoalStore)
  self.dropped = self:Sanitize()
  return self
end

local function notify(self, event, goal)
  if self.onChange then
    self.onChange(event, goal)
  end
end

-- Drops malformed entries (corrupted saved data, hand edits). Returns the count.
function GoalStore:Sanitize()
  local dropped = 0
  for id, goal in pairs(self.storage.goals) do
    local ok = GoalModel.Validate(goal)
    if not ok or goal.id ~= id then
      self.storage.goals[id] = nil
      dropped = dropped + 1
    else
      if goal.status == nil then goal.status = GoalModel.Statuses.ACTIVE end
      if goal.tracked == nil then goal.tracked = true end
    end
  end
  if self.storage.selectedGoalId and not self.storage.goals[self.storage.selectedGoalId] then
    self.storage.selectedGoalId = nil
  end
  return dropped
end

function GoalStore:Add(goal)
  local ok, err = GoalModel.Validate(goal)
  if not ok then
    return nil, err
  end
  if self.storage.goals[goal.id] then
    return nil, "duplicate goal id"
  end
  if goal.priority == nil then
    goal.priority = self:Count({ open = true }) + 1
  end
  self.storage.goals[goal.id] = goal
  notify(self, "added", goal)
  return goal
end

function GoalStore:Create(goalType, target, opts)
  local goal, err = GoalModel.New(goalType, target, opts)
  if not goal then
    return nil, err
  end
  return self:Add(goal)
end

function GoalStore:Get(id)
  if id == nil then return nil end
  return self.storage.goals[id]
end

local function matches(goal, filter)
  if not filter then return true end
  if filter.open ~= nil and GoalModel.IsOpen(goal) ~= filter.open then return false end
  if filter.status and goal.status ~= filter.status then return false end
  if filter.tracked ~= nil and (goal.tracked and true or false) ~= filter.tracked then return false end
  return true
end

function GoalStore:Count(filter)
  local n = 0
  for _, goal in pairs(self.storage.goals) do
    if matches(goal, filter) then n = n + 1 end
  end
  return n
end

local function compare(a, b)
  local sa, sb = GoalModel.StatusOrder[a.status] or 9, GoalModel.StatusOrder[b.status] or 9
  if sa ~= sb then return sa < sb end
  local pa, pb = a.priority or math.huge, b.priority or math.huge
  if pa ~= pb then return pa < pb end
  local ca, cb = a.createdAt or 0, b.createdAt or 0
  if ca ~= cb then return ca < cb end
  return a.id < b.id
end

-- Goals ordered by status group, priority, creation time. filter: { open=, status=, tracked= }
function GoalStore:List(filter)
  local list = {}
  for _, goal in pairs(self.storage.goals) do
    if matches(goal, filter) then
      list[#list + 1] = goal
    end
  end
  table.sort(list, compare)
  return list
end

function GoalStore:Remove(id)
  local goal = self.storage.goals[id]
  if not goal then
    return nil
  end
  self.storage.goals[id] = nil
  if self.storage.selectedGoalId == id then
    local remaining = self:List({ open = true })
    self.storage.selectedGoalId = remaining[1] and remaining[1].id or nil
  end
  self:Renumber()
  notify(self, "removed", goal)
  return goal
end

function GoalStore:Select(id)
  if id ~= nil and not self.storage.goals[id] then
    return false
  end
  if self.storage.selectedGoalId == id then
    return true
  end
  self.storage.selectedGoalId = id
  notify(self, "selected", self.storage.goals[id])
  return true
end

function GoalStore:GetSelectedID()
  return self.storage.selectedGoalId
end

function GoalStore:GetSelected()
  return self:Get(self.storage.selectedGoalId)
end

function GoalStore:SetQuantity(id, quantity)
  local goal = self.storage.goals[id]
  if not goal then
    return false, "no such goal"
  end
  local ok, err = GoalModel.SetQuantity(goal, quantity, self.now())
  if not ok then
    return false, err
  end
  notify(self, "updated", goal)
  return true
end

function GoalStore:SetStatus(id, status)
  local goal = self.storage.goals[id]
  if not goal then
    return false, "no such goal"
  end
  local ok, err = GoalModel.SetStatus(goal, status, self.now())
  if not ok then
    return false, err
  end
  self:Renumber()
  notify(self, "updated", goal)
  return true
end

function GoalStore:SetTracked(id, tracked)
  local goal = self.storage.goals[id]
  if not goal then
    return false, "no such goal"
  end
  goal.tracked = tracked and true or false
  goal.updatedAt = self.now()
  notify(self, "updated", goal)
  return true
end

-- Switches a goal between types that share the same target shape
-- (CRAFT_ITEM <-> OBTAIN_ITEM).
function GoalStore:SetType(id, goalType)
  local goal = self.storage.goals[id]
  if not goal then
    return false, "no such goal"
  end
  local def = GoalModel.Types[goalType]
  if not def then
    return false, "unknown goal type"
  end
  local current = GoalModel.Types[goal.type]
  if not current or current.targetKind ~= def.targetKind then
    return false, "goal types have different targets"
  end
  local ok, err = GoalModel.ValidateTarget(goalType, goal.target)
  if not ok then
    return false, err
  end
  if goal.type ~= goalType then
    goal.type = goalType
    goal.updatedAt = self.now()
    notify(self, "updated", goal)
  end
  return true
end

-- Forces how a reagent is obtained for this goal: "craft", "buy" or nil (default).
function GoalStore:SetRoute(id, itemID, route)
  local goal = self.storage.goals[id]
  if not goal then
    return false, "no such goal"
  end
  if type(itemID) ~= "number" then
    return false, "itemID must be a number"
  end
  if route ~= nil and route ~= "craft" and route ~= "buy" then
    return false, "route must be craft, buy or nil"
  end
  goal.routes = goal.routes or {}
  goal.routes[itemID] = route
  if next(goal.routes) == nil then goal.routes = nil end
  goal.updatedAt = self.now()
  notify(self, "updated", goal)
  return true
end

-- Assigns sequential priorities to open goals in their current order.
function GoalStore:Renumber()
  for index, goal in ipairs(self:List({ open = true })) do
    goal.priority = index
  end
end

-- Moves an open goal to position `position` (1 = highest priority).
function GoalStore:SetPriority(id, position)
  local goal = self.storage.goals[id]
  if not goal or not GoalModel.IsOpen(goal) then
    return false, "no such open goal"
  end
  local open = self:List({ open = true })
  local ordered = {}
  for _, g in ipairs(open) do
    if g.id ~= id then ordered[#ordered + 1] = g end
  end
  position = Util.Clamp(Util.ParseInt(position) or 1, 1, #ordered + 1)
  table.insert(ordered, position, goal)
  for index, g in ipairs(ordered) do
    g.priority = index
  end
  goal.updatedAt = self.now()
  notify(self, "updated", goal)
  return true
end

-- Finds an existing goal with the same type and item target.
function GoalStore:FindByItem(goalType, itemID)
  for _, goal in pairs(self.storage.goals) do
    if goal.type == goalType and goal.target and goal.target.itemID == itemID then
      return goal
    end
  end
  return nil
end
