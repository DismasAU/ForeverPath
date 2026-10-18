-- Celebration toast: a small gold-bordered panel that drops in at the top of
-- the screen when a goal completes, holds a few seconds, then fades. Toasts
-- queue so two completions in a row both show. Clicking it opens My Goals.
local _, ns = ...

local Widgets = ns.UI.Widgets
local Theme = ns.UI.Theme
local C = Theme.Colors

local Toast = { queue = {}, HOLD = 6, WIDTH = 340, HEIGHT = 76 }
ns.UI.Toast = Toast

local function build()
  local frame = Widgets.Frame(UIParent, "ForeverPathToast", { frameType = "Button", bg = Theme.RGB("#1C1B18"), border = C.gold })
  frame:SetSize(Toast.WIDTH, Toast.HEIGHT)
  frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
  frame:SetFrameStrata("HIGH")
  frame:Hide()
  local inner = Widgets.Frame(frame, nil, { bg = C.panel, border = C.black })
  inner:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
  inner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
  local glow = inner:CreateTexture(nil, "BACKGROUND")
  glow:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -1)
  glow:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -1, 1)
  Widgets.Gradient(glow, Theme.Gradients.buttonPrimary)
  glow:SetAlpha(0.35)
  local topLine = Widgets.HLine(inner, C.goldLight, 0.5)
  topLine:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -1)
  topLine:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -1)
  local icon = Widgets.ItemIcon(inner, 44)
  icon:SetPoint("LEFT", inner, "LEFT", 14, 0)
  local title = Widgets.Text(inner, "panelHeading", "Goal complete", { caps = true })
  title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 2)
  local name = Widgets.Text(inner, "goalName", "")
  name:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  name:SetPoint("RIGHT", inner, "RIGHT", -12, 0)
  local sub = Widgets.Text(inner, "small", "")
  sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
  sub:SetPoint("RIGHT", inner, "RIGHT", -12, 0)
  local close = Widgets.Text(inner, "small", "x", { color = C.text3 })
  close:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -8, -6)
  frame.icon, frame.title, frame.name, frame.sub = icon, title, name, sub
  frame:SetScript("OnClick", function(self)
    Toast.Dismiss()
    if self.goalID and ns.UI.MainFrame then
      ns.UI.MainFrame.Show()
      ns.UI.MainFrame.ShowScreen("goals")
    end
  end)
  Widgets.SetTooltip(frame, "ForeverPath", { "Click to open My Goals.", "Toasts can be turned off with /fp celebrate off." })
  return frame
end

function Toast.Frame()
  if not Toast.frame then
    Toast.frame = build()
  end
  return Toast.frame
end

local function showNext()
  local frame = Toast.Frame()
  local opts = table.remove(Toast.queue, 1)
  if not opts then
    Toast.showing = nil
    return
  end
  Toast.showing = opts
  Toast.lastShown = opts
  Toast.shownCount = (Toast.shownCount or 0) + 1
  Toast.generation = (Toast.generation or 0) + 1
  local generation = Toast.generation
  frame.goalID = opts.goalID
  frame.icon:SetItem(opts.icon, opts.quality)
  frame.title:SetText(Theme.Upper(opts.title or "Goal complete"))
  frame.name:SetText(Theme.QualityText(opts.name or "", opts.quality or 1))
  frame.sub:SetText(opts.detail and (opts.detail .. (opts.sub and ("  -  " .. opts.sub) or "")) or (opts.sub or ""))
  frame:SetAlpha(1)
  frame:Show()
  if ns.Compat.After then
    ns.Compat.After(Toast.HOLD, function()
      if Toast.generation == generation then Toast.Dismiss() end
    end)
  end
end

-- opts: { title, name, quality, icon, detail, sub, goalID }
function Toast.Show(opts)
  Toast.queue[#Toast.queue + 1] = opts or {}
  if not Toast.showing and not Toast.fading then
    showNext()
  end
end

function Toast.Dismiss()
  local frame = Toast.frame
  if not frame or not frame:IsShown() then
    Toast.showing = nil
    return
  end
  Toast.showing = nil
  local function finish()
    Toast.fading = nil
    frame:Hide()
    if #Toast.queue > 0 then showNext() end
  end
  if type(UIFrameFadeOut) == "function" and ns.Compat.After then
    Toast.fading = true
    pcall(UIFrameFadeOut, frame, 0.4, 1, 0)
    ns.Compat.After(0.4, finish)
  else
    finish()
  end
end

-- A sample toast for /fp celebrate test.
function Toast.Test()
  Toast.Show({ title = "Goal complete", name = "Linen Bag", quality = 1, detail = "Crafted 1x Linen Bag", sub = "this is a test", icon = 133639 })
end
