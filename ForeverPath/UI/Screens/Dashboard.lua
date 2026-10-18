-- Screen 01: goals, blockers and the next step at a glance.
local _, ns = ...

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets
local C = Theme.Colors
local Util = ns.Util

ns.UI.Screens = ns.UI.Screens or {}

local GOAL_ROW = 84
local STEP_ROW = 56
local MATERIAL_ROW = 31

local function statCell(parent, label)
  local cell = CreateFrame("Frame", nil, parent)
  local title = Widgets.Text(cell, "label", label, { caps = true })
  title:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
  local value = Widgets.Text(cell, "bigNumber", "")
  value:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  value:SetPoint("RIGHT", cell, "RIGHT", -8, 0)   -- bounded: truncates instead of overhanging
  local sub = Widgets.Text(cell, "small", "")
  sub:SetPoint("TOPLEFT", value, "BOTTOMLEFT", 0, -3)
  sub:SetPoint("RIGHT", cell, "RIGHT", -8, 0)
  local bar = Widgets.ProgressBar(cell, 6, "gold")
  bar:SetPoint("TOPLEFT", value, "BOTTOMLEFT", 0, -5)
  bar:SetPoint("RIGHT", cell, "RIGHT", -12, 0)
  bar:Hide()
  cell.title, cell.value, cell.sub, cell.bar = title, value, sub, bar
  return cell
end

local function createCharacterStrip(screen)
  local strip = Widgets.Panel(screen, nil, { pad = 0 })
  strip:SetHeight(78)
  strip:SetPoint("TOPLEFT", screen, "TOPLEFT", 0, 0)
  strip:SetPoint("TOPRIGHT", screen, "TOPRIGHT", 0, 0)
  local body = strip.body

  local portrait = Widgets.Frame(body, nil, { bg = C.black, border = C.bronze })
  portrait:SetSize(46, 46)
  portrait:SetPoint("LEFT", body, "LEFT", 14, 0)
  local portraitTexture = portrait:CreateTexture(nil, "ARTWORK")
  portraitTexture:SetPoint("TOPLEFT", portrait, "TOPLEFT", 1, -1)
  portraitTexture:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -1, 1)
  strip.portrait = portraitTexture

  local name = Widgets.Text(body, "hero", "")
  name:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 14, -2)
  local meta = Widgets.Text(body, "secondary", "")
  meta:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
  strip.name, strip.meta = name, meta

  strip.cells = {}
  strip.dividers = {}
  local anchor = nil
  for i = 1, 4 do
    local divider = Widgets.Engraved(body, true)
    divider:SetHeight(50)
    local cell = statCell(body, "")
    cell:SetSize(150, 50)
    if i > 1 then
      divider:SetPoint("LEFT", anchor, "RIGHT", 0, 0)
    end
    cell:SetPoint("LEFT", divider, "RIGHT", 12, 0)
    cell:SetPoint("TOP", body, "TOP", 0, -14)
    anchor = cell
    strip.cells[i] = cell
    strip.dividers[i] = divider
  end
  name:SetPoint("RIGHT", strip.dividers[1], "LEFT", -10, 0)
  meta:SetPoint("RIGHT", strip.dividers[1], "LEFT", -10, 0)

  -- Stat cells shrink before the name block does.
  function strip:Layout()
    local width = body:GetWidth() or 0
    if width <= 0 then return end
    local cellWidth = Util.Clamp(math.floor((width - 300) / 4), 96, 150)
    for _, cell in ipairs(self.cells) do cell:SetWidth(cellWidth) end
    self.dividers[1]:ClearAllPoints()
    self.dividers[1]:SetPoint("LEFT", body, "LEFT", width - 4 * (cellWidth + 12) - 2, 0)
  end
  body:SetScript("OnSizeChanged", function() strip:Layout() end)
  strip:Layout()
  return strip
end

local function createGoalRow(content, index)
  local row = Widgets.Frame(content, nil, { frameType = "Button", bg = C.sidebar, border = Theme.RGB("#33302A") })
  row:SetHeight(GOAL_ROW - 8)
  row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * GOAL_ROW)
  row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * GOAL_ROW)
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(row)
  Widgets.SetColor(highlight, C.white, 0.03)
  local icon = Widgets.ItemIcon(row, 42)
  icon:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -12)
  local name = Widgets.Text(row, "goalName", "")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 14, 0)
  name:SetWidth(260)
  local badge = Widgets.Badge(row, "Crafting", "text")
  badge:SetPoint("LEFT", name, "RIGHT", 10, 0)
  local percent = Widgets.Text(row, "bigNumber", "", { color = C.text, justify = "RIGHT" })
  percent:SetPoint("TOPRIGHT", row, "TOPRIGHT", -14, -10)
  local bar = Widgets.ProgressBar(row, 8, "gold")
  bar:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -8)
  bar:SetPoint("RIGHT", row, "RIGHT", -14, 0)
  local detail = Widgets.Text(row, "secondary", "", { color = C.partial })
  detail:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
  detail:SetPoint("RIGHT", row, "RIGHT", -150, 0)
  local meta = Widgets.Text(row, "secondary", "", { justify = "RIGHT" })
  meta:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
  row.icon, row.name, row.badge, row.percent, row.bar, row.detail, row.meta = icon, name, badge, percent, bar, detail, meta
  row:SetScript("OnClick", function(self)
    if self.goalID then ns.UI.MainFrame.OpenGoal(self.goalID) end
  end)
  Widgets.ShiftClickLinks(row, function(self) return self.itemID end)
  Widgets.SetItemTooltip(row, function(self) return self.itemID end)
  return row
end

local function createStepRow(content, index)
  local row = CreateFrame("Frame", nil, content)
  row:SetHeight(STEP_ROW)
  row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * STEP_ROW)
  row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * STEP_ROW)
  local line = Widgets.HLine(row, C.black, 0.45)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  local circle = Widgets.Frame(row, nil, { bg = C.black, border = C.bronzeDim })
  circle:SetSize(24, 24)
  circle:SetPoint("LEFT", row, "LEFT", 6, 0)
  local number = Widgets.Text(circle, "goalName", tostring(index), { color = C.gold, justify = "CENTER" })
  number:SetPoint("CENTER", circle, "CENTER", 0, 0)
  local title = Widgets.Text(row, "body", "")
  title:SetPoint("TOPLEFT", circle, "TOPRIGHT", 12, 10)
  title:SetPoint("RIGHT", row, "RIGHT", -150, 0)
  local detail = Widgets.Text(row, "secondary", "")
  detail:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  detail:SetPoint("RIGHT", row, "RIGHT", -150, 0)
  local badge = Widgets.Badge(row, "", "ok")
  badge:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.title, row.detail, row.badge = title, detail, badge
  return row
end

local function createMaterialRow(content, index)
  local row = CreateFrame("Button", nil, content)
  row:SetHeight(MATERIAL_ROW)
  row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * MATERIAL_ROW)
  row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * MATERIAL_ROW)
  local line = Widgets.HLine(row, C.black, 0.45)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(row)
  Widgets.SetColor(highlight, C.white, 0.03)
  local icon = Widgets.ItemIcon(row, 22)
  icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  local count = Widgets.Text(row, "body", "", { color = C.missing, justify = "RIGHT" })
  count:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  local name = Widgets.Text(row, "secondaryBright", "")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 0)
  name:SetPoint("RIGHT", count, "LEFT", -6, 0)
  local source = Widgets.Text(row, "note", "")
  source:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 0)
  source:SetPoint("RIGHT", count, "LEFT", -6, 0)
  row.icon, row.name, row.source, row.count = icon, name, source, count
  Widgets.SetItemTooltip(row, function(self) return self.itemID end, function(self)
    return self.goals and { "Needed for: " .. Util.Join(self.goals) } or nil
  end)
  Widgets.ShiftClickLinks(row, function(self) return self.itemID end)
  return row
end

local function Create(parent)
  local screen = CreateFrame("Frame", nil, parent)
  local strip = createCharacterStrip(screen)
  screen.strip = strip

  -- Right column
  local missingPanel = Widgets.Panel(screen, "Missing Materials", { pad = 0 })
  missingPanel:SetWidth(268)
  missingPanel:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, -10)
  local craftwise = Widgets.Panel(screen, "CraftWise")
  craftwise:SetWidth(268)
  craftwise:SetHeight(226)
  craftwise:SetPoint("BOTTOMRIGHT", screen, "BOTTOMRIGHT", 0, 0)
  missingPanel:SetPoint("BOTTOMRIGHT", craftwise, "TOPRIGHT", 0, 10)
  local missingCount = Widgets.Text(missingPanel.header, "small", "", { justify = "RIGHT" })
  missingCount:SetPoint("RIGHT", missingPanel.header, "RIGHT", -10, 0)
  missingPanel.count = missingCount
  local missingScroll = Widgets.ScrollArea(missingPanel.body)
  missingScroll:SetPoint("TOPLEFT", missingPanel.body, "TOPLEFT", 6, -4)
  missingScroll:SetPoint("BOTTOMRIGHT", missingPanel.body, "BOTTOMRIGHT", -6, 30)
  missingPanel.scroll = missingScroll
  missingPanel.pool = Widgets.Pool(missingScroll.content, createMaterialRow)
  missingPanel.empty = Widgets.EmptyState(missingPanel.body, "Nothing missing", "Active goals have everything they need.")
  missingPanel.empty:SetPoint("TOPLEFT", missingPanel.body, "TOPLEFT", 0, -20)
  missingPanel.empty:SetPoint("TOPRIGHT", missingPanel.body, "TOPRIGHT", 0, -20)
  missingPanel.empty:SetHeight(80)
  local shopping = Widgets.Text(missingPanel.body, "small", "Open shopping list >", { color = C.info })
  shopping:SetPoint("BOTTOMLEFT", missingPanel.body, "BOTTOMLEFT", 12, 9)
  local shoppingButton = CreateFrame("Button", nil, missingPanel.body)
  shoppingButton:SetAllPoints(shopping)
  shoppingButton:SetScript("OnClick", function() ns.UI.MainFrame.ShowScreen("shopping") end)
  missingPanel.shoppingLink = shoppingButton
  screen.missingPanel = missingPanel

  local craftwiseEmpty = Widgets.EmptyState(craftwise.body, "No price data",
    "CraftWise compares buying the item, buying materials and crafting intermediates from your vendor records and Auctionator scans.")
  craftwiseEmpty:SetPoint("TOPLEFT", craftwise.body, "TOPLEFT", 0, -36)
  craftwiseEmpty:SetPoint("TOPRIGHT", craftwise.body, "TOPRIGHT", 0, -36)
  craftwiseEmpty:SetHeight(120)
  craftwise.empty = craftwiseEmpty
  local cwTotal = Widgets.Text(craftwise.body, "bigNumberLarge", "", { color = C.gold })
  cwTotal:SetPoint("TOPLEFT", craftwise.body, "TOPLEFT", 12, -10)
  local cwSub = Widgets.Text(craftwise.body, "small", "", { color = C.ok })
  cwSub:SetPoint("TOPLEFT", cwTotal, "BOTTOMLEFT", 0, -2)
  craftwise.total, craftwise.sub = cwTotal, cwSub
  craftwise.rows = {}
  local previous = cwSub
  for i, label in ipairs({ "Buy finished item", "Buy all materials", "Hybrid - recommended" }) do
    local row = CreateFrame("Frame", nil, craftwise.body)
    row:SetHeight(20)
    row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, i == 1 and -10 or -2)
    row:SetPoint("RIGHT", craftwise.body, "RIGHT", -12, 0)
    row.label = Widgets.Text(row, "secondary", label)
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.value = Widgets.Text(row, "secondaryBright", "", { justify = "RIGHT" })
    row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    craftwise.rows[i] = row
    previous = row
  end
  local cwDot = Widgets.Dot(craftwise.body, "info")
  cwDot:SetPoint("BOTTOMLEFT", craftwise.body, "BOTTOMLEFT", 12, 18)
  local cwScan = Widgets.Text(craftwise.body, "small", "")
  cwScan:SetPoint("LEFT", cwDot, "RIGHT", 6, 0)
  craftwise.dot, craftwise.scan = cwDot, cwScan
  local compare = Widgets.Button(craftwise.body, "Compare", { width = 90, onClick = function()
    if craftwise.goalID then
      ns.GoalService.Select(craftwise.goalID)
      ns.UI.MainFrame.ShowScreen("crafting")
      local crafting = ns.UI.MainFrame.screens.crafting
      if crafting and crafting.tabs then
        crafting.tabs:Select("craftwise")
        crafting.tab = "craftwise"
        crafting:Refresh()
      end
    end
  end })
  compare:SetPoint("BOTTOMRIGHT", craftwise.body, "BOTTOMRIGHT", -10, 10)
  craftwise.compare = compare
  craftwise.content = { cwTotal, cwSub, craftwise.rows[1], craftwise.rows[2], craftwise.rows[3], cwDot, cwScan }
  screen.craftwise = craftwise

  -- Left column
  local recommended = Widgets.Panel(screen, "Recommended Next", { pad = 0 })
  recommended:SetHeight(28 + 3 * STEP_ROW + 8)
  recommended:SetPoint("BOTTOMLEFT", screen, "BOTTOMLEFT", 0, 0)
  recommended:SetPoint("BOTTOMRIGHT", missingPanel, "BOTTOMLEFT", -10, 0)
  recommended:SetPoint("BOTTOMRIGHT", craftwise, "BOTTOMLEFT", -10, 0)
  local recommendedNote = Widgets.Text(recommended.header, "small", "Ordered by goal priority", { justify = "RIGHT" })
  recommendedNote:SetPoint("RIGHT", recommended.header, "RIGHT", -10, 0)
  recommended.pool = Widgets.Pool(recommended.body, createStepRow)
  recommended.empty = Widgets.EmptyState(recommended.body, "No steps yet", "Add a crafting goal and ForeverPath will suggest what to do first.")
  recommended.empty:SetPoint("TOPLEFT", recommended.body, "TOPLEFT", 0, -30)
  recommended.empty:SetPoint("TOPRIGHT", recommended.body, "TOPRIGHT", 0, -30)
  recommended.empty:SetHeight(80)
  screen.recommended = recommended

  local goalsPanel = Widgets.Panel(screen, "Active Goals", { pad = 0 })
  goalsPanel:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -10)
  goalsPanel:SetPoint("BOTTOMRIGHT", recommended, "TOPRIGHT", 0, 10)
  local manage = Widgets.Text(goalsPanel.header, "small", "Manage goals >", { color = C.info, justify = "RIGHT" })
  manage:SetPoint("RIGHT", goalsPanel.header, "RIGHT", -10, 0)
  local manageButton = CreateFrame("Button", nil, goalsPanel.header)
  manageButton:SetAllPoints(manage)
  manageButton:SetScript("OnClick", function() ns.UI.MainFrame.ShowScreen("goals") end)
  local goalsScroll = Widgets.ScrollArea(goalsPanel.body)
  goalsScroll:SetPoint("TOPLEFT", goalsPanel.body, "TOPLEFT", 10, -10)
  goalsScroll:SetPoint("BOTTOMRIGHT", goalsPanel.body, "BOTTOMRIGHT", -10, 8)
  goalsPanel.scroll = goalsScroll
  goalsPanel.pool = Widgets.Pool(goalsScroll.content, createGoalRow)
  goalsPanel.empty = Widgets.EmptyState(goalsPanel.body, "No active goals", "Type an item ID in the search box, Shift-click an item, or add one from My Goals.")
  goalsPanel.empty:SetPoint("TOPLEFT", goalsPanel.body, "TOPLEFT", 0, -40)
  goalsPanel.empty:SetPoint("TOPRIGHT", goalsPanel.body, "TOPRIGHT", 0, -40)
  goalsPanel.empty:SetHeight(80)
  screen.goalsPanel = goalsPanel

  function screen:Refresh()
    local MainFrame = ns.UI.MainFrame
    local info = MainFrame.CharacterInfo()
    strip.name:SetText(info.name)
    Widgets.SetTextColor(strip.name, info.color)
    local parts = {}
    if info.level and info.level > 0 then parts[#parts + 1] = "Level " .. info.level end
    if info.race ~= "" then parts[#parts + 1] = info.race end
    if info.class ~= "" then parts[#parts + 1] = info.class end
    strip.meta:SetText(table.concat(parts, " "))
    if type(SetPortraitTexture) == "function" then
      pcall(SetPortraitTexture, strip.portrait, "player")
    end

    local professions = ns.ProfessionProvider.GetCharacterProfessions()
    for i = 1, 2 do
      local cell = strip.cells[i]
      local p = professions[i]
      if p then
        cell.title:SetText(Theme.Upper(p.name))
        cell.value:SetText(string.format("%d %s/ %d|r", p.skillLevel or 0, Theme.Hex.text3, p.maxSkillLevel or 0))
        cell.sub:SetText("")
        cell.bar:SetKind((p.maxSkillLevel or 0) > 0 and (p.skillLevel or 0) >= p.maxSkillLevel and "ok" or "gold")
        cell.bar:SetValue((p.maxSkillLevel or 0) > 0 and (p.skillLevel or 0) / p.maxSkillLevel or 0)
        cell.bar:Show()
      else
        cell.title:SetText(i == 1 and "PROFESSION" or "PROFESSION")
        cell.value:SetText(Theme.ColorText("text3", "-"))
        cell.sub:SetText(i == 1 and "None learned" or "")
        cell.bar:Hide()
      end
    end
    local goldCell = strip.cells[3]
    goldCell.title:SetText("GOLD ON HAND")
    if type(GetMoney) == "function" then
      -- Coin icons plus copper do not fit a 96-150 px cell at 20 px; fall
      -- back to the compact "12g 34s" form when the full string overflows.
      local copper = GetMoney()
      goldCell.value:SetText(Widgets.Money(copper))
      if goldCell.value:GetStringWidth() > goldCell:GetWidth() - 8 then
        goldCell.value:SetText(Widgets.Money(copper, true))
      end
    else
      goldCell.value:SetText(Theme.ColorText("text3", "-"))
    end
    goldCell.sub:SetText("Bags only")
    local goalsCell = strip.cells[4]
    local active = ns.GoalService.Count({ status = "ACTIVE" })
    local completed = ns.GoalService.Count({ status = "COMPLETED" })
    goalsCell.title:SetText("GOALS")
    -- "N active" as the big number; the completed count moves to the sub line
    -- because "N active - M done" at 20 px overhangs the cell in FRIZQT.
    goalsCell.value:SetText(string.format("%d active", active))
    local lastCompleted
    for _, goal in ipairs(ns.GoalService.List({ status = "COMPLETED" })) do
      if goal.completedAt and (not lastCompleted or goal.completedAt > lastCompleted) then lastCompleted = goal.completedAt end
    end
    local doneLine = string.format("%d done", completed)
    if lastCompleted then doneLine = doneLine .. " - last " .. Util.FormatAgo(lastCompleted) end
    goalsCell.sub:SetText(doneLine)

    -- Active goals
    local entries = {}
    local activeGoals = ns.GoalService.List({ status = "ACTIVE" })
    for index, goal in ipairs(activeGoals) do
      local view = MainFrame.views[goal.id]
      entries[#entries + 1] = { goal = goal, view = view }
      local row = goalsPanel.pool:Get(index)
      local item = view and view.item or {}
      row.goalID = goal.id
      row.itemID = goal.target.itemID
      row.icon:SetItem(item.icon, item.quality)
      row.name:SetText(Theme.QualityText(ns.GoalService.Name(goal), item.quality))
      row.badge:SetBadge(view and view.obtain and "Item" or ns.GoalModel.Types[goal.type].badge, "text")
      local percent = ns.Overview.Percent(view)
      row.percent:SetText(percent and (percent .. "%") or "")
      row.bar:SetKind(percent == 100 and "ok" or "gold")
      row.bar:SetValue((percent or 0) / 100)
      if view and view.plan then
        local questReward = view.questline and view.nextStep and #view.plan.materials <= 1
        if ((view.learn or view.skill or view.quest or view.reputation) and #view.plan.materials == 0) or questReward then
          row.detail:SetText(view.nextStep or view.message or "")
        else
          row.detail:SetText(ns.Overview.MissingSummary(view, ns.ItemProvider.GetName))
        end
        Widgets.SetTextColor(row.detail, view.plan.isComplete and C.ok or C.partial)
        if view.skill then
          row.meta:SetText(string.format("%d of %d", view.skill.current, view.skill.target))
        elseif view.quest then
          row.meta:SetText(view.quest.label or "")
        elseif view.reputation then
          row.meta:SetText(view.reputation.record.standingLabel or "")
        elseif view.enchant then
          row.meta:SetText(string.format("%d of %d cast%s", view.enchant.casts, view.enchant.quantity, view.enchant.quantity == 1 and "" or "s"))
        elseif view.learn then
          row.meta:SetText(view.learn.kind == "plans" and "Plans" or (view.learn.kind == "trainer" and "Trainer" or "Combine"))
        elseif view.plan.obtain then
          row.meta:SetText(view.hint and view.hint.label or "Source unknown")
        else
          row.meta:SetText(string.format("%d of %d materials", view.progress.materialsHave, view.progress.materialsTotal))
        end
      elseif view and view.attunement then
        local a = view.attunement
        row.detail:SetText(a.complete and "Attuned" or (a.next and ("Next: " .. ns.AttuneProvider.StepText(a.next)) or ""))
        Widgets.SetTextColor(row.detail, a.complete and C.ok or C.text2)
        row.meta:SetText(string.format("%d of %d steps", a.done, a.total))
      else
        row.detail:SetText(view and view.message or "")
        Widgets.SetTextColor(row.detail, C.missing)
        row.meta:SetText(view and (ns.StatusLabel[view.status] or "") or "")
      end
    end
    goalsPanel.pool:HideFrom(#activeGoals + 1)
    goalsScroll:SetContentHeight(#activeGoals * GOAL_ROW)
    if #activeGoals == 0 then goalsPanel.empty:Show() else goalsPanel.empty:Hide() end

    -- Overview
    local overview = ns.Overview.Build(entries, {
      nameOf = ns.ItemProvider.GetName,
      craftableBy = function(itemID)
        for _, candidate in ipairs(ns.ProfessionProvider.FindRecipesForItem(itemID)) do
          if candidate.learned then return candidate.recipe.professionName end
        end
        return nil
      end,
      completedCount = completed,
    })
    for index, step in ipairs(overview.nextSteps) do
      local row = recommended.pool:Get(index)
      row.title:SetText(step.title)
      row.detail:SetText(step.detail or "")
      if step.badge then
        row.badge:SetBadge(step.badge, step.badgeKind or "ok")
        row.badge:Show()
      else
        row.badge:Hide()
      end
    end
    recommended.pool:HideFrom(#overview.nextSteps + 1)
    if #overview.nextSteps == 0 then recommended.empty:Show() else recommended.empty:Hide() end

    for index, material in ipairs(overview.missing) do
      local row = missingPanel.pool:Get(index)
      local item = ns.ItemProvider.GetItem(material.itemID)
      row.itemID = material.itemID
      row.goals = material.goals
      row.icon:SetItem(item.icon, item.quality)
      row.name:SetText(Theme.QualityText(item.name or ("Item " .. material.itemID), item.quality))
      if material.craftableBy then
        row.source:SetText("Craft - " .. material.craftableBy)
      elseif #material.goals > 1 then
        row.source:SetText(string.format("Needed by %d goals", #material.goals))
      else
        row.source:SetText("Needed by " .. tostring(material.goals[1]))
      end
      row.count:SetText("x" .. material.count)
    end
    missingPanel.pool:HideFrom(#overview.missing + 1)
    missingScroll:SetContentHeight(#overview.missing * MATERIAL_ROW)
    missingPanel.count:SetText(#overview.missing > 0 and string.format("%d material%s", #overview.missing, #overview.missing == 1 and "" or "s") or "")
    if #overview.missing == 0 then missingPanel.empty:Show() else missingPanel.empty:Hide() end
    screen.lastOverview = overview
    self:RefreshCraftWise(activeGoals)
  end

  -- CraftWise panel: the selected goal when it is active, else the first
  -- active goal with a dependency tree.
  function screen:RefreshCraftWise(activeGoals)
    local MainFrame = ns.UI.MainFrame
    local goal = ns.GoalService.GetSelected()
    local view = goal and MainFrame.views[goal.id]
    if not (goal and goal.status == "ACTIVE" and view and view.tree) then
      goal, view = nil, nil
      for _, g in ipairs(activeGoals or {}) do
        local v = MainFrame.views[g.id]
        if v and v.tree then goal, view = g, v break end
      end
    end
    local result = view and ns.CraftWise.Compare(view.fullTree or view.tree, { priceOf = ns.PriceProvider.GetPrice, marketOf = ns.PriceProvider.GetMarket }) or nil
    local panel = craftwise
    panel.goalID = goal and goal.id or nil
    panel.result = result
    local status = ns.PriceProvider.Status()
    if not result or (not result.available and not result.buy.cost) then
      for _, w in ipairs(panel.content) do w:Hide() end
      panel.empty:Set(goal and "No price data" or "No active goal", goal and status.text or "Add a crafting goal to compare buying and crafting.")
      panel.empty:Show()
      panel.compare:SetEnabledState(goal ~= nil)
      return
    end
    panel.empty:Hide()
    for _, w in ipairs(panel.content) do w:Show() end
    panel.compare:SetEnabledState(true)
    local best = result.recommended and result[result.recommended].cost or result.hybrid.cost
    panel.total:SetText(best and Widgets.Money(best, true) or Theme.ColorText("text3", "?"))
    local names = { buy = "Buy the item", craft = "Craft everything", hybrid = "Hybrid plan" }
    local saved = result.savings and (result.savings.buy or result.savings.craft)
    if result.recommended and saved then
      panel.sub:SetText(string.format("%s - saves %s", names[result.recommended], Widgets.Money(saved, true)))
      Widgets.SetTextColor(panel.sub, C.ok)
    elseif result.recommended then
      panel.sub:SetText(names[result.recommended] .. " - " .. ns.GoalService.Name(goal))
      Widgets.SetTextColor(panel.sub, C.text2)
    else
      panel.sub:SetText(string.format("%d component%s unpriced - %s", result.hybrid.unknown or 0, (result.hybrid.unknown or 0) == 1 and "" or "s", ns.GoalService.Name(goal)))
      Widgets.SetTextColor(panel.sub, C.partial)
    end
    local function value(strategy)
      if strategy.cost then
        return Widgets.Money(strategy.cost, true) .. ((strategy.unknown or 0) > 0 and Theme.ColorText("text3", " +?") or "")
      end
      return Theme.ColorText("text3", "no price")
    end
    panel.rows[1].value:SetText(value(result.buy))
    panel.rows[2].value:SetText(value(result.craft))
    panel.rows[3].value:SetText(value(result.hybrid))
    for i, key in ipairs({ "buy", "craft", "hybrid" }) do
      Widgets.SetTextColor(panel.rows[i].value, result.recommended == key and C.gold or C.text)
    end
    panel.rows[3].label:SetText(result.recommended == "hybrid" and "Hybrid - recommended" or "Hybrid")
    if status.freshness then
      panel.dot:SetKind(status.freshness.kind)
      panel.scan:SetText("Cached scan - " .. status.freshness.label)
    else
      panel.dot:SetKind("partial")
      panel.scan:SetText(status.lastScan and "Cached scan" or "Vendor prices only - no AH scan")
    end
  end

  return screen
end

ns.UI.Screens.dashboard = { label = "Dashboard", Create = Create }
