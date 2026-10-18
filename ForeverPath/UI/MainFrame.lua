-- Main window shell: frame, header, sidebar, status bar, content switching.
-- Screens register themselves in ns.UI.Screens (see UI/Screens/*).
local _, ns = ...

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets
local C = Theme.Colors
local G = Theme.Gradients
local Events = ns.Events
local Util = ns.Util

ns.UI.Screens = ns.UI.Screens or {}

local MainFrame = {}
ns.UI.MainFrame = MainFrame

MainFrame.frame = nil
MainFrame.screens = {}
MainFrame.views = {}
MainFrame.MIN_WIDTH, MainFrame.MIN_HEIGHT = 820, 560
MainFrame.MAX_WIDTH, MainFrame.MAX_HEIGHT = 1400, 960
MainFrame.linkTargets = {}

MainFrame.Nav = {
  { key = "dashboard", label = "Dashboard" },
  { key = "goals", label = "My Goals", count = true },
  { key = "crafting", label = "Crafting" },
  { key = "shopping", label = "Shopping List" },
  { key = "characters", label = "Characters" },
  { key = "attunements", label = "Attunements" },
  { key = "quests", label = "Quests" },
  { key = "equipment", label = "Equipment" },
  { key = "reputations", label = "Reputations" },
}

---------------------------------------------------------------------------
-- Shared data
---------------------------------------------------------------------------
local function windowSettings()
  return ns.chardb and ns.chardb.window or nil
end

function MainFrame.CharacterInfo()
  local info = ns.CharacterProvider.Identity()
  info.color = C.text
  local colors = _G.RAID_CLASS_COLORS
  if info.classFile and type(colors) == "table" and colors[info.classFile] then
    local c = colors[info.classFile]
    info.color = { c.r, c.g, c.b }
  end
  return info
end

-- Re-evaluates every open goal. Screens and the tracker read MainFrame.views.
function MainFrame.EvaluateViews()
  local goals = ns.GoalService.List({ open = true })
  MainFrame.views = ns.Planner.EvaluateAll(goals)
  MainFrame.openGoals = goals
  return MainFrame.views
end

function MainFrame.GetView(goalID)
  return MainFrame.views[goalID]
end

function MainFrame.ActiveGoal()
  local selected = ns.GoalService.GetSelected()
  if selected and ns.GoalModel.IsOpen(selected) then
    return selected
  end
  return ns.GoalService.List({ open = true })[1]
end

---------------------------------------------------------------------------
-- Position persistence
---------------------------------------------------------------------------
function MainFrame.SavePosition()
  local frame = MainFrame.frame
  local w = windowSettings()
  if not frame or not w then return end
  local point, _, relativePoint, x, y = frame:GetPoint(1)
  if point then
    w.point = point
    w.relativePoint = relativePoint or point
    w.x = tonumber(x) or 0
    w.y = tonumber(y) or 0
  end
  local width, height = frame:GetWidth(), frame:GetHeight()
  if type(width) == "number" and width >= MainFrame.MIN_WIDTH then w.width = width end
  if type(height) == "number" and height >= MainFrame.MIN_HEIGHT then w.height = height end
end

function MainFrame.RestorePosition()
  local frame = MainFrame.frame
  local w = windowSettings() or ns.Database.WINDOW_DEFAULTS
  if not frame then return end
  local width = Util.Clamp(tonumber(w.width) or 1000, MainFrame.MIN_WIDTH, MainFrame.MAX_WIDTH)
  local height = Util.Clamp(tonumber(w.height) or 700, MainFrame.MIN_HEIGHT, MainFrame.MAX_HEIGHT)
  frame:SetSize(width, height)
  frame:ClearAllPoints()
  frame:SetPoint(w.point or "CENTER", UIParent, w.relativePoint or w.point or "CENTER", tonumber(w.x) or 0, tonumber(w.y) or 0)
end

function MainFrame.ResetWindow()
  local w = windowSettings()
  if w then
    for k, v in pairs(ns.Database.WINDOW_DEFAULTS) do w[k] = v end
  end
  if MainFrame.frame then
    MainFrame.RestorePosition()
  end
  if ns.UI.Tracker and ns.UI.Tracker.ResetPosition then
    ns.UI.Tracker.ResetPosition()
  end
end

---------------------------------------------------------------------------
-- Status line
---------------------------------------------------------------------------
local STATUS_KIND = { info = C.text2, ok = C.ok, error = C.missing, warn = C.partial }

function MainFrame.SetStatus(text, kind)
  local frame = MainFrame.frame
  if not frame then return end
  frame.alertText:SetText(text or "")
  Widgets.SetTextColor(frame.alertText, STATUS_KIND[kind or "info"] or C.text2)
  frame.alertDot:SetKind(kind == "error" and "missing" or (kind == "warn" and "partial" or (kind == "ok" and "ok" or "info")))
  if text and text ~= "" then frame.alertDot:Show() else frame.alertDot:Hide() end
end

function MainFrame.IsShown()
  return MainFrame.frame ~= nil and MainFrame.frame:IsShown()
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local function createRings(frame)
  local specs = { { 1, C.black, 1 }, { 3, C.ring, 2 }, { 4, C.black, 1 } }
  for _, spec in ipairs(specs) do
    local ring = Widgets.Frame(frame, nil, { border = spec[2] })
    if ring.SetBackdrop then
      ring:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = spec[3] })
      ring:SetBackdropBorderColor(spec[2][1], spec[2][2], spec[2][3], 1)
    end
    ring:SetPoint("TOPLEFT", frame, "TOPLEFT", -spec[1], spec[1])
    ring:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", spec[1], -spec[1])
    ring:SetFrameLevel(frame:GetFrameLevel())
    ring:EnableMouse(false)
  end
  for _, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
    local rivet = Widgets.Texture(frame, C.bronze, 1, "OVERLAY")
    rivet:SetSize(7, 7)
    if rivet.SetRotation then rivet:SetRotation(math.pi / 4) end
    local dx = corner:find("LEFT") and -3 or 3
    local dy = corner:find("TOP") and 3 or -3
    rivet:SetPoint(corner, frame, corner, dx, dy)
  end
end

-- Places the header divider after the wider of the title and tagline. String
-- widths depend on the font actually loaded, so this runs again on refresh.
function MainFrame.LayoutBrand(frame)
  frame = frame or MainFrame.frame
  if not frame or not frame.brandDivider then return end
  local width = math.max(frame.title:GetStringWidth() or 0, frame.tagline:GetStringWidth() or 0, 90)
  frame.brandDivider:ClearAllPoints()
  frame.brandDivider:SetPoint("LEFT", frame.title, "LEFT", width + 14, -6)
end

local function createHeader(frame)
  local header = CreateFrame("Frame", nil, frame)
  header:SetHeight(46)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  local gradient = header:CreateTexture(nil, "BACKGROUND")
  gradient:SetAllPoints(header)
  Widgets.Gradient(gradient, G.header)
  local border = Widgets.HLine(header, C.bronze, 1)
  border:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
  border:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  local shadow = Widgets.HLine(frame, C.black, 1)
  shadow:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
  shadow:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -1)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() frame:StartMoving() end)
  header:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    MainFrame.SavePosition()
  end)

  -- The ForeverPath mark (Media/ForeverPath-Mark.png: round badge, its own
  -- dark fill and gold rings, so it needs no backing frame).
  local emblem = CreateFrame("Frame", nil, header)
  emblem:SetSize(32, 32)
  emblem:SetPoint("LEFT", header, "LEFT", 11, 0)
  local mark = emblem:CreateTexture(nil, "ARTWORK")
  mark:SetAllPoints(emblem)
  mark:SetTexture(ns.UI.LOGO)
  frame.emblem, frame.mark = emblem, mark

  local title = Widgets.Text(header, "title", "ForeverPath")
  title:SetPoint("TOPLEFT", emblem, "TOPRIGHT", 10, 1)
  local tagline = Widgets.Text(header, "tagline", "Your World. Your Goals. Your Path.", { caps = true })
  tagline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
  frame.title = title
  frame.tagline = tagline

  -- The divider sits after the wider of title and tagline; in the client
  -- fonts the caps tagline is wider than the 18 px title. Positioned by
  -- layoutBrand (here and on every refresh, once string widths are known).
  local divider = Widgets.Engraved(header, true)
  divider:SetHeight(26)
  frame.brandDivider = divider

  local charName = Widgets.Text(header, "body", "")
  charName:SetPoint("TOPLEFT", divider, "TOPRIGHT", 12, 0)
  local charMeta = Widgets.Text(header, "small", "")
  charMeta:SetPoint("TOPLEFT", charName, "BOTTOMLEFT", 0, -2)
  frame.charName = charName
  frame.charMeta = charMeta
  MainFrame.LayoutBrand(frame)

  -- Right side: close, settings, search, active goal pill
  local close = Widgets.IconButton(header, "X", { close = true, onClick = function() MainFrame.Hide() end })
  close:SetPoint("RIGHT", header, "RIGHT", -10, 0)
  local settings = Widgets.IconButton(header, "...", { onClick = function(self) MainFrame.OpenSettingsMenu(self) end })
  settings:SetPoint("RIGHT", close, "LEFT", -6, 0)
  Widgets.SetTooltip(settings, "Settings")

  local search = Widgets.SearchField(header, {
    name = "ForeverPathSearchBox",
    width = 176,
    placeholder = "Search items, goals...",
    onEnter = function(box) MainFrame.SubmitSearch(box) end,
    onChange = function(box, userInput) if userInput then MainFrame.UpdateSuggestions(box) end end,
  })
  search:SetPoint("RIGHT", settings, "LEFT", -8, 0)
  search:SetScript("OnEditFocusLost", function(self)
    if (self:GetText() or "") == "" then self.placeholder:Show() end
    Widgets.SetBackdrop(self, C.inset, C.lineDark)
    if ns.Compat.After then
      ns.Compat.After(0.2, function() MainFrame.HideSuggestions() end)
    else
      MainFrame.HideSuggestions()
    end
  end)
  frame.search = search
  MainFrame.linkTargets[#MainFrame.linkTargets + 1] = search

  local pill = Widgets.Frame(header, nil, { frameType = "Button", bg = Theme.RGB("#141412"), border = C.line })
  pill:SetSize(250, 30)
  pill:SetPoint("RIGHT", search, "LEFT", -10, 0)
  local pillIcon = Widgets.ItemIcon(pill, 22)
  pillIcon:SetPoint("LEFT", pill, "LEFT", 4, 0)
  local pillLabel = Widgets.Text(pill, "tagline", "Active goal", { caps = true })
  pillLabel:SetPoint("TOPLEFT", pillIcon, "TOPRIGHT", 8, 0)
  local pillName = Widgets.Text(pill, "button", "")
  pillName:SetPoint("BOTTOMLEFT", pillIcon, "BOTTOMRIGHT", 8, 0)
  pillName:SetWidth(150)
  local pillArrow = Widgets.Arrow(pill, 8, "down", C.text2)
  pillArrow:SetPoint("RIGHT", pill, "RIGHT", -8, 0)
  local pillPercent = Widgets.Text(pill, "button", "", { color = C.gold, justify = "RIGHT" })
  pillPercent:SetPoint("RIGHT", pillArrow, "LEFT", -6, 0)
  pill.icon, pill.name, pill.percent = pillIcon, pillName, pillPercent
  pill:SetScript("OnClick", function(self) MainFrame.OpenGoalSwitcher(self) end)
  frame.pill = pill
  -- Character lines truncate before the pill instead of running under it.
  frame.charName:SetPoint("RIGHT", pill, "LEFT", -12, 0)
  frame.charMeta:SetPoint("RIGHT", pill, "LEFT", -12, 0)
  frame.header = header
end

local function createSidebar(frame)
  local sidebar = Widgets.Frame(frame, nil, { bg = C.sidebar })
  sidebar:SetWidth(142)
  sidebar:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -2)
  sidebar:SetPoint("BOTTOMLEFT", frame.statusBar, "TOPLEFT", 0, 1)
  local edge = Widgets.Texture(sidebar, C.line, 1, "ARTWORK")
  edge:SetWidth(1)
  edge:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
  edge:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
  local inner = Widgets.Texture(sidebar, C.black, 1, "ARTWORK")
  inner:SetWidth(1)
  inner:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -1, 0)
  inner:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -1, 0)

  frame.navButtons = {}
  local y = -8
  for _, entry in ipairs(MainFrame.Nav) do
    if entry.divider then
      local line = Widgets.Engraved(sidebar)
      line:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 10, y - 6)
      line:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -10, y - 6)
      local label = Widgets.Text(sidebar, "tagline", entry.label, { caps = true, color = C.text3 })
      label:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 15, y - 14)
      y = y - 30
    else
      local button = Widgets.Frame(sidebar, nil, { frameType = "Button" })
      button:SetHeight(31)
      button:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 6, y)
      button:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -8, y)
      local gradient = button:CreateTexture(nil, "BACKGROUND")
      gradient:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
      gradient:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
      Widgets.Gradient(gradient, G.navActive)
      gradient:Hide()
      button.gradient = gradient
      local highlight = button:CreateTexture(nil, "HIGHLIGHT")
      highlight:SetAllPoints(button)
      Widgets.SetColor(highlight, C.white, 0.04)
      local glyph = Widgets.Texture(button, C.text3, 1, "ARTWORK")
      glyph:SetSize(6, 6)
      if glyph.SetRotation then glyph:SetRotation(math.pi / 4) end
      glyph:SetPoint("LEFT", button, "LEFT", 12, 0)
      button.glyph = glyph
      local label = Widgets.Text(button, "nav", entry.label, { color = entry.preview and C.text2 or Theme.RGB("#D2C9B4") })
      label:SetPoint("LEFT", button, "LEFT", 28, 0)
      button.label = label
      button.entry = entry
      if entry.count then
        local count = Widgets.Text(button, "small", "", { justify = "RIGHT" })
        count:SetPoint("RIGHT", button, "RIGHT", -8, 0)
        button.count = count
      end
      button:SetScript("OnClick", function() MainFrame.ShowScreen(entry.key) end)
      frame.navButtons[entry.key] = button
      y = y - 33
    end
  end

  local footerLine = Widgets.Engraved(sidebar)
  footerLine:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 6, 48)
  footerLine:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -8, 48)
  local footerActive = Widgets.Text(sidebar, "small", "")
  footerActive:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 15, 26)
  local footerDone = Widgets.Text(sidebar, "small", "")
  footerDone:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 15, 10)
  frame.footerActive = footerActive
  frame.footerDone = footerDone
  frame.sidebar = sidebar
end

local function createStatusBar(frame)
  local bar = Widgets.Frame(frame, nil, { bg = C.statusbar })
  bar:SetHeight(24)
  bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
  bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
  local top = Widgets.HLine(bar, C.line, 1)
  top:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)

  local bagsDot = Widgets.Dot(bar, "ok")
  bagsDot:SetPoint("LEFT", bar, "LEFT", 10, 0)
  local bagsText = Widgets.Text(bar, "small", "")
  bagsText:SetPoint("LEFT", bagsDot, "RIGHT", 6, 0)
  local recipesDot = Widgets.Dot(bar, "partial")
  recipesDot:SetPoint("LEFT", bagsText, "RIGHT", 16, 0)
  local recipesText = Widgets.Text(bar, "small", "")
  recipesText:SetPoint("LEFT", recipesDot, "RIGHT", 6, 0)
  local pricesDot = Widgets.Dot(bar, "partial")
  pricesDot:SetPoint("LEFT", recipesText, "RIGHT", 16, 0)
  local pricesText = Widgets.Text(bar, "small", "")
  pricesText:SetPoint("LEFT", pricesDot, "RIGHT", 6, 0)
  local alertDot = Widgets.Dot(bar, "info")
  alertDot:SetPoint("LEFT", pricesText, "RIGHT", 16, 0)
  alertDot:Hide()
  local alertText = Widgets.Text(bar, "small", "")
  alertText:SetPoint("LEFT", alertDot, "RIGHT", 6, 0)
  alertText:SetPoint("RIGHT", bar, "RIGHT", -170, 0)

  local version = Widgets.Text(bar, "small", "", { justify = "RIGHT" })
  version:SetPoint("RIGHT", bar, "RIGHT", -24, 0)
  frame.bagsDot, frame.bagsText = bagsDot, bagsText
  frame.recipesDot, frame.recipesText = recipesDot, recipesText
  frame.pricesDot, frame.pricesText = pricesDot, pricesText
  frame.alertDot, frame.alertText = alertDot, alertText
  frame.versionText = version
  frame.statusBar = bar
end

function MainFrame.Create()
  if MainFrame.frame then
    return MainFrame.frame
  end
  local frame = Widgets.Frame(UIParent, "ForeverPathMainFrame", { bg = C.bg, border = C.bronze })
  MainFrame.frame = frame
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  if frame.SetResizeBounds then
    frame:SetResizeBounds(MainFrame.MIN_WIDTH, MainFrame.MIN_HEIGHT, MainFrame.MAX_WIDTH, MainFrame.MAX_HEIGHT)
  elseif frame.SetMinResize then
    frame:SetMinResize(MainFrame.MIN_WIDTH, MainFrame.MIN_HEIGHT)
    if frame.SetMaxResize then frame:SetMaxResize(MainFrame.MAX_WIDTH, MainFrame.MAX_HEIGHT) end
  end
  frame:SetScript("OnSizeChanged", function()
    Events.Debounce("window-save", 0.5, MainFrame.SavePosition)
  end)
  frame:SetScript("OnShow", function() MainFrame.RequestRefresh() end)
  frame:SetScript("OnHide", function()
    MainFrame.SavePosition()
    Widgets.CloseMenu()
    MainFrame.HideSuggestions()
  end)
  frame:Hide()

  createRings(frame)
  createHeader(frame)
  createStatusBar(frame)
  createSidebar(frame)

  local content = CreateFrame("Frame", nil, frame)
  content:SetPoint("TOPLEFT", frame.sidebar, "TOPRIGHT", 14, -12)
  content:SetPoint("BOTTOMRIGHT", frame.statusBar, "TOPRIGHT", -14, 12)
  frame.content = content

  for key, def in pairs(ns.UI.Screens) do
    local screen = def.Create(content, key)
    screen:SetAllPoints(content)
    screen:Hide()
    MainFrame.screens[key] = screen
  end

  local grip = Widgets.ResizeGrip(frame, MainFrame.SavePosition)
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)

  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "ForeverPathMainFrame")
  end

  frame.versionText:SetText("ForeverPath " .. tostring(ns.VERSION))
  MainFrame.RestorePosition()
  local startScreen = ns.chardb and ns.chardb.ui and ns.chardb.ui.screen or "dashboard"
  MainFrame.ShowScreen(MainFrame.screens[startScreen] and startScreen or "dashboard", true)
  return frame
end

---------------------------------------------------------------------------
-- Screens
---------------------------------------------------------------------------
function MainFrame.ShowScreen(key, silent)
  local frame = MainFrame.Create()
  if not MainFrame.screens[key] then
    key = "dashboard"
  end
  for screenKey, screen in pairs(MainFrame.screens) do
    if screenKey == key then screen:Show() else screen:Hide() end
  end
  for navKey, button in pairs(frame.navButtons) do
    local active = navKey == key
    if active then
      Widgets.SetBackdrop(button, nil, C.bronzeDim)
      button.gradient:Show()
      Widgets.SetTextColor(button.label, C.goldLight)
      Widgets.SetColor(button.glyph, C.gold)
    else
      Widgets.SetBackdrop(button, nil, nil)
      if button.SetBackdrop then button:SetBackdrop(nil) end
      button.gradient:Hide()
      Widgets.SetTextColor(button.label, button.entry.preview and C.text2 or Theme.RGB("#D2C9B4"))
      Widgets.SetColor(button.glyph, C.text3)
    end
  end
  MainFrame.currentScreen = key
  if ns.chardb and ns.chardb.ui then
    ns.chardb.ui.screen = key
  end
  if not silent then
    MainFrame.Refresh()
  end
end

function MainFrame.Show()
  if not ns.loaded then
    ns.Log.Print("Still loading, try again in a moment.")
    return
  end
  local frame = MainFrame.Create()
  frame:Show()
  MainFrame.Refresh()
end

function MainFrame.Hide()
  if MainFrame.frame then
    MainFrame.frame:Hide()
  end
end

function MainFrame.Toggle()
  if MainFrame.IsShown() then
    MainFrame.Hide()
  else
    MainFrame.Show()
  end
end

-- Opens the window on the crafting screen for a goal.
function MainFrame.OpenGoal(goalID)
  ns.GoalService.Select(goalID)
  MainFrame.Show()
  local goal = ns.GoalService.Store() and ns.GoalService.Store():Get(goalID)
  local SCREEN_FOR = { COMPLETE_ATTUNEMENT = "attunements", COMPLETE_QUEST = "quests", REACH_REPUTATION = "reputations" }
  MainFrame.ShowScreen(goal and SCREEN_FOR[goal.type] or "crafting")
end

local function refreshChrome(frame)
  MainFrame.LayoutBrand(frame)
  local info = MainFrame.CharacterInfo()
  frame.charName:SetText(info.name)
  Widgets.SetTextColor(frame.charName, info.color)
  local meta = {}
  if info.level and info.level > 0 then meta[#meta + 1] = "Level " .. info.level end
  if info.class ~= "" then meta[#meta + 1] = info.class end
  local line = table.concat(meta, " ")
  if info.realm ~= "" then line = line .. (line ~= "" and " - " or "") .. info.realm end
  frame.charMeta:SetText(line)

  local active = ns.GoalService.Count({ status = "ACTIVE" })
  local open = ns.GoalService.Count({ open = true })
  local completed = ns.GoalService.Count({ status = "COMPLETED" })
  frame.footerActive:SetText(string.format("%d active goal%s", active, active == 1 and "" or "s"))
  frame.footerDone:SetText(string.format("%d completed", completed))
  if frame.navButtons.goals.count then
    frame.navButtons.goals.count:SetText(open > 0 and tostring(open) or "")
  end

  local goal = MainFrame.ActiveGoal()
  if goal then
    local view = MainFrame.views[goal.id]
    local item = view and view.item or ns.ItemProvider.GetItem(goal.target.itemID)
    frame.pill.icon:SetItem(item.icon, item.quality)
    frame.pill.name:SetText(Theme.QualityText(ns.GoalService.Name(goal), item.quality))
    local percent = ns.Overview.Percent(view)
    frame.pill.percent:SetText(percent and (percent .. "%") or "")
    frame.pill:Show()
  else
    frame.pill.icon:SetItem(nil, 1)
    frame.pill.name:SetText(Theme.ColorText("text3", "No goals yet"))
    frame.pill.percent:SetText("")
  end

  local bags = ns.InventoryProvider.bags
  if bags.dirty then
    ns.InventoryProvider.ScanBags()
  end
  local bankCache = ns.chardb and ns.chardb.bankCache
  if bags.scannedAt then
    frame.bagsDot:SetKind("ok")
    local text = "Bags synced - " .. Util.FormatAgo(bags.scannedAt)
    if bankCache and bankCache.scannedAt then
      text = "Bags & bank synced - " .. Util.FormatAgo(math.min(bags.scannedAt, bankCache.scannedAt))
    end
    frame.bagsText:SetText(text)
  else
    frame.bagsDot:SetKind("partial")
    frame.bagsText:SetText("Bags not scanned yet")
  end
  local professions = ns.ProfessionProvider.GetScannedProfessions()
  if #professions == 0 then
    frame.recipesDot:SetKind("missing")
    frame.recipesText:SetText(ns.ProfessionProvider.IsAvailable() and "Recipes: none recorded - open a profession window" or "Recipes: profession API unavailable")
  else
    local total, latest = 0, 0
    for _, p in ipairs(professions) do
      total = total + (p.recipeCount or 0)
      if (p.scannedAt or 0) > latest then latest = p.scannedAt end
    end
    local age = Util.Now() - latest
    frame.recipesDot:SetKind(age < 3 * 3600 and "ok" or (age < 86400 and "partial" or "missing"))
    frame.recipesText:SetText(string.format("Recipes: %d recorded - %s", total, Util.FormatAgo(latest)))
  end
  local prices = ns.PriceProvider.Status()
  frame.pricesDot:SetKind(prices.kind == "text3" and "text" or prices.kind)
  frame.pricesText:SetText(prices.text)
end

function MainFrame.Refresh()
  local frame = MainFrame.frame
  if not frame or not frame:IsShown() then
    return
  end
  MainFrame.EvaluateViews()
  refreshChrome(frame)
  local screen = MainFrame.screens[MainFrame.currentScreen]
  if screen and screen.Refresh then
    ns.Log.Call(screen.Refresh, screen)
  end
end

function MainFrame.RequestRefresh()
  Events.Debounce("ui-refresh", 0.05, function()
    if MainFrame.IsShown() then
      MainFrame.Refresh()
    elseif ns.UI.Tracker and ns.UI.Tracker.IsShown() then
      MainFrame.EvaluateViews()
    end
    if ns.UI.Tracker then
      ns.UI.Tracker.Refresh()
    end
  end)
end

---------------------------------------------------------------------------
-- Header interactions
---------------------------------------------------------------------------
function MainFrame.OpenGoalSwitcher(anchor)
  local goals = ns.GoalService.List({ open = true })
  if #goals == 0 then
    MainFrame.SetStatus("Add a goal from My Goals or the search box.", "info")
    return
  end
  local selected = ns.GoalService.GetSelected()
  local items = {}
  for _, goal in ipairs(goals) do
    local view = MainFrame.views[goal.id]
    local percent = ns.Overview.Percent(view)
    items[#items + 1] = {
      text = Theme.QualityText(ns.GoalService.Name(goal), view and view.item and view.item.quality),
      meta = percent and (percent .. "%") or "",
      value = goal.id,
      selected = selected and selected.id == goal.id,
    }
  end
  return Widgets.Menu(anchor, items, function(goalID)
    ns.GoalService.Select(goalID)
    MainFrame.ShowScreen("crafting")
  end, 250)
end

function MainFrame.OpenSettingsMenu(anchor)
  local tracker = ns.UI.Tracker
  local items = {
    { text = tracker and tracker.IsEnabled() and "Hide goal tracker" or "Show goal tracker", value = "tracker" },
    { text = "Record recipes (open profession windows)", value = "scan" },
    { text = ns.Log.debugEnabled and "Disable debug logging" or "Enable debug logging", value = "debug" },
    { text = "Reset window positions", value = "reset" },
  }
  Widgets.Menu(anchor, items, function(value)
    if value == "tracker" and tracker then
      tracker.Toggle()
    elseif value == "scan" then
      ns.ProfessionProvider.RequestScan(false)
    elseif value == "debug" then
      ns.Log.SetDebug(not ns.Log.debugEnabled)
      MainFrame.SetStatus("Debug logging " .. (ns.Log.debugEnabled and "enabled" or "disabled"), "info")
    elseif value == "reset" then
      MainFrame.ResetWindow()
      MainFrame.SetStatus("Window positions reset.", "info")
    end
  end, 260)
end

function MainFrame.SubmitSearch(box)
  local text = box:GetText() or ""
  if Util.Trim(text) == "" then
    return
  end
  MainFrame.HideSuggestions()
  local ok, message = ns.GoalService.AddFromInput(text, 1)
  MainFrame.SetStatus(message, ok and "ok" or "error")
  if ok then
    box:SetText("")
    box:ClearFocus()
    MainFrame.ShowScreen("crafting")
  end
end

-- Type-ahead popup under an input. hits come from GoalService.Suggest;
-- clicking a row adds its goal. opts.quantity() supplies the quantity for
-- item and enchant goals, opts.onAdd(ok, message, goal) runs after a pick.
function MainFrame.ShowSuggestions(box, hits, opts)
  local frame = MainFrame.frame
  opts = opts or {}
  if not frame or type(hits) ~= "table" or #hits == 0 then
    MainFrame.HideSuggestions()
    return
  end
  local popup = frame.suggestions
  if not popup then
    popup = Widgets.Frame(frame, nil, { bg = C.sidebar, border = C.bronzeDim })
    popup:SetFrameLevel(frame:GetFrameLevel() + 20)
    popup.rows = {}
    frame.suggestions = popup
  end
  popup:ClearAllPoints()
  popup:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -2)
  popup:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -2)
  popup.box = box
  for index, hit in ipairs(hits) do
    local row = popup.rows[index]
    if not row then
      row = CreateFrame("Button", nil, popup)
      row:SetHeight(26)
      row:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -1 - (index - 1) * 26)
      row:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -1, -1 - (index - 1) * 26)
      Widgets.HoverFill(row, C.raised, 1)
      row.meta = Widgets.Text(row, "small", "", { color = C.text3, justify = "RIGHT" })
      row.meta:SetPoint("RIGHT", row, "RIGHT", -8, 0)
      row.text = Widgets.Text(row, "button", "", { color = C.text })
      row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
      row.text:SetPoint("RIGHT", row.meta, "LEFT", -6, 0)
      popup.rows[index] = row
    end
    row.text:SetText(hit.text or "")
    row.meta:SetText(hit.meta or "")
    row.hit = hit
    row.itemID = hit.itemID
    row:SetScript("OnClick", function(self)
      MainFrame.HideSuggestions()
      local quantity = opts.quantity and opts.quantity() or 1
      local ok, message, goal = self.hit.add(quantity)
      MainFrame.SetStatus(message, ok and "ok" or "error")
      if opts.onAdd then ns.Log.Call(opts.onAdd, ok, message, goal) end
    end)
    row:Show()
  end
  for index = #hits + 1, #popup.rows do
    popup.rows[index]:Hide()
  end
  popup:SetHeight(#hits * 26 + 2)
  popup:Show()
end

-- Header search: a few suggestions of every kind; a pick opens the goal's screen.
function MainFrame.UpdateSuggestions(box)
  local text = Util.Trim(box:GetText() or "")
  if #text < 2 or text:find("|H", 1, true) or Util.ParseInt(text) then
    MainFrame.HideSuggestions()
    return
  end
  MainFrame.ShowSuggestions(box, ns.GoalService.Suggest("all", text, 8), {
    onAdd = function(ok, _, goal)
      if not ok then return end
      box:SetText("")
      box:ClearFocus()
      if goal and MainFrame.OpenGoal then MainFrame.OpenGoal(goal.id) else MainFrame.ShowScreen("crafting") end
    end,
  })
end

function MainFrame.HideSuggestions()
  if MainFrame.frame and MainFrame.frame.suggestions then
    MainFrame.frame.suggestions:Hide()
  end
end

-- Shift-click support: item links, and enchant or spell links from a
-- profession window, go into whichever ForeverPath input has focus, or the
-- header search when no chat box is active.
local function onInsertLink(link)
  if type(link) ~= "string" or not MainFrame.IsShown() then
    return
  end
  local isItem = link:find("|Hitem:", 1, true) ~= nil
  local isSpell = link:find("|Henchant:", 1, true) ~= nil or link:find("|Hspell:", 1, true) ~= nil
  if not isItem and not isSpell then
    return
  end
  local focus = type(GetCurrentKeyBoardFocus) == "function" and GetCurrentKeyBoardFocus() or nil
  local target
  for _, box in ipairs(MainFrame.linkTargets) do
    if focus == box then target = box end
  end
  if not target then
    if focus ~= nil then
      return
    end
    target = MainFrame.frame.search
  end
  target:SetText(link)
  MainFrame.SetStatus(isItem and "Item link received. Press Enter or Add goal." or "Recipe link received. Press Enter or Add goal.", "info")
end

function MainFrame.InstallLinkHook()
  if MainFrame.hooked or type(hooksecurefunc) ~= "function" then
    return false
  end
  local function callback(link) ns.Log.Call(onInsertLink, link) end
  if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.InsertLink) == "function" then
    hooksecurefunc(ChatFrameUtil, "InsertLink", callback)
    MainFrame.hooked = true
  elseif type(ChatEdit_InsertLink) == "function" then
    hooksecurefunc("ChatEdit_InsertLink", callback)
    MainFrame.hooked = true
  end
  return MainFrame.hooked
end

function MainFrame.OnCharactersUpdated()
  if MainFrame.IsShown() and MainFrame.currentScreen == "characters" then
    MainFrame.RequestRefresh()
  end
end

function MainFrame.Init()
  for _, message in ipairs({ "FP_GOALS_CHANGED", "FP_RECIPES_UPDATED", "FP_INVENTORY_UPDATED", "FP_ITEM_LOADED", "FP_QUESTS_UPDATED", "FP_EQUIPMENT_UPDATED", "FP_REPUTATION_UPDATED" }) do
    Events.On(message, MainFrame.RequestRefresh)
  end
  Events.On("FP_CHARACTERS_UPDATED", MainFrame.OnCharactersUpdated)
  MainFrame.InstallLinkHook()
end
