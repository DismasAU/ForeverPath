-- Screen 12: add, order, pause and configure every goal.
local _, ns = ...

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets
local C = Theme.Colors
local Util = ns.Util
local GoalModel = ns.GoalModel

ns.UI.Screens = ns.UI.Screens or {}

local ROW = 52
local GROUP_ROW = 26
local SORTS = { { key = "priority", label = "Sort: Priority" }, { key = "name", label = "Sort: Name" }, { key = "progress", label = "Sort: Progress" } }

local function sortLabel(key)
  for _, s in ipairs(SORTS) do if s.key == key then return s.label end end
  return SORTS[1].label
end

local ONE_ROW, TWO_ROWS = 50, 84
local MIN_INPUT = 200

local function createNewGoalBar(screen)
  local bar = Widgets.Panel(screen, nil, { pad = 0 })
  bar:SetHeight(ONE_ROW)
  bar:SetPoint("TOPLEFT", screen, "TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", screen, "TOPRIGHT", 0, 0)
  local body = bar.body
  -- Everything but the kind segment lives on the first row, so the segment
  -- can drop to a second row when the window is narrow.
  local row1 = CreateFrame("Frame", nil, body)
  row1:SetHeight(ONE_ROW)
  row1:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  row1:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
  local label = Widgets.Text(row1, "panelHeading", "New goal", { caps = true })
  label:SetPoint("LEFT", row1, "LEFT", 14, 0)
  local add = Widgets.Button(row1, "+ Add goal", { primary = true, width = 100, onClick = function() screen:Submit() end })
  add:SetPoint("RIGHT", row1, "RIGHT", -12, 0)
  local stepper = Widgets.Stepper(row1, nil)
  stepper:SetPoint("RIGHT", add, "LEFT", -10, 0)
  local input
  local PLACEHOLDERS = {
    item = "Shift-click an item link, or type an item ID or name",
    recipe = "Type a recipe name (Bolt of Woolen Cloth, Sulfuron Hammer...)",
    enchant = "Shift-click an enchant in your Enchanting window, or type its name (Enchant Weapon - Crusader)",
    skill = "Type a profession and the skill to reach (Tailoring 225)",
    quest = "Type a quest name (dungeon and attunement quests, or your log)",
    reputation = "Type a faction and the standing to reach (Argent Dawn Exalted)",
    attunement = "Type an attunement name (Onyxia, Molten Core...)",
  }
  local segment = Widgets.Segment(body, {
    { key = "item", label = "Item" },
    { key = "recipe", label = "Recipe" },
    { key = "enchant", label = "Enchant" },
    { key = "skill", label = "Skill" },
    { key = "quest", label = "Quest" },
    { key = "reputation", label = "Reputation" },
    { key = "attunement", label = "Attunement" },
  }, function(key)
    if input and input.placeholder then
      input.placeholder:SetText(PLACEHOLDERS[key] or PLACEHOLDERS.item)
    end
    if stepper.SetEnabledState then stepper:SetEnabledState(key == "item" or key == "enchant") end
    ns.UI.MainFrame.HideSuggestions()
  end)
  input = Widgets.SearchField(row1, {
    name = "ForeverPathNewGoalInput",
    placeholder = "Shift-click an item link, or type an item ID or name",
    onEnter = function() screen:Submit() end,
    onChange = function(_, userInput) if userInput then screen:UpdateSuggestions() end end,
    onFocusLost = function()
      if ns.Compat.After then ns.Compat.After(0.2, function() ns.UI.MainFrame.HideSuggestions() end) else ns.UI.MainFrame.HideSuggestions() end
    end,
  })
  input:SetPoint("LEFT", label, "RIGHT", 14, 0)
  bar.input, bar.stepper, bar.add, bar.segment, bar.row1 = input, stepper, add, segment, row1
  table.insert(ns.UI.MainFrame.linkTargets, input)

  -- One row when the segment fits beside a usable input, two rows otherwise.
  function bar:Layout(forceWidth)
    local width = forceWidth or body:GetWidth() or 0
    local needed = 14 + (label:GetStringWidth() or 70) + 14 + MIN_INPUT + 10 + (segment:GetWidth() or 0) + 10 + (stepper:GetWidth() or 80) + 10 + (add:GetWidth() or 100) + 12
    local twoRows = width > 0 and width < needed
    if self.twoRows == twoRows then return twoRows end
    self.twoRows = twoRows
    input:ClearAllPoints()
    segment:ClearAllPoints()
    input:SetPoint("LEFT", label, "RIGHT", 14, 0)
    if twoRows then
      self:SetHeight(TWO_ROWS)
      input:SetPoint("RIGHT", stepper, "LEFT", -10, 0)
      segment:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -8)
    else
      self:SetHeight(ONE_ROW)
      segment:SetPoint("RIGHT", stepper, "LEFT", -10, 0)
      input:SetPoint("RIGHT", segment, "LEFT", -10, 0)
    end
    return twoRows
  end
  bar:Layout(nil)
  if bar.twoRows == nil then bar:Layout(999999) end
  bar:SetScript("OnSizeChanged", function(self) ns.Log.Call(self.Layout, self) end)
  return bar
end

local function createGoalRow(content, index)
  local row = Widgets.Frame(content, nil, { frameType = "Button" })
  row:SetHeight(ROW)
  local line = Widgets.HLine(row, C.black, 0.55)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(row)
  Widgets.SetColor(highlight, C.white, 0.025)
  local number = Widgets.Text(row, "secondary", "", { justify = "RIGHT", width = 18 })
  number:SetPoint("LEFT", row, "LEFT", 10, 0)
  local icon = Widgets.ItemIcon(row, 32)
  icon:SetPoint("LEFT", number, "RIGHT", 10, 0)
  local tracked = Widgets.Checkbox(row, "", function(checked)
    if row.goalID then ns.GoalService.SetTracked(row.goalID, checked) end
  end)
  tracked:SetWidth(16)
  tracked:SetPoint("RIGHT", row, "RIGHT", -12, 0)
  local cost = Widgets.Text(row, "secondary", "-", { justify = "RIGHT", width = 58 })
  cost:SetPoint("RIGHT", tracked, "LEFT", -12, 0)
  local percent = Widgets.Text(row, "secondaryBright", "", { justify = "RIGHT", width = 92 })
  percent:SetPoint("TOPRIGHT", cost, "TOPLEFT", -12, 10)
  local bar = Widgets.ProgressBar(row, 6, "gold")
  bar:SetWidth(92)
  bar:SetPoint("TOPRIGHT", percent, "BOTTOMRIGHT", 0, -4)
  local name = Widgets.Text(row, "body", "")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
  name:SetPoint("RIGHT", bar, "LEFT", -16, 0)
  local badge = Widgets.Badge(row, "Crafting", "text")
  badge:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 0)
  badge:SetHeight(14)
  local sub = Widgets.Text(row, "small", "")
  sub:SetPoint("LEFT", badge, "RIGHT", 8, 0)
  sub:SetPoint("RIGHT", bar, "LEFT", -16, 0)
  row.number, row.icon, row.tracked, row.cost, row.percent, row.bar, row.name, row.badge, row.sub =
    number, icon, tracked, cost, percent, bar, name, badge, sub
  row:SetScript("OnClick", function(self)
    if self.goalID then ns.GoalService.Select(self.goalID) end
  end)
  Widgets.SetItemTooltip(row, function(self) return self.itemID end)
  return row
end

local function createGroupRow(content)
  local row = Widgets.Frame(content, nil, { bg = C.sidebar })
  row:SetHeight(GROUP_ROW)
  local arrow = Widgets.Arrow(row, 8, "down", C.gold)
  arrow:SetPoint("LEFT", row, "LEFT", 10, 0)
  local label = Widgets.Text(row, "label", "", { caps = true, color = C.text })
  label:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
  local count = Widgets.Text(row, "small", "")
  count:SetPoint("LEFT", label, "RIGHT", 8, 0)
  row.label, row.count = label, count
  return row
end

local function createSettings(screen)
  local panel = Widgets.Panel(screen, "Goal Settings", { pad = 0 })
  panel:SetWidth(252)
  local body = panel.body
  local icon = Widgets.ItemIcon(body, 40)
  icon:SetPoint("TOPLEFT", body, "TOPLEFT", 14, -14)
  local name = Widgets.Text(body, "body", "")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
  name:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  local meta = Widgets.Text(body, "small", "")
  meta:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
  meta:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  local open = Widgets.Text(body, "small", "Open details >", { color = C.info })
  open:SetPoint("TOPLEFT", meta, "BOTTOMLEFT", 0, -2)
  local openButton = CreateFrame("Button", nil, body)
  openButton:SetAllPoints(open)
  openButton:SetScript("OnClick", function()
    if panel.goalID then ns.UI.MainFrame.OpenGoal(panel.goalID) end
  end)

  local function field(labelText, anchor, offset)
    local label = Widgets.Text(body, "label", labelText, { caps = true })
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offset or -14)
    return label
  end
  local quantityLabel = field("Quantity", icon, -18)
  local stepper = Widgets.Stepper(body, function(value)
    if not panel.goalID then return end
    if panel.goal and panel.goal.type == "REACH_SKILL" then
      ns.GoalService.SetRank(panel.goalID, value)
    elseif panel.goal and GoalModel.Types[panel.goal.type] and (GoalModel.Types[panel.goal.type].targetKind == "item" or panel.goal.type == "APPLY_ENCHANT") then
      ns.GoalService.SetQuantity(panel.goalID, value)
    end
  end)
  stepper:SetPoint("TOPLEFT", quantityLabel, "BOTTOMLEFT", 0, -6)

  local priorityLabel = field("Priority", stepper)
  local priority = Widgets.Dropdown(body, "1 - Highest", 224, function(self)
    if not panel.goalID then return end
    local openGoals = ns.GoalService.List({ open = true })
    local items = {}
    for index = 1, #openGoals do
      items[index] = { text = tostring(index) .. (index == 1 and " - Highest" or (index == #openGoals and " - Lowest" or "")), value = index, selected = panel.goal and panel.goal.priority == index }
    end
    Widgets.Menu(self, items, function(position)
      ns.GoalService.SetPriority(panel.goalID, position)
    end)
  end)
  priority:SetPoint("TOPLEFT", priorityLabel, "BOTTOMLEFT", 0, -6)

  local statusLabel = field("Status", priority)
  local status = Widgets.Segment(body, {
    { key = "ACTIVE", label = "Active" }, { key = "QUEUED", label = "Queued" }, { key = "PAUSED", label = "Paused" },
  }, function(key)
    if panel.goalID then ns.GoalService.SetStatus(panel.goalID, key) end
  end)
  status:SetPoint("TOPLEFT", statusLabel, "BOTTOMLEFT", 0, -6)

  local scopeLabel = field("Count materials from", status)
  local scope = Widgets.Segment(body, {
    { key = "character", label = "This character" }, { key = "account", label = "Account", disabled = true },
  })
  scope:SetPoint("TOPLEFT", scopeLabel, "BOTTOMLEFT", 0, -6)

  local routeLabel = field("Route", scope)
  local route = Widgets.Dropdown(body, "Default routes", 224, function(self)
    if not panel.goalID then return end
    local result = panel.craftwise
    local mode = ns.CraftWise.Mode(result, panel.goal and panel.goal.routes)
    local items = {
      { text = "Default routes (craft what you know)", value = "default", selected = mode == "default" },
      { text = result and result.hybrid.cost and ("CraftWise hybrid - " .. Widgets.Money(result.hybrid.cost, true)) or "CraftWise hybrid (no price data)", value = "hybrid", selected = mode == "hybrid" },
      { text = result and result.craft.cost and ("Buy all materials - " .. Widgets.Money(result.craft.cost, true)) or "Buy all materials", value = "buyall", selected = mode == "buyall" },
    }
    Widgets.Menu(self, items, function(value)
      panel:ApplyRouteMode(value)
    end)
  end)
  route:SetPoint("TOPLEFT", routeLabel, "BOTTOMLEFT", 0, -6)
  panel.route = route

  function panel:ApplyRouteMode(mode)
    if not self.goalID then return end
    local goalID, result = self.goalID, self.craftwise
    local plan = {}
    if mode == "hybrid" and result then
      plan = result.plan
    elseif mode == "buyall" and result then
      plan = ns.CraftWise.BuyAllPlan(result)
    end
    -- Clear every current override, then apply the preset.
    for itemID in pairs(self.goal and self.goal.routes or {}) do
      if plan[itemID] == nil then ns.GoalService.SetRoute(goalID, itemID, nil) end
    end
    for itemID, value in pairs(plan) do
      ns.GoalService.SetRoute(goalID, itemID, value == "buy" and "buy" or nil)
    end
    local labels = { default = "Default routes restored.", hybrid = "CraftWise hybrid plan applied.", buyall = "Buying every material." }
    ns.UI.MainFrame.SetStatus(labels[mode] or "Routes updated.", "ok")
    ns.UI.MainFrame.RequestRefresh()
  end

  local tracker = Widgets.Checkbox(body, "Show in tracker", function(checked)
    if panel.goalID then ns.GoalService.SetTracked(panel.goalID, checked) end
  end)
  tracker:SetPoint("TOPLEFT", route, "BOTTOMLEFT", 0, -14)
  local reserve = Widgets.Checkbox(body, "Reserve owned materials")
  reserve:SetPoint("TOPLEFT", tracker, "BOTTOMLEFT", 0, -8)
  reserve:SetEnabledState(false)
  local alert = Widgets.Checkbox(body, "Alert when ready to craft")
  alert:SetPoint("TOPLEFT", reserve, "BOTTOMLEFT", 0, -8)
  alert:SetEnabledState(false)

  local delete = Widgets.Button(body, "Delete", { width = 70, onClick = function()
    if panel.goalID then
      ns.GoalService.Remove(panel.goalID)
      ns.UI.MainFrame.SetStatus("Goal deleted.", "info")
    end
  end })
  delete:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 12)
  Widgets.SetTextColor(delete.label, C.missing)
  delete.textColor = C.missing
  local complete = Widgets.Button(body, "Mark complete", { onClick = function()
    if not panel.goalID or not panel.goal then return end
    if GoalModel.IsOpen(panel.goal) then
      ns.GoalService.SetStatus(panel.goalID, "COMPLETED")
      ns.UI.MainFrame.SetStatus("Goal marked complete.", "ok")
    else
      ns.GoalService.SetStatus(panel.goalID, "ACTIVE")
      ns.UI.MainFrame.SetStatus("Goal reopened.", "ok")
    end
  end })
  complete:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 12, 12)
  complete:SetPoint("RIGHT", delete, "LEFT", -8, 0)

  panel.empty = Widgets.EmptyState(body, "No goal selected", "Pick a goal from the list to configure it.")
  panel.empty:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -40)
  panel.empty:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -40)
  panel.empty:SetHeight(80)
  panel.controls = { icon, name, meta, open, quantityLabel, stepper, priorityLabel, priority, statusLabel, status, scopeLabel, scope, routeLabel, route, tracker, reserve, alert, delete, complete }
  panel.icon, panel.name, panel.meta, panel.stepper, panel.priority, panel.status, panel.tracker, panel.complete = icon, name, meta, stepper, priority, status, tracker, complete

  function panel:SetGoal(goal, view)
    self.goal = goal
    self.goalID = goal and goal.id or nil
    for _, control in ipairs(self.controls) do
      if goal then control:Show() else control:Hide() end
    end
    if not goal then
      self.empty:Show()
      return
    end
    self.empty:Hide()
    local item = view and view.item or (goal.target.itemID and ns.ItemProvider.GetItem(goal.target.itemID)) or { icon = goal.target.icon, quality = 1 }
    icon:SetItem(item.icon, item.quality)
    name:SetText(Theme.QualityText(ns.GoalService.Name(goal), item.quality))
    local added = type(date) == "function" and goal.createdAt and date("%d %b", goal.createdAt) or ""
    meta:SetText(string.format("%s - added %s", GoalModel.Types[goal.type].badge, added))
    local kind = GoalModel.Types[goal.type].targetKind
    if goal.type == "REACH_SKILL" then
      quantityLabel:SetText(Theme.Upper("Target skill"))
      stepper:SetValue(goal.target.rank or 1)
      stepper:SetEnabledState(true)
    else
      quantityLabel:SetText(Theme.Upper(goal.type == "APPLY_ENCHANT" and "Casts" or "Quantity"))
      stepper:SetValue(goal.target.quantity or 1)
      stepper:SetEnabledState(kind == "item" or goal.type == "APPLY_ENCHANT")
    end
    priority:SetLabel(string.format("%d%s", goal.priority or 1, (goal.priority or 1) == 1 and " - Highest" or ""))
    local isOpen = GoalModel.IsOpen(goal)
    priority:SetEnabledState(isOpen)
    if isOpen then status:Select(goal.status) end
    tracker:SetChecked(goal.tracked)
    complete:SetLabel(isOpen and "Mark complete" or "Reopen goal")
    local tree = view and (view.fullTree or view.tree)
    self.craftwise = tree and ns.CraftWise.Compare(tree, { priceOf = ns.PriceProvider.GetPrice, marketOf = ns.PriceProvider.GetMarket }) or nil
    local mode = ns.CraftWise.Mode(self.craftwise, goal.routes)
    local result = self.craftwise
    if mode == "hybrid" then
      route:SetLabel("CraftWise hybrid" .. (result and result.hybrid.cost and (" - " .. Widgets.Money(result.hybrid.cost, true)) or ""))
    elseif mode == "buyall" then
      route:SetLabel("Buy all materials" .. (result and result.craft.cost and (" - " .. Widgets.Money(result.craft.cost, true)) or ""))
    elseif mode == "custom" then
      route:SetLabel("Custom routes")
    else
      route:SetLabel("Default routes")
    end
    route:SetEnabledState(tree ~= nil)
  end
  panel:SetGoal(nil)
  return panel
end

local function Create(parent)
  local screen = CreateFrame("Frame", nil, parent)
  local newGoal = createNewGoalBar(screen)
  screen.newGoal = newGoal

  local settings = createSettings(screen)
  settings:SetPoint("TOPRIGHT", newGoal, "BOTTOMRIGHT", 0, -10)
  settings:SetPoint("BOTTOMRIGHT", screen, "BOTTOMRIGHT", 0, 0)
  screen.settings = settings

  local list = Widgets.Panel(screen, nil, { pad = 0 })
  list:SetPoint("TOPLEFT", newGoal, "BOTTOMLEFT", 0, -10)
  list:SetPoint("BOTTOMRIGHT", settings, "BOTTOMLEFT", -10, 0)
  local body = list.body

  local tabs = Widgets.Tabs(body, { { key = "open", label = "Open" }, { key = "completed", label = "Completed" } }, function(key)
    screen.tab = key
    screen:Refresh()
  end)
  tabs:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -8)
  tabs:SetPoint("TOPRIGHT", body, "TOPRIGHT", -180, -8)
  screen.tabs = tabs
  screen.tab = "open"
  local sort = Widgets.Dropdown(body, sortLabel("priority"), 160, function(self)
    local current = ns.chardb and ns.chardb.ui.goalSort or "priority"
    local items = {}
    for _, s in ipairs(SORTS) do items[#items + 1] = { text = s.label:gsub("Sort: ", ""), value = s.key, selected = s.key == current } end
    Widgets.Menu(self, items, function(value)
      if ns.chardb then ns.chardb.ui.goalSort = value end
      self:SetLabel(sortLabel(value))
      screen:Refresh()
    end)
  end)
  sort:SetPoint("TOPRIGHT", body, "TOPRIGHT", -10, -8)
  screen.sort = sort

  local header = Widgets.Frame(body, nil, { bg = C.sidebar })
  header:SetHeight(26)
  header:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", -10, -6)
  header:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -42)
  local headerLine = Widgets.HLine(header, C.black, 1)
  headerLine:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
  headerLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  local hNumber = Widgets.Text(header, "tableHeader", "#", { caps = true })
  hNumber:SetPoint("LEFT", header, "LEFT", 16, 0)
  local hGoal = Widgets.Text(header, "tableHeader", "Goal", { caps = true })
  hGoal:SetPoint("LEFT", header, "LEFT", 80, 0)
  local hTracked = Widgets.Text(header, "tableHeader", "Trk", { caps = true, justify = "RIGHT" })
  hTracked:SetPoint("RIGHT", header, "RIGHT", -10, 0)
  local hCost = Widgets.Text(header, "tableHeader", "Est. cost", { caps = true, justify = "RIGHT", width = 58 })
  hCost:SetPoint("RIGHT", hTracked, "LEFT", -14, 0)
  local hProgress = Widgets.Text(header, "tableHeader", "Progress", { caps = true, justify = "RIGHT", width = 92 })
  hProgress:SetPoint("RIGHT", hCost, "LEFT", -12, 0)

  local scroll = Widgets.ScrollArea(body)
  scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
  scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 26)
  screen.scroll = scroll
  screen.rowPool = Widgets.Pool(scroll.content, createGoalRow)
  screen.groupPool = Widgets.Pool(scroll.content, createGroupRow)

  local footer = Widgets.Frame(body, nil, { bg = C.sidebar })
  footer:SetHeight(26)
  footer:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
  footer:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
  local footerText = Widgets.Text(footer, "small", "Click a goal to configure it")
  footerText:SetPoint("LEFT", footer, "LEFT", 12, 0)
  local footerRight = Widgets.Text(footer, "small", "TRK = shown in tracker", { justify = "RIGHT" })
  footerRight:SetPoint("RIGHT", footer, "RIGHT", -12, 0)

  screen.empty = Widgets.EmptyState(body, "No goals here", "Add a crafting goal above.")
  screen.empty:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -40)
  screen.empty:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -40)
  screen.empty:SetHeight(80)

  -- Type-ahead for the selected kind; a pick adds the goal with the stepper's quantity.
  function screen:UpdateSuggestions()
    local MainFrame = ns.UI.MainFrame
    local text = Util.Trim(newGoal.input:GetText() or "")
    local kind = newGoal.segment and newGoal.segment.selected or "item"
    if #text < 2 or text:find("|H", 1, true) or (kind == "item" and Util.ParseInt(text)) then
      MainFrame.HideSuggestions()
      return
    end
    MainFrame.ShowSuggestions(newGoal.input, ns.GoalService.Suggest(kind, text, 8), {
      quantity = function() return newGoal.stepper:GetValue() end,
      onAdd = function(ok)
        if not ok then return end
        newGoal.input:SetText("")
        newGoal.input:ClearFocus()
        newGoal.stepper:SetValue(1)
        screen:Refresh()
      end,
    })
  end

  function screen:Submit()
    ns.UI.MainFrame.HideSuggestions()
    local text = newGoal.input:GetText() or ""
    local kind = newGoal.segment and newGoal.segment.selected or "item"
    if Util.Trim(text) == "" then
      ns.UI.MainFrame.SetStatus(kind == "attunement" and "Type an attunement name, or pick one on the Attunements screen." or "Enter an item ID, Shift-click an item link, or type an item name.", "info")
      return false
    end
    local ok, message
    if kind == "attunement" then
      ok, message = ns.GoalService.AddAttunementFromInput(text)
    elseif kind == "recipe" then
      ok, message = ns.GoalService.AddRecipeFromInput(text)
    elseif kind == "enchant" then
      ok, message = ns.GoalService.AddEnchantFromInput(text, newGoal.stepper:GetValue())
    elseif kind == "skill" then
      ok, message = ns.GoalService.AddSkillFromInput(text)
    elseif kind == "quest" then
      ok, message = ns.GoalService.AddQuestFromInput(text)
    elseif kind == "reputation" then
      ok, message = ns.GoalService.AddReputationFromInput(text)
    else
      ok, message = ns.GoalService.AddFromInput(text, newGoal.stepper:GetValue())
    end
    ns.UI.MainFrame.SetStatus(message, ok and "ok" or "error")
    if ok then
      newGoal.input:SetText("")
      newGoal.input:ClearFocus()
      newGoal.stepper:SetValue(1)
    end
    return ok
  end

  local function sortedGoals(goals, views, sortKey)
    if sortKey == "name" then
      table.sort(goals, function(a, b) return ns.GoalService.Name(a) < ns.GoalService.Name(b) end)
    elseif sortKey == "progress" then
      table.sort(goals, function(a, b)
        return (ns.Overview.Percent(views[a.id]) or -1) > (ns.Overview.Percent(views[b.id]) or -1)
      end)
    end
    return goals
  end

  function screen:Refresh()
    local MainFrame = ns.UI.MainFrame
    local views = MainFrame.views
    local openCount = ns.GoalService.Count({ open = true })
    local completedCount = ns.GoalService.Count({ status = "COMPLETED" })
    tabs:SetLabel("open", string.format("Open - %d", openCount))
    tabs:SetLabel("completed", string.format("Completed - %d", completedCount))
    local sortKey = ns.chardb and ns.chardb.ui.goalSort or "priority"
    sort:SetLabel(sortLabel(sortKey))

    local selected = ns.GoalService.GetSelected()
    local y = 0
    local rowIndex, groupIndex = 0, 0
    local groups
    if self.tab == "completed" then
      groups = { { key = "COMPLETED", label = "Completed", goals = sortedGoals(ns.GoalService.List({ status = "COMPLETED" }), views, sortKey) } }
    else
      groups = {}
      for _, status in ipairs({ "ACTIVE", "QUEUED", "PAUSED" }) do
        local goals = sortedGoals(ns.GoalService.List({ status = status }), views, sortKey)
        if #goals > 0 then
          groups[#groups + 1] = { key = status, label = GoalModel.StatusLabel[status], goals = goals }
        end
      end
    end
    local total = 0
    for _, group in ipairs(groups) do
      groupIndex = groupIndex + 1
      local groupRow = self.groupPool:Get(groupIndex)
      groupRow:ClearAllPoints()
      groupRow:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -y)
      groupRow:SetPoint("TOPRIGHT", scroll.content, "TOPRIGHT", 0, -y)
      groupRow.label:SetText(Theme.Upper(group.label))
      groupRow.count:SetText(tostring(#group.goals))
      y = y + GROUP_ROW
      for _, goal in ipairs(group.goals) do
        total = total + 1
        rowIndex = rowIndex + 1
        local row = self.rowPool:Get(rowIndex)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", scroll.content, "TOPRIGHT", 0, -y)
        y = y + ROW
        local view = views[goal.id]
        local item = view and view.item or (goal.target.itemID and ns.ItemProvider.GetItem(goal.target.itemID)) or { icon = goal.target.icon, quality = 1 }
        row.goalID = goal.id
        row.itemID = goal.target.itemID
        row.number:SetText(goal.priority and tostring(goal.priority) or "")
        row.icon:SetItem(item.icon, item.quality)
        local quantity = (goal.target.itemID or goal.type == "APPLY_ENCHANT") and goal.target.quantity or 1
        row.name:SetText(Theme.QualityText(ns.GoalService.Name(goal), item.quality) .. (quantity > 1 and (Theme.Hex.text2 .. " x" .. quantity .. "|r") or ""))
        row.badge:SetBadge(view and view.obtain and "Item" or GoalModel.Types[goal.type].badge, "text")
        if view and view.attunement then
          local a = view.attunement
          row.sub:SetText(a.complete and "Attuned" or string.format("%d of %d steps%s", a.done, a.total, a.next and (" - next: " .. a.next.name) or ""))
        elseif view and view.skill then
          local s = view.skill
          row.sub:SetText(s.reached and "Reached" or string.format("%d of %d - %s", s.current, s.target, view.nextStep or ""))
        elseif view and view.quest then
          row.sub:SetText((view.quest.label or "") .. (view.nextStep and (" - " .. view.nextStep) or ""))
        elseif view and view.reputation then
          local p = view.reputation.progress
          row.sub:SetText(p.reached and (p.targetLabel .. " reached") or string.format("%s - %d to %s", view.reputation.record.standingLabel, p.remaining, p.targetLabel))
        elseif view and view.enchant then
          local e = view.enchant
          row.sub:SetText(e.remaining <= 0 and "All casts done" or string.format("%d of %d cast%s - %s", e.casts, e.quantity, e.quantity == 1 and "" or "s", view.nextStep or ""))
        elseif view and view.learn then
          row.sub:SetText(view.learn.learned and "Learned" or ((view.learn.recipe.professionName or "") .. (view.nextStep and (" - " .. view.nextStep) or "")))
        elseif view and view.questline and view.plan and not view.plan.isComplete then
          row.sub:SetText("Quest reward" .. (view.nextStep and (" - " .. view.nextStep) or ""))
        elseif view and view.plan then
          row.sub:SetText(view.plan.isComplete and "Ready to craft" or string.format("%d of %d materials missing - %s", view.plan.totals.materialsMissing, #view.plan.materials, view.recipe and view.recipe.professionName or ""))
        else
          row.sub:SetText(view and (ns.StatusLabel[view.status] or "") or (goal.status == "COMPLETED" and ("Completed " .. Util.FormatAgo(goal.completedAt)) or ""))
        end
        local percent = ns.Overview.Percent(view)
        row.percent:SetText(percent and (percent .. "%") or (goal.status == "COMPLETED" and "100%" or "-"))
        row.bar:SetKind((percent == 100 or goal.status == "COMPLETED") and "ok" or "gold")
        row.bar:SetValue(goal.status == "COMPLETED" and 1 or (percent or 0) / 100)
        row.tracked:SetChecked(goal.tracked)
        if selected and selected.id == goal.id then
          Widgets.SetBackdrop(row, C.raised, C.bronzeDim)
        elseif row.SetBackdrop then
          row:SetBackdrop(nil)
        end
        row:SetAlpha(goal.status == "PAUSED" and 0.62 or 1)
      end
    end
    self.rowPool:HideFrom(rowIndex + 1)
    self.groupPool:HideFrom(groupIndex + 1)
    scroll:SetContentHeight(y)
    if total == 0 then self.empty:Show() else self.empty:Hide() end
    settings:SetGoal(selected, selected and views[selected.id] or nil)
  end

  return screen
end

ns.UI.Screens.goals = { label = "My Goals", Create = Create }
