-- Widget kit implementing the handoff's component sheet with plain frames,
-- textures and font strings (no Blizzard art templates).
local _, ns = ...

ns.UI = ns.UI or {}
local Theme = ns.UI.Theme
local C = Theme.Colors
local G = Theme.Gradients

local Widgets = {}
ns.UI.Widgets = Widgets

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"
local SEARCH_ICON = "Interface\\Common\\UI-Searchbox-Icon"
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"

local unpack = unpack or table.unpack

---------------------------------------------------------------------------
-- Primitives
---------------------------------------------------------------------------
function Widgets.SetColor(texture, color, alpha)
  texture:SetColorTexture(color[1], color[2], color[3], alpha or 1)
end

function Widgets.Texture(parent, color, alpha, layer)
  local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
  if color then
    Widgets.SetColor(texture, color, alpha)
  end
  return texture
end

-- Vertical gradient; falls back to the average colour on clients without SetGradient.
function Widgets.Gradient(texture, gradient)
  local top, bottom = gradient[1], gradient[2]
  if type(texture.SetGradient) == "function" and type(CreateColor) == "function" then
    texture:SetColorTexture(1, 1, 1, 1)
    texture:SetGradient("VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1))
  else
    Widgets.SetColor(texture, { (top[1] + bottom[1]) / 2, (top[2] + bottom[2]) / 2, (top[3] + bottom[3]) / 2 })
  end
end

function Widgets.SetBackdrop(frame, bg, border, bgAlpha, borderAlpha)
  if type(frame.SetBackdrop) ~= "function" then
    return false
  end
  frame:SetBackdrop({
    bgFile = bg and WHITE or nil,
    edgeFile = border and WHITE or nil,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  if bg then
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bgAlpha or 1)
  else
    frame:SetBackdropColor(0, 0, 0, 0)
  end
  if border then
    frame:SetBackdropBorderColor(border[1], border[2], border[3], borderAlpha or 1)
  end
  return true
end

-- Flat frame with optional solid background and 1 px border.
function Widgets.Frame(parent, name, opts)
  opts = opts or {}
  local template = ns.Compat.hasBackdropTemplate and "BackdropTemplate" or nil
  local frame = CreateFrame(opts.frameType or "Frame", name, parent, template)
  if opts.bg or opts.border then
    Widgets.SetBackdrop(frame, opts.bg, opts.border, opts.alpha, opts.borderAlpha)
  end
  return frame
end

function Widgets.ApplyFont(fontString, role)
  local font = Theme.Fonts[role]
  if font then
    fontString:SetFontObject(font)
  else
    fontString:SetFontObject(Theme.Fallback[role] or "GameFontHighlightSmall")
  end
end

-- opts: color (rgb table), justify, width, wrap, caps
function Widgets.Text(parent, role, text, opts)
  opts = opts or {}
  local fs = parent:CreateFontString(nil, "OVERLAY")
  Widgets.ApplyFont(fs, role)
  if opts.color then
    fs:SetTextColor(opts.color[1], opts.color[2], opts.color[3])
  end
  fs:SetJustifyH(opts.justify or "LEFT")
  fs:SetWordWrap(opts.wrap == true)
  if opts.width then
    fs:SetWidth(opts.width)
  end
  fs:SetText(opts.caps and Theme.Upper(text) or (text or ""))
  return fs
end

function Widgets.SetTextColor(fs, color)
  fs:SetTextColor(color[1], color[2], color[3])
end

-- 1 px horizontal line.
function Widgets.HLine(parent, color, alpha, layer)
  local line = Widgets.Texture(parent, color, alpha, layer or "ARTWORK")
  line:SetHeight(1)
  return line
end

-- Hover fill drawn on the BACKGROUND layer (beneath text) and toggled by
-- OnEnter/OnLeave. A HIGHLIGHT-layer texture renders above OVERLAY font
-- strings, so an opaque hover colour there would hide the row's content.
function Widgets.HoverFill(frame, color, alpha)
  local fill = frame:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(frame)
  Widgets.SetColor(fill, color, alpha)
  fill:Hide()
  frame:HookScript("OnEnter", function() fill:Show() end)
  frame:HookScript("OnLeave", function() fill:Hide() end)
  frame:HookScript("OnHide", function() fill:Hide() end)
  frame.hoverFill = fill
  return fill
end

-- Engraved divider: black line with a faint highlight beneath. Returns a 2 px frame.
function Widgets.Engraved(parent, vertical)
  local frame = CreateFrame("Frame", nil, parent)
  local dark = Widgets.Texture(frame, C.black, 1, "ARTWORK")
  local light = Widgets.Texture(frame, C.white, 0.05, "ARTWORK")
  if vertical then
    frame:SetWidth(2)
    dark:SetPoint("TOPLEFT")
    dark:SetPoint("BOTTOMLEFT")
    dark:SetWidth(1)
    light:SetPoint("TOPRIGHT")
    light:SetPoint("BOTTOMRIGHT")
    light:SetWidth(1)
  else
    frame:SetHeight(2)
    dark:SetPoint("TOPLEFT")
    dark:SetPoint("TOPRIGHT")
    dark:SetHeight(1)
    light:SetPoint("BOTTOMLEFT")
    light:SetPoint("BOTTOMRIGHT")
    light:SetHeight(1)
  end
  return frame
end

-- Arrow glyph texture: direction "down" | "up" | "right" | "left".
function Widgets.Arrow(parent, size, direction, color)
  local tex = parent:CreateTexture(nil, "OVERLAY")
  tex:SetTexture(ARROW)
  tex:SetSize(size or 10, size or 10)
  local rotation = { right = 0, down = -math.pi / 2, up = math.pi / 2, left = math.pi }
  if tex.SetRotation then
    tex:SetRotation(rotation[direction or "right"] or 0)
  end
  if color and tex.SetVertexColor then
    tex:SetVertexColor(color[1], color[2], color[3])
  end
  return tex
end

---------------------------------------------------------------------------
-- Panel: 1 px line border, outer black ring, optional 28 px header.
---------------------------------------------------------------------------
function Widgets.Panel(parent, title, opts)
  opts = opts or {}
  local outer = Widgets.Frame(parent, nil, { border = C.black })
  local panel = Widgets.Frame(outer, nil, { bg = C.panel, border = C.line })
  panel:SetPoint("TOPLEFT", outer, "TOPLEFT", 1, -1)
  panel:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT", -1, 1)
  local topHighlight = Widgets.HLine(panel, C.white, 0.03, "BORDER")
  topHighlight:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
  topHighlight:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1)
  outer.panel = panel

  local body = CreateFrame("Frame", nil, panel)
  if title then
    local header = CreateFrame("Frame", nil, panel)
    header:SetHeight(28)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1)
    local gradient = header:CreateTexture(nil, "BACKGROUND")
    gradient:SetAllPoints(header)
    Widgets.Gradient(gradient, G.panelHeader)
    local bottom = Widgets.HLine(header, C.black, 1)
    bottom:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    local highlight = Widgets.HLine(panel, C.white, 0.04)
    highlight:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
    highlight:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -1)
    local titleText = Widgets.Text(header, "panelHeading", title, { caps = true })
    titleText:SetPoint("LEFT", header, "LEFT", 10, 0)
    outer.header = header
    outer.title = titleText
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  else
    body:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
  end
  body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -1, 1)
  outer.body = body
  outer.pad = opts.pad == false and 0 or (opts.pad or 10)

  function outer:SetTitle(text)
    if self.title then
      self.title:SetText(Theme.Upper(text))
    end
  end
  return outer
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
-- opts: primary, close, width, height, onClick, role
function Widgets.Button(parent, text, opts)
  opts = opts or {}
  local border = opts.primary and C.gold or (opts.close and C.bronze or C.bronzeDim)
  local button = Widgets.Frame(parent, nil, { frameType = "Button", border = border })
  button:SetHeight(opts.height or 24)
  local gradient = button:CreateTexture(nil, "BACKGROUND")
  gradient:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
  gradient:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
  Widgets.Gradient(gradient, opts.primary and G.buttonPrimary or (opts.close and G.buttonClose or G.button))
  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(button)
  Widgets.SetColor(highlight, C.white, 0.06)
  local shadow = Widgets.HLine(button, C.black, 1, "BORDER")
  shadow:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, 0)
  shadow:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, 0)

  local textColor = opts.primary and C.primaryText or (opts.close and C.closeText or C.text)
  local label = Widgets.Text(button, opts.role or "button", text, { color = textColor, justify = "CENTER" })
  label:SetPoint("CENTER", button, "CENTER", 0, 0)
  button.label = label
  button.textColor = textColor
  button:SetWidth(opts.width or ((label:GetStringWidth() or 40) + 20))

  if opts.onClick then
    button:SetScript("OnClick", function(self, mouseButton)
      ns.Log.Call(opts.onClick, self, mouseButton)
    end)
  end

  function button:SetLabel(value)
    label:SetText(value or "")
    if not opts.width then
      self:SetWidth((label:GetStringWidth() or 40) + 20)
    end
  end
  function button:SetEnabledState(enabled)
    if enabled then
      self:Enable()
      self:SetAlpha(1)
      Widgets.SetTextColor(label, self.textColor)
    else
      self:Disable()
      self:SetAlpha(0.6)
      Widgets.SetTextColor(label, C.text3)
    end
  end
  return button
end

-- 24 px square button holding a glyph text (settings "..." or close "X").
function Widgets.IconButton(parent, glyph, opts)
  opts = opts or {}
  opts.width = 24
  opts.height = 24
  local button = Widgets.Button(parent, glyph, opts)
  return button
end

-- [-] [ 1 ] [+]
function Widgets.Stepper(parent, onChange, opts)
  opts = opts or {}
  local frame = CreateFrame("Frame", nil, parent)
  local height = opts.height or 24
  frame:SetSize(24 + (opts.boxWidth or 44) + 24, height)
  local minus = Widgets.Button(frame, "-", { width = 24, height = height })
  minus:SetPoint("LEFT", frame, "LEFT", 0, 0)
  local box = Widgets.Frame(frame, nil, { frameType = "EditBox", bg = C.inset, border = C.lineDark })
  box:SetSize(opts.boxWidth or 44, height)
  box:SetPoint("LEFT", minus, "RIGHT", -1, 0)
  box:SetAutoFocus(false)
  box:SetNumeric(true)
  box:SetMaxLetters(5)
  box:SetJustifyH("CENTER")
  Widgets.ApplyFont(box, "number")
  box:SetTextInsets(4, 4, 0, 0)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local plus = Widgets.Button(frame, "+", { width = 24, height = height })
  plus:SetPoint("LEFT", box, "RIGHT", -1, 0)

  frame.value = 1
  frame.min = opts.min or 1
  frame.max = opts.max or 99999
  local function commit(value)
    value = ns.Util.ParseInt(value)
    if not value or value < frame.min then value = frame.min end
    if value > frame.max then value = frame.max end
    local changed = value ~= frame.value
    frame.value = value
    box:SetText(tostring(value))
    if changed and onChange then
      ns.Log.Call(onChange, value)
    end
  end
  minus:SetScript("OnClick", function() commit(frame.value - 1) end)
  plus:SetScript("OnClick", function() commit(frame.value + 1) end)
  box:SetScript("OnEnterPressed", function(self) commit(self:GetText()); self:ClearFocus() end)
  box:SetScript("OnEditFocusLost", function(self)
    if not frame.applying then
      frame.applying = true
      commit(self:GetText())
      frame.applying = false
    end
  end)
  function frame:SetValue(value)
    self.value = ns.Util.ParseInt(value) or self.min
    box:SetText(tostring(self.value))
  end
  function frame:GetValue() return self.value end
  function frame:SetEnabledState(enabled)
    minus:SetEnabledState(enabled)
    plus:SetEnabledState(enabled)
    if enabled then box:Enable() else box:Disable() end
  end
  frame.box = box
  frame.minus = minus
  frame.plus = plus
  box:SetText("1")
  return frame
end

---------------------------------------------------------------------------
-- Tabs and segments
---------------------------------------------------------------------------
-- items: { { key=, label=, disabled= }, ... }. onSelect(key). Returns strip with :Select(key).
function Widgets.Tabs(parent, items, onSelect)
  local strip = CreateFrame("Frame", nil, parent)
  strip:SetHeight(28)
  local baseline = Widgets.HLine(strip, C.bronzeDim, 1)
  baseline:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
  baseline:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)
  strip.tabs = {}
  strip.order = {}
  local previous
  for _, item in ipairs(items) do
    local tab = Widgets.Frame(strip, nil, { frameType = "Button", bg = C.tagBg, border = C.line })
    tab:SetHeight(25)
    local label = Widgets.Text(tab, "button", item.label, { color = C.text2, justify = "CENTER" })
    label:SetPoint("CENTER", tab, "CENTER", 0, 0)
    tab:SetWidth((label:GetStringWidth() or 50) + 26)
    local cover = Widgets.HLine(tab, C.panel, 1, "OVERLAY")
    cover:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 1, 0)
    cover:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -1, 0)
    cover:Hide()
    tab.label = label
    tab.cover = cover
    tab.key = item.key
    if previous then
      tab:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT", 3, 0)
    else
      tab:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
    end
    if item.disabled then
      tab:Disable()
      tab:SetAlpha(0.55)
    else
      tab:SetScript("OnClick", function()
        strip:Select(item.key)
        if onSelect then ns.Log.Call(onSelect, item.key) end
      end)
    end
    strip.tabs[item.key] = tab
    strip.order[#strip.order + 1] = item.key
    previous = tab
  end
  function strip:Select(key)
    self.selected = key
    for tabKey, tab in pairs(self.tabs) do
      if tabKey == key then
        tab:SetHeight(27)
        Widgets.SetBackdrop(tab, C.panel, C.bronzeDim)
        Widgets.SetTextColor(tab.label, C.goldLight)
        tab.cover:Show()
      else
        tab:SetHeight(25)
        Widgets.SetBackdrop(tab, C.tagBg, C.line)
        Widgets.SetTextColor(tab.label, C.text2)
        tab.cover:Hide()
      end
    end
  end
  function strip:SetLabel(key, text)
    local tab = self.tabs[key]
    if tab then
      tab.label:SetText(text)
      tab:SetWidth((tab.label:GetStringWidth() or 50) + 26)
    end
  end
  if items[1] then
    strip:Select(items[1].key)
  end
  return strip
end

-- Segmented control, 22 px. Same API as Tabs.
function Widgets.Segment(parent, items, onSelect)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetHeight(22)
  frame.segments = {}
  local previous
  local total = 0
  for index, item in ipairs(items) do
    local seg = Widgets.Frame(frame, nil, { frameType = "Button", bg = C.tagBg, border = C.lineDark })
    seg:SetHeight(22)
    local label = Widgets.Text(seg, "button", item.label, { color = C.text2, justify = "CENTER" })
    label:SetPoint("CENTER", seg, "CENTER", 0, 0)
    local width = (label:GetStringWidth() or 40) + 20
    seg:SetWidth(width)
    total = total + width - (index > 1 and 1 or 0)
    seg.label = label
    seg.key = item.key
    if previous then
      seg:SetPoint("LEFT", previous, "RIGHT", -1, 0)
    else
      seg:SetPoint("LEFT", frame, "LEFT", 0, 0)
    end
    if item.disabled then
      seg:Disable()
      seg:SetAlpha(0.55)
    else
      seg:SetScript("OnClick", function()
        frame:Select(item.key)
        if onSelect then ns.Log.Call(onSelect, item.key) end
      end)
    end
    frame.segments[item.key] = seg
    previous = seg
  end
  frame:SetWidth(total)
  function frame:Select(key)
    self.selected = key
    for segKey, seg in pairs(self.segments) do
      if segKey == key then
        Widgets.SetBackdrop(seg, Theme.RGB("#3A3428"), C.gold)
        Widgets.SetTextColor(seg.label, C.goldLight)
        seg:SetFrameLevel(frame:GetFrameLevel() + 2)
      else
        Widgets.SetBackdrop(seg, C.tagBg, C.lineDark)
        Widgets.SetTextColor(seg.label, C.text2)
        seg:SetFrameLevel(frame:GetFrameLevel() + 1)
      end
    end
  end
  if items[1] then
    frame:Select(items[1].key)
  end
  return frame
end

---------------------------------------------------------------------------
-- Badges, tags, chips, counters
---------------------------------------------------------------------------
local KIND_COLORS = { ok = C.ok, partial = C.partial, missing = C.missing, info = C.info, gold = C.gold, text = C.text2 }
Widgets.KindColors = KIND_COLORS

-- 16 px outlined caps label. badge:SetBadge(text, kind)
function Widgets.Badge(parent, text, kind)
  local badge = Widgets.Frame(parent, nil, { bg = C.black, border = KIND_COLORS[kind] or C.text2, alpha = 0.3 })
  badge:SetHeight(16)
  local label = Widgets.Text(badge, "badge", text, { caps = true, justify = "CENTER" })
  label:SetPoint("CENTER", badge, "CENTER", 0, 0)
  badge.label = label
  function badge:SetBadge(value, newKind)
    local color = KIND_COLORS[newKind] or C.text2
    label:SetText(Theme.Upper(value))
    Widgets.SetTextColor(label, color)
    Widgets.SetBackdrop(self, C.black, color, 0.3)
    self:SetWidth((label:GetStringWidth() or 30) + 12)
  end
  badge:SetBadge(text, kind)
  return badge
end

-- 16 px neutral tag ("In bags", "AH").
function Widgets.Tag(parent, text)
  local tag = Widgets.Frame(parent, nil, { bg = C.tagBg, border = C.lineDark })
  tag:SetHeight(16)
  local label = Widgets.Text(tag, "note", text, { color = C.tagText, justify = "CENTER" })
  label:SetPoint("CENTER", tag, "CENTER", 0, 0)
  tag.label = label
  function tag:SetTag(value)
    label:SetText(value or "")
    self:SetWidth((label:GetStringWidth() or 30) + 12)
  end
  tag:SetTag(text)
  return tag
end

-- 20 px chip with a coloured mark: kind "ok" (check), "missing" (x) or "info" (dot).
function Widgets.Chip(parent, kind, text)
  local chip = Widgets.Frame(parent, nil, { bg = C.tagBg, border = C.trackBorder })
  chip:SetHeight(20)
  local check = chip:CreateTexture(nil, "OVERLAY")
  check:SetTexture(CHECK)
  check:SetSize(14, 14)
  check:SetPoint("LEFT", chip, "LEFT", 5, 0)
  local mark = Widgets.Text(chip, "button", "", { justify = "CENTER" })
  mark:SetPoint("LEFT", chip, "LEFT", 8, 0)
  local label = Widgets.Text(chip, "small", text, { color = C.text })
  label:SetPoint("LEFT", chip, "LEFT", 22, 0)
  chip.label = label
  function chip:SetChip(newKind, value)
    label:SetText(value or "")
    if newKind == "ok" then
      check:Show()
      if check.SetVertexColor then check:SetVertexColor(C.ok[1], C.ok[2], C.ok[3]) end
      mark:SetText("")
    else
      check:Hide()
      mark:SetText(newKind == "missing" and "x" or "-")
      Widgets.SetTextColor(mark, newKind == "missing" and C.missing or C.text2)
    end
    self:SetWidth((label:GetStringWidth() or 40) + 30)
  end
  chip:SetChip(kind, text)
  return chip
end

-- Writes "have / need" with the have part coloured by completeness.
function Widgets.CounterText(have, need)
  local color
  if need and have >= need then
    color = Theme.Hex.ok
  elseif have and have > 0 then
    color = Theme.Hex.partial
  else
    color = Theme.Hex.missing
  end
  return string.format("%s%d|r%s / |r%d", color, have or 0, Theme.Hex.text3, need or 0)
end

function Widgets.CountColor(have, need)
  if need and have >= need then return C.ok end
  if have and have > 0 then return C.partial end
  return C.missing
end

-- 7 px status dot.
function Widgets.Dot(parent, kind)
  local dot = Widgets.Frame(parent, nil, { bg = KIND_COLORS[kind] or C.text2, border = C.black })
  dot:SetSize(7, 7)
  function dot:SetKind(newKind)
    Widgets.SetBackdrop(self, KIND_COLORS[newKind] or C.text2, C.black)
  end
  return dot
end

---------------------------------------------------------------------------
-- Progress bar: track, gradient fill, black ticks every 10 %.
---------------------------------------------------------------------------
function Widgets.ProgressBar(parent, height, kind)
  local bar = Widgets.Frame(parent, nil, { bg = C.track, border = C.trackBorder })
  bar:SetHeight(height or 8)
  local fill = bar:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
  fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
  bar.fill = fill
  bar.ticks = {}
  for i = 1, 9 do
    local tick = Widgets.Texture(bar, C.black, 0.5, "OVERLAY")
    tick:SetWidth(1)
    bar.ticks[i] = tick
  end
  bar.value = 0
  function bar:SetKind(newKind)
    local gradient = ({ gold = G.barGold, ok = G.barOk, info = G.barInfo, missing = G.barMissing, partial = G.barPartial })[newKind or "gold"] or G.barGold
    Widgets.Gradient(fill, gradient)
  end
  function bar:SetValue(value)
    value = tonumber(value) or 0
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    self.value = value
    local inner = (self:GetWidth() or 0) - 2
    if inner <= 0 then return end
    local width = inner * value
    if width < 1 then
      fill:Hide()
    else
      fill:SetWidth(width)
      fill:Show()
    end
    for i, tick in ipairs(self.ticks) do
      tick:ClearAllPoints()
      tick:SetPoint("TOPLEFT", self, "TOPLEFT", 1 + inner * i / 10, -1)
      tick:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 1 + inner * i / 10, 1)
    end
  end
  bar:SetScript("OnSizeChanged", function(self) self:SetValue(self.value) end)
  bar:SetKind(kind)
  bar:SetValue(0)
  return bar
end

---------------------------------------------------------------------------
-- Checkbox (13 px), dropdown button, popup menu, search field
---------------------------------------------------------------------------
function Widgets.Checkbox(parent, labelText, onChange)
  local frame = CreateFrame("Button", nil, parent)
  frame:SetHeight(16)
  local box = Widgets.Frame(frame, nil, { bg = C.inset, border = C.bronzeDim })
  box:SetSize(13, 13)
  box:SetPoint("LEFT", frame, "LEFT", 0, 0)
  local check = box:CreateTexture(nil, "OVERLAY")
  check:SetTexture(CHECK)
  check:SetSize(14, 14)
  check:SetPoint("CENTER", box, "CENTER", 0, 0)
  if check.SetVertexColor then check:SetVertexColor(C.goldLight[1], C.goldLight[2], C.goldLight[3]) end
  check:Hide()
  local label = Widgets.Text(frame, "button", labelText, { color = C.text })
  label:SetPoint("LEFT", box, "RIGHT", 6, 0)
  frame:SetWidth(19 + (label:GetStringWidth() or 40))
  frame.checked = false
  frame.label = label
  function frame:SetChecked(value)
    self.checked = value and true or false
    if self.checked then check:Show() else check:Hide() end
  end
  function frame:GetChecked() return self.checked end
  function frame:SetEnabledState(enabled)
    if enabled then self:Enable(); self:SetAlpha(1) else self:Disable(); self:SetAlpha(0.5) end
  end
  frame:SetScript("OnClick", function(self)
    self:SetChecked(not self.checked)
    if onChange then ns.Log.Call(onChange, self.checked) end
  end)
  return frame
end

-- Button styled as a dropdown; onClick typically opens Widgets.Menu.
function Widgets.Dropdown(parent, text, width, onClick)
  local button = Widgets.Frame(parent, nil, { frameType = "Button", border = C.bronzeDim })
  button:SetSize(width or 140, 24)
  local gradient = button:CreateTexture(nil, "BACKGROUND")
  gradient:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
  gradient:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
  Widgets.Gradient(gradient, G.dropdown)
  local label = Widgets.Text(button, "button", text, { color = C.text })
  label:SetPoint("LEFT", button, "LEFT", 8, 0)
  label:SetPoint("RIGHT", button, "RIGHT", -20, 0)
  local arrow = Widgets.Arrow(button, 9, "down", C.gold)
  arrow:SetPoint("RIGHT", button, "RIGHT", -7, 0)
  button.label = label
  function button:SetLabel(value) label:SetText(value or "") end
  function button:SetEnabledState(enabled)
    if enabled then self:Enable(); self:SetAlpha(1) else self:Disable(); self:SetAlpha(0.55) end
  end
  if onClick then
    button:SetScript("OnClick", function(self) ns.Log.Call(onClick, self) end)
  end
  return button
end

-- Shared popup menu. items: { { text=, value=, selected=, color= }, ... }; onPick(value).
local menu
local function getMenu()
  if menu then return menu end
  menu = Widgets.Frame(UIParent, "ForeverPathMenu", { bg = C.sidebar, border = C.bronzeDim })
  menu:SetFrameStrata("TOOLTIP")
  menu:SetClampedToScreen(true)
  menu:Hide()
  menu.rows = {}
  menu.catcher = CreateFrame("Button", nil, UIParent)
  menu.catcher:SetFrameStrata("DIALOG")
  menu.catcher:SetAllPoints(UIParent)
  menu.catcher:SetScript("OnClick", function() Widgets.CloseMenu() end)
  menu.catcher:Hide()
  return menu
end

function Widgets.CloseMenu()
  if menu then
    menu:Hide()
    menu.catcher:Hide()
  end
end

function Widgets.Menu(anchor, items, onPick, width)
  local popup = getMenu()
  if popup:IsShown() and popup.anchor == anchor then
    Widgets.CloseMenu()
    return
  end
  popup.anchor = anchor
  width = width or math.max(anchor:GetWidth() or 160, 160)
  popup:SetWidth(width)
  local rowHeight = 26
  for index, item in ipairs(items) do
    local row = popup.rows[index]
    if not row then
      row = CreateFrame("Button", nil, popup)
      row:SetHeight(rowHeight)
      row:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -1 - (index - 1) * rowHeight)
      row:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -1, -1 - (index - 1) * rowHeight)
      Widgets.HoverFill(row, C.raised, 1)
      row.check = row:CreateTexture(nil, "OVERLAY")
      row.check:SetTexture(CHECK)
      row.check:SetSize(14, 14)
      row.check:SetPoint("LEFT", row, "LEFT", 6, 0)
      if row.check.SetVertexColor then row.check:SetVertexColor(C.gold[1], C.gold[2], C.gold[3]) end
      row.text = Widgets.Text(row, "button", "", { color = C.text })
      row.text:SetPoint("LEFT", row, "LEFT", 24, 0)
      row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
      row.meta = Widgets.Text(row, "small", "", { justify = "RIGHT" })
      row.meta:SetPoint("RIGHT", row, "RIGHT", -8, 0)
      popup.rows[index] = row
    end
    row.text:SetText(item.text or "")
    Widgets.SetTextColor(row.text, item.color or C.text)
    row.meta:SetText(item.meta or "")
    if item.selected then row.check:Show() else row.check:Hide() end
    row:SetScript("OnClick", function()
      Widgets.CloseMenu()
      if onPick then ns.Log.Call(onPick, item.value, item) end
    end)
    row:Show()
  end
  for index = #items + 1, #popup.rows do
    popup.rows[index]:Hide()
  end
  popup:SetHeight(#items * rowHeight + 2)
  popup:ClearAllPoints()
  popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  popup.catcher:Show()
  popup:Show()
  return popup
end

-- Search / text input, 24 px, magnifier icon, placeholder. opts: width, placeholder, icon, onEnter, onChange
function Widgets.SearchField(parent, opts)
  opts = opts or {}
  local box = Widgets.Frame(parent, opts.name, { frameType = "EditBox", bg = C.inset, border = C.lineDark })
  box:SetHeight(24)
  if opts.width then box:SetWidth(opts.width) end
  box:SetAutoFocus(false)
  box:SetMaxLetters(opts.maxLetters or 255)
  Widgets.ApplyFont(box, "button")
  box:SetTextColor(C.text[1], C.text[2], C.text[3])
  local inset = 8
  if opts.icon ~= false then
    local icon = box:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(SEARCH_ICON)
    icon:SetSize(12, 12)
    icon:SetPoint("LEFT", box, "LEFT", 7, 0)
    if icon.SetVertexColor then icon:SetVertexColor(C.text2[1], C.text2[2], C.text2[3]) end
    inset = 24
  end
  box:SetTextInsets(inset, 6, 0, 0)
  local placeholder = Widgets.Text(box, "button", opts.placeholder or "", { color = C.text3 })
  placeholder:SetPoint("LEFT", box, "LEFT", inset, 0)
  placeholder:SetPoint("RIGHT", box, "RIGHT", -6, 0)
  box.placeholder = placeholder
  local function updatePlaceholder(self)
    if (self:GetText() or "") == "" and not self:HasFocus() then placeholder:Show() else placeholder:Hide() end
  end
  box:SetScript("OnTextChanged", function(self, userInput)
    updatePlaceholder(self)
    if opts.onChange then ns.Log.Call(opts.onChange, self, userInput) end
  end)
  box:SetScript("OnEditFocusGained", function(self)
    placeholder:Hide()
    Widgets.SetBackdrop(self, C.inset, C.gold)
  end)
  box:SetScript("OnEditFocusLost", function(self)
    updatePlaceholder(self)
    Widgets.SetBackdrop(self, C.inset, C.lineDark)
    if opts.onFocusLost then ns.Log.Call(opts.onFocusLost, self) end
  end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  if opts.onEnter then
    box:SetScript("OnEnterPressed", function(self) ns.Log.Call(opts.onEnter, self) end)
  end
  return box
end

---------------------------------------------------------------------------
-- Item icon with black outer ring and quality inner ring
---------------------------------------------------------------------------
function Widgets.ItemIcon(parent, size)
  local frame = Widgets.Frame(parent, nil, { border = C.black })
  frame:SetSize(size, size)
  local inner = Widgets.Frame(frame, nil, { bg = C.black, border = Theme.QualityBorder[1] })
  inner:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  inner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
  local texture = inner:CreateTexture(nil, "ARTWORK")
  texture:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -1)
  texture:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -1, 1)
  texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  frame.texture = texture
  frame.inner = inner
  function frame:SetItem(icon, quality)
    if icon then
      texture:SetTexture(icon)
      texture:Show()
    else
      texture:Hide()
    end
    local color = Theme.QualityBorder[quality or 1] or Theme.QualityBorder[1]
    Widgets.SetBackdrop(inner, C.black, color)
  end
  return frame
end

---------------------------------------------------------------------------
-- Scroll area with a minimal thumb; mouse wheel scrolling.
---------------------------------------------------------------------------
function Widgets.ScrollArea(parent)
  local scroll = CreateFrame("ScrollFrame", nil, parent)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  scroll.content = content
  local thumb = Widgets.Texture(scroll, C.bronzeDim, 0.9, "OVERLAY")
  thumb:SetWidth(4)
  thumb:Hide()
  scroll.thumb = thumb
  scroll.contentHeight = 1

  local function update()
    local viewHeight = scroll:GetHeight() or 0
    local maxScroll = scroll.contentHeight - viewHeight
    local offset = scroll:GetVerticalScroll() or 0
    if maxScroll <= 0 or viewHeight <= 0 then
      thumb:Hide()
      if offset ~= 0 then scroll:SetVerticalScroll(0) end
      return
    end
    if offset > maxScroll then
      offset = maxScroll
      scroll:SetVerticalScroll(offset)
    end
    local thumbHeight = math.max(20, viewHeight * viewHeight / scroll.contentHeight)
    local travel = viewHeight - thumbHeight
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -(travel * offset / maxScroll))
    thumb:SetHeight(thumbHeight)
    thumb:Show()
  end
  scroll.Update = update

  function scroll:SetContentHeight(height)
    self.contentHeight = math.max(1, height or 1)
    content:SetHeight(self.contentHeight)
    update()
  end
  scroll:SetScript("OnSizeChanged", function(self, width)
    if width and width > 0 then content:SetWidth(width) end
    update()
  end)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local maxScroll = math.max(0, self.contentHeight - (self:GetHeight() or 0))
    local offset = (self:GetVerticalScroll() or 0) - delta * 40
    if offset < 0 then offset = 0 end
    if offset > maxScroll then offset = maxScroll end
    self:SetVerticalScroll(offset)
    update()
  end)
  return scroll
end

-- Row pool over a content frame. factory(content, index) creates a row.
function Widgets.Pool(content, factory)
  local pool = { rows = {}, content = content, factory = factory }
  function pool:Get(index)
    local row = self.rows[index]
    if not row then
      row = self.factory(self.content, index)
      self.rows[index] = row
    end
    row:Show()
    return row
  end
  function pool:HideFrom(index)
    for i = index, #self.rows do
      self.rows[i]:Hide()
    end
  end
  return pool
end

---------------------------------------------------------------------------
-- Tooltips, money, misc
---------------------------------------------------------------------------
function Widgets.SetTooltip(frame, title, lines)
  frame:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    local t, l = title, lines
    if type(title) == "function" then t, l = title(self) end
    if not t then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(t, 1, 1, 1)
    if type(l) == "table" then
      for _, line in ipairs(l) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
    end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

function Widgets.SetItemTooltip(frame, getItemID, extraLines)
  frame:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    local itemID = getItemID(self)
    if not itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local ok = false
    if type(GameTooltip.SetItemByID) == "function" then
      ok = pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
    end
    if not ok then
      GameTooltip:SetText(ns.ItemProvider.GetName(itemID), 1, 1, 1)
    end
    if extraLines then
      local lines = extraLines(self)
      if type(lines) == "table" and #lines > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Theme.ColorText("tooltipHeader", "ForeverPath"))
        for _, line in ipairs(lines) do GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true) end
      end
    end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- Money string from copper. Uses the client's coin textures when available.
-- Money text. Uses the client's coin-icon string when available; `compact`
-- forces the short coloured-letter form (gold and silver only, or just gold
-- from 1000g) for narrow cells.
function Widgets.Money(copper, compact)
  copper = tonumber(copper) or 0
  local fn = (type(C_CurrencyInfo) == "table" and C_CurrencyInfo.GetCoinTextureString) or _G.GetCoinTextureString
  if not compact and type(fn) == "function" then
    local ok, text = pcall(fn, copper)
    if ok and text then return text end
  end
  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  local bronze = copper % 100
  if compact and gold >= 1000 then
    return string.format("%s%dg|r", Theme.Hex.coinGold, gold)
  end
  if gold > 0 then
    return string.format("%s%dg|r %s%02ds|r", Theme.Hex.coinGold, gold, Theme.Hex.coinSilver, silver)
  end
  if silver > 0 then
    return string.format("%s%ds|r %s%02dc|r", Theme.Hex.coinSilver, silver, Theme.Hex.coinCopper, bronze)
  end
  return string.format("%s%dc|r", Theme.Hex.coinCopper, bronze)
end

function Widgets.ResizeGrip(frame, onStop)
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(12, 12)
  grip:SetNormalTexture(GRIP)
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    if onStop then ns.Log.Call(onStop) end
  end)
  return grip
end

-- Centered "nothing here" state.
function Widgets.EmptyState(parent, title, text)
  local frame = CreateFrame("Frame", nil, parent)
  local titleText = Widgets.Text(frame, "body", title, { color = C.text, justify = "CENTER", wrap = true })
  titleText:SetPoint("TOP", frame, "TOP", 0, -8)
  titleText:SetPoint("LEFT", frame, "LEFT", 16, 0)
  titleText:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
  local body = Widgets.Text(frame, "secondary", text, { justify = "CENTER", wrap = true })
  body:SetPoint("TOP", titleText, "BOTTOM", 0, -6)
  body:SetPoint("LEFT", frame, "LEFT", 16, 0)
  body:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
  frame.title = titleText
  frame.text = body
  function frame:Set(newTitle, newText)
    titleText:SetText(newTitle or "")
    body:SetText(newText or "")
  end
  return frame
end
