-- Screen 08: compact goal tracker. A separate 262 px frame that stays on
-- screen during play, pages through tracked goals and collapses to one line.
local _, ns = ...

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets
local C = Theme.Colors
local Events = ns.Events

local Tracker = {}
ns.UI.Tracker = Tracker

Tracker.frame = nil
local WIDTH = 262
local MAX_ROWS = 6
local ROW = 20

local function settings()
  return ns.chardb and ns.chardb.tracker or nil
end

function Tracker.IsShown()
  return Tracker.frame ~= nil and Tracker.frame:IsShown()
end

function Tracker.IsEnabled()
  local s = settings()
  return s ~= nil and not s.hidden
end

function Tracker.SavePosition()
  local frame, s = Tracker.frame, settings()
  if not frame or not s then return end
  local point, _, relativePoint, x, y = frame:GetPoint(1)
  if point then
    s.point, s.relativePoint, s.x, s.y = point, relativePoint or point, tonumber(x) or 0, tonumber(y) or 0
  end
end

function Tracker.RestorePosition()
  local frame = Tracker.frame
  local s = settings() or ns.Database.DEFAULTS.char.tracker
  if not frame then return end
  frame:ClearAllPoints()
  frame:SetPoint(s.point or "TOPRIGHT", UIParent, s.relativePoint or s.point or "TOPRIGHT", tonumber(s.x) or -20, tonumber(s.y) or -220)
end

function Tracker.ResetPosition()
  local s = settings()
  if s then
    local defaults = ns.Database.DEFAULTS.char.tracker
    s.point, s.relativePoint, s.x, s.y = defaults.point, defaults.relativePoint, defaults.x, defaults.y
  end
  if Tracker.frame then Tracker.RestorePosition() end
end

local function createRow(content, index)
  local row = CreateFrame("Button", nil, content)
  row:SetHeight(ROW)
  row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW)
  row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * ROW)
  local icon = Widgets.ItemIcon(row, 16)
  icon:SetPoint("LEFT", row, "LEFT", 0, 0)
  local counter = Widgets.Text(row, "small", "", { justify = "RIGHT" })
  counter:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  local name = Widgets.Text(row, "secondaryBright", "")
  name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
  name:SetPoint("RIGHT", counter, "LEFT", -6, 0)
  row.icon, row.name, row.counter = icon, name, counter
  Widgets.ShiftClickLinks(row, function(self) return self.itemID end)
  Widgets.SetItemTooltip(row, function(self) return self.itemID end)
  return row
end

function Tracker.Create()
  if Tracker.frame then return Tracker.frame end
  local frame = Widgets.Frame(UIParent, "ForeverPathTracker", { bg = Theme.RGB("#0E0E0C"), border = C.line, alpha = 0.86 })
  Tracker.frame = frame
  frame:SetWidth(WIDTH)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:Hide()

  local header = CreateFrame("Frame", nil, frame)
  header:SetHeight(22)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() frame:StartMoving() end)
  header:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    Tracker.SavePosition()
  end)
  local headerLine = Widgets.HLine(header, C.black, 0.6)
  headerLine:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
  headerLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)

  local grip = Widgets.Texture(header, C.text3, 0.7, "ARTWORK")
  grip:SetSize(4, 10)
  grip:SetPoint("LEFT", header, "LEFT", 6, 0)
  local emblem = header:CreateTexture(nil, "ARTWORK")
  emblem:SetSize(16, 16)
  emblem:SetTexture(ns.UI.LOGO)
  emblem:SetPoint("LEFT", grip, "RIGHT", 6, 0)
  local title = Widgets.Text(header, "trackerTitle", "ForeverPath")
  title:SetPoint("LEFT", emblem, "RIGHT", 8, 0)
  frame.title = title

  local expand = Widgets.Button(header, "+", { width = 15, height = 15, onClick = function()
    local goal = Tracker.CurrentGoal()
    if goal then ns.UI.MainFrame.OpenGoal(goal.id) else ns.UI.MainFrame.Show() end
  end })
  expand:SetPoint("RIGHT", header, "RIGHT", -4, 0)
  Widgets.SetTooltip(expand, "Open in ForeverPath")
  local collapse = Widgets.Button(header, "-", { width = 15, height = 15, onClick = function()
    local s = settings()
    if s then
      s.collapsed = not s.collapsed
      Tracker.Refresh()
    end
  end })
  collapse:SetPoint("RIGHT", expand, "LEFT", -3, 0)
  Widgets.SetTooltip(collapse, "Collapse / expand")

  local nextPage = CreateFrame("Button", nil, header)
  nextPage:SetSize(12, 16)
  nextPage:SetPoint("RIGHT", collapse, "LEFT", -6, 0)
  local nextArrow = Widgets.Arrow(nextPage, 8, "right", C.text2)
  nextArrow:SetPoint("CENTER")
  nextPage:SetScript("OnClick", function() Tracker.Page(1) end)
  local pager = Widgets.Text(header, "small", "", { justify = "CENTER" })
  pager:SetPoint("RIGHT", nextPage, "LEFT", -2, 0)
  local prevPage = CreateFrame("Button", nil, header)
  prevPage:SetSize(12, 16)
  prevPage:SetPoint("RIGHT", pager, "LEFT", -2, 0)
  local prevArrow = Widgets.Arrow(prevPage, 8, "left", C.text2)
  prevArrow:SetPoint("CENTER")
  prevPage:SetScript("OnClick", function() Tracker.Page(-1) end)
  frame.pager, frame.prevPage, frame.nextPage = pager, prevPage, nextPage

  local collapsedText = Widgets.Text(header, "secondaryBright", "")
  collapsedText:SetPoint("LEFT", title, "RIGHT", 8, 0)
  collapsedText:SetPoint("RIGHT", prevPage, "LEFT", -4, 0)
  frame.collapsedText = collapsedText

  local body = CreateFrame("Frame", nil, frame)
  body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 8, -8)
  body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -8, -8)
  frame.body = body
  local icon = Widgets.ItemIcon(body, 28)
  icon:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  local name = Widgets.Text(body, "body", "")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
  name:SetPoint("RIGHT", body, "RIGHT", 0, 0)
  local sub = Widgets.Text(body, "small", "")
  sub:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 1)
  sub:SetPoint("RIGHT", body, "RIGHT", 0, 0)
  local bar = Widgets.ProgressBar(body, 6, "gold")
  bar:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -8)
  bar:SetPoint("RIGHT", body, "RIGHT", 0, 0)
  local rows = CreateFrame("Frame", nil, body)
  rows:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -8)
  rows:SetPoint("RIGHT", body, "RIGHT", 0, 0)
  rows:SetHeight(1)
  local more = Widgets.Text(body, "small", "")
  more:SetPoint("TOPLEFT", rows, "BOTTOMLEFT", 0, -4)
  more:SetPoint("RIGHT", body, "RIGHT", 0, 0)
  local divider = Widgets.HLine(body, C.black, 0.6)
  divider:SetPoint("TOPLEFT", more, "BOTTOMLEFT", 0, -6)
  divider:SetPoint("RIGHT", body, "RIGHT", 0, 0)
  local nextLabel = Widgets.Text(body, "label", "Next", { caps = true, color = C.gold })
  nextLabel:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -7)
  local nextText = Widgets.Text(body, "secondaryBright", "")
  nextText:SetPoint("LEFT", nextLabel, "RIGHT", 8, 0)
  nextText:SetPoint("RIGHT", body, "RIGHT", 0, 0)
  frame.icon, frame.name, frame.sub, frame.bar, frame.rows, frame.more, frame.nextLabel, frame.nextText = icon, name, sub, bar, rows, more, nextLabel, nextText
  frame.pool = Widgets.Pool(rows, createRow)

  Tracker.RestorePosition()
  return frame
end

function Tracker.TrackedGoals()
  return ns.GoalService.TrackedGoals()
end

function Tracker.CurrentGoal()
  local goals = Tracker.TrackedGoals()
  local s = settings()
  local page = s and s.page or 1
  if page > #goals then page = #goals end
  if page < 1 then page = 1 end
  if s then s.page = page end
  return goals[page], page, #goals
end

function Tracker.Page(delta)
  local s = settings()
  if not s then return end
  local goals = Tracker.TrackedGoals()
  if #goals == 0 then return end
  local page = (s.page or 1) + delta
  if page < 1 then page = #goals end
  if page > #goals then page = 1 end
  s.page = page
  Tracker.Refresh()
end

function Tracker.Toggle()
  local s = settings()
  if not s then return end
  s.hidden = not s.hidden
  Tracker.Refresh()
  if s.hidden then
    ns.Log.Print("Goal tracker hidden. Use /fp tracker or the settings menu to show it.")
  end
end

function Tracker.Refresh()
  local s = settings()
  if not s or not ns.loaded then return end
  local goal, page, total = Tracker.CurrentGoal()
  if s.hidden or not goal then
    if Tracker.frame then Tracker.frame:Hide() end
    return
  end
  local frame = Tracker.Create()
  local MainFrame = ns.UI.MainFrame
  local view = MainFrame.views[goal.id]
  if not view then
    MainFrame.EvaluateViews()
    view = MainFrame.views[goal.id]
  end
  local item = view and view.item or (goal.target.itemID and ns.ItemProvider.GetItem(goal.target.itemID)) or {}
  local percent = ns.Overview.Percent(view)
  local goalName = Theme.QualityText(ns.GoalService.Name(goal), item.quality)
  frame.pager:SetText(string.format("%d/%d", page, total))

  if s.collapsed then
    frame.body:Hide()
    frame.title:SetText("")
    frame.collapsedText:SetText(goalName .. (percent and (Theme.Hex.gold .. "  " .. percent .. "%|r") or ""))
    frame.collapsedText:Show()
    frame:SetHeight(24)
    frame:Show()
    return
  end
  frame.title:SetText("ForeverPath")
  frame.collapsedText:Hide()
  frame.body:Show()
  frame.icon:SetItem(item.icon, item.quality)
  frame.name:SetText(goalName)
  local height = 22 + 8 + 28 + 8 + 6 + 8
  local shown = 0
  if view and view.plan then
    local unresolved = view.plan.totals.materialsMissing
    frame.sub:SetText(string.format("%d%% - %d unresolved", percent or 0, unresolved))
    frame.bar:SetKind(percent == 100 and "ok" or "gold")
    frame.bar:SetValue((percent or 0) / 100)
    local materials = {}
    for _, m in ipairs(view.plan.materials) do materials[#materials + 1] = m end
    table.sort(materials, function(a, b)
      if (a.missing > 0) ~= (b.missing > 0) then return a.missing > 0 end
      return a.required > b.required
    end)
    for index, material in ipairs(materials) do
      if index > MAX_ROWS then break end
      local row = frame.pool:Get(index)
      local info = ns.ItemProvider.GetItem(material.itemID)
      row.itemID = material.itemID
      row.icon:SetItem(info.icon, info.quality)
      row.name:SetText(Theme.QualityText(info.name or ("Item " .. material.itemID), info.quality))
      row.counter:SetText(Widgets.CounterText(material.owned, material.required))
      shown = index
    end
    frame.pool:HideFrom(shown + 1)
    frame.rows:SetHeight(math.max(1, shown * ROW))
    height = height + shown * ROW
    if #materials > shown then
      frame.more:SetText(string.format("+%d more", #materials - shown))
      frame.more:SetHeight(14)
    else
      frame.more:SetText("")
      frame.more:SetHeight(1)
    end
    height = height + (frame.more:GetHeight() or 0) + 4
    if view.skill then
      frame.sub:SetText(string.format("%d%% - %s %d of %d", percent or 0, view.skill.professionName, view.skill.current, view.skill.target))
    end
    if view.quest then
      frame.sub:SetText(string.format("%d%% - %s", percent or 0, view.quest.label or ""))
    elseif view.reputation then
      frame.sub:SetText(string.format("%d%% - %s", percent or 0, view.reputation.record.standingLabel or ""))
    elseif view.enchant then
      frame.sub:SetText(string.format("%d%% - %d of %d cast%s", percent or 0, view.enchant.casts, view.enchant.quantity, view.enchant.quantity == 1 and "" or "s"))
    end
    if view.nextStep and (view.learn or view.skill or view.quest or view.reputation or view.enchant) and (view.plan.isComplete or #view.plan.materials == 0) then
      frame.nextText:SetText(view.nextStep)
    elseif view.nextStep and view.questline and not view.plan.isComplete and #view.plan.materials <= 1 then
      frame.nextText:SetText(view.nextStep)
    elseif view.plan.isComplete and view.plan.obtain then
      frame.nextText:SetText(string.format("All %d x %s on hand", view.plan.quantityWanted or 0, ns.GoalService.Name(goal)))
    elseif view.plan.isComplete then
      frame.nextText:SetText(string.format("Craft %d x %s", view.plan.craftsNeeded, ns.GoalService.Name(goal)))
    else
      local top
      for _, m in ipairs(view.plan.materials) do
        if m.missing > 0 and (not top or m.missing > top.missing) then top = m end
      end
      local hint = view.plan.obtain and view.hint and view.hint.label or nil
      frame.nextText:SetText(top and (string.format("Obtain %d x %s", top.missing, ns.ItemProvider.GetName(top.itemID)) .. (hint and (" - " .. hint) or "")) or (view.nextStep or ""))
    end
  else
    frame.sub:SetText(view and (ns.StatusLabel[view.status] or "") or "")
    frame.bar:SetValue(0)
    frame.pool:HideFrom(1)
    frame.rows:SetHeight(1)
    frame.more:SetText("")
    frame.more:SetHeight(1)
    if view and view.attunement then
      local a = view.attunement
      frame.sub:SetText(string.format("%d%% - %d of %d steps", a.percent, a.done, a.total))
      frame.bar:SetKind(a.complete and "ok" or "gold")
      frame.bar:SetValue(a.percent / 100)
      frame.nextText:SetText(a.complete and "Attuned" or (a.next and ns.AttuneProvider.StepText(a.next) or ""))
    else
      frame.nextText:SetText(view and view.status == ns.Status.RECIPES_NOT_SCANNED and "Open a profession window" or (view and view.message or ""))
    end
    height = height + 6
  end
  height = height + 6 + 7 + 14 + 10
  frame:SetHeight(height)
  frame:Show()
end

function Tracker.Init()
  for _, message in ipairs({ "FP_GOALS_CHANGED", "FP_RECIPES_UPDATED", "FP_INVENTORY_UPDATED", "FP_ITEM_LOADED", "FP_READY" }) do
    Events.On(message, function() ns.UI.MainFrame.RequestRefresh() end)
  end
  Events.RegisterWoW("PLAYER_ENTERING_WORLD", function()
    Events.Debounce("tracker-initial", 1, Tracker.Refresh)
  end)
end
