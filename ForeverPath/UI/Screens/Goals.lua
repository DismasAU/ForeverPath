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
      ns.Compat.After(0.2, ns.UI.MainFrame.HideSuggestions)
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
  local row = Widgets.ListRow(content, { height = ROW, divider = 0.55, hover = 0.025 })
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
  return Widgets.GroupHeaderRow(content, { height = GROUP_ROW, arrow = true })
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
    ns.GoalService.SetAmount(panel.goalID, value)
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
    { key = GoalModel.Statuses.ACTIVE, label = GoalModel.StatusLabel.ACTIVE },
    { key = GoalModel.Statuses.QUEUED, label = GoalModel.StatusLabel.QUEUED },
    { key = GoalModel.Statuses.PAUSED, label = GoalModel.StatusLabel.PAUSED },
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
    ns.GoalService.ApplyRoutePreset(self.goalID, mode, self.craftwise)
    local labels = { default = "Default routes restored.", hybrid = "CraftWise hybrid plan applied.", buyall = "Buying every material." }
    ns.UI.MainFrame.SetAlert(labels[mode] or "Routes updated.", "ok")
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
      ns.UI.MainFrame.SetAlert("Goal deleted.", "info")
    end
  end })
  delete:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 12)
  Widgets.SetTextColor(delete.label, C.missing)
  delete.textColor = C.missing
  local complete = Widgets.Button(body, "Mark complete", { onClick = function()
    if not panel.goalID or not panel.goal then return end
    if GoalModel.IsOpen(panel.goal) then
      ns.GoalService.SetStatus(panel.goalID, GoalModel.Statuses.COMPLETED)
      ns.UI.MainFrame.SetAlert("Goal marked complete.", "ok")
    else
      ns.GoalService.SetStatus(panel.goalID, GoalModel.Statuses.ACTIVE)
      ns.UI.MainFrame.SetAlert("Goal reopened.", "ok")
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
    local amount, value = GoalModel.Amount(goal)
    quantityLabel:SetText(Theme.Upper(amount and amount.label or "Quantity"))
    stepper:SetValue(value or 1)
    stepper:SetEnabledState(amount ~= nil)
    priority:SetLabel(string.format("%d%s", goal.priority or 1, (goal.priority or 1) == 1 and " - Highest" or ""))
    local isOpen = GoalModel.IsOpen(goal)
    priority:SetEnabledState(isOpen)
    if isOpen then status:Select(goal.status) end
    tracker:SetChecked(goal.tracked)
    complete:SetLabel(isOpen and "Mark complete" or "Reopen goal")
    self.craftwise = view and view.craftwise or nil
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
  local sort = Widgets.Dropdown(body, Widgets.SortLabel(SORTS, "priority"), 160, function(self)
    local current = ns.chardb.ui.goalSort
    local items = {}
    for _, s in ipairs(SORTS) do items[#items + 1] = { text = s.label:gsub("Sort: ", ""), value = s.key, selected = s.key == current } end
    Widgets.Menu(self, items, function(value)
      ns.chardb.ui.goalSort = value
      self:SetLabel(Widgets.SortLabel(SORTS, value))
      screen:Refresh()
    end)
  end)
  sort:SetPoint("TOPRIGHT", body, "TOPRIGHT", -10, -8)
  screen.sort = sort

  local header = Widgets.TableHeader(body, {
    { "Trk", nil, "RIGHT", 14 }, { "Est. cost", 58, "RIGHT", 12 }, { "Progress", 92, "RIGHT" },
  }, { "Goal", 80 })
  -- Below the status tabs rather than at the top of the panel.
  header:ClearAllPoints()
  header:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", -10, -6)
  header:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -42)
  local hNumber = Widgets.Text(header, "tableHeader", "#", { caps = true })
  hNumber:SetPoint("LEFT", header, "LEFT", 16, 0)

  local scroll = Widgets.TableScroll(body, header, nil, 26)
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
      onAdd = function(goal)
        if not goal then return end
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
      ns.UI.MainFrame.SetAlert(kind == "attunement" and "Type an attunement name, or pick one on the Attunements screen." or "Enter an item ID, Shift-click an item link, or type an item name.", "info")
      return false
    end
    local goal, message = ns.GoalService.AddByKind(kind, text, newGoal.stepper:GetValue())
    ns.UI.MainFrame.SetAlert(message, goal and "ok" or "error")
    if goal then
      newGoal.input:SetText("")
      newGoal.input:ClearFocus()
      newGoal.stepper:SetValue(1)
    end
    return goal ~= nil
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
    local views = ns.GoalService.Views()
    local openCount = ns.GoalService.Count({ open = true })
    local completedCount = ns.GoalService.Count({ status = GoalModel.Statuses.COMPLETED })
    tabs:SetLabel("open", string.format("Open - %d", openCount))
    tabs:SetLabel("completed", string.format("Completed - %d", completedCount))
    local sortKey = ns.chardb.ui.goalSort
    sort:SetLabel(Widgets.SortLabel(SORTS, sortKey))

    local selected = ns.GoalService.GetSelected()
    local y = 0
    local rowIndex, groupIndex = 0, 0
    local groups
    if self.tab == "completed" then
      groups = { { key = GoalModel.Statuses.COMPLETED, label = GoalModel.StatusLabel.COMPLETED, goals = sortedGoals(ns.GoalService.List({ status = GoalModel.Statuses.COMPLETED }), views, sortKey) } }
    else
      groups = {}
      for _, status in ipairs({ GoalModel.Statuses.ACTIVE, GoalModel.Statuses.QUEUED, GoalModel.Statuses.PAUSED }) do
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
        local quantity = GoalModel.ShownQuantity(goal)
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
          row.sub:SetText(view and (ns.Readiness.Label(view.readiness) or "") or (goal.status == GoalModel.Statuses.COMPLETED and ("Completed " .. Util.FormatAgo(goal.completedAt)) or ""))
        end
        local percent = ns.Overview.Percent(view)
        row.percent:SetText(percent and (percent .. "%") or (goal.status == GoalModel.Statuses.COMPLETED and "100%" or "-"))
        row.bar:SetKind((percent == 100 or goal.status == GoalModel.Statuses.COMPLETED) and "ok" or "gold")
        row.bar:SetValue(goal.status == GoalModel.Statuses.COMPLETED and 1 or (percent or 0) / 100)
        row.tracked:SetChecked(goal.tracked)
        if selected and selected.id == goal.id then
          Widgets.SetBackdrop(row, C.raised, C.bronzeDim)
        elseif row.SetBackdrop then
          row:SetBackdrop(nil)
        end
        row:SetAlpha(goal.status == GoalModel.Statuses.PAUSED and 0.62 or 1)
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
