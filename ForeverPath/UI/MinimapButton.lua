-- Minimap button with the ForeverPath mark. Left-click opens the window,
-- right-click shows or hides the goal tracker, drag moves it around the
-- minimap edge. Built on the client's own minimap textures (no library);
-- the position (an angle in degrees) and visibility are account-wide.
local _, ns = ...

local MinimapButton = {}
ns.UI.MinimapButton = MinimapButton

MinimapButton.DEFAULT_ANGLE = 225 -- lower left, clear of the clock and the zoom buttons

-- Corners that stay rounded for each minimap shape (LibDBIcon's table):
-- quadrants 1..4 are bottom-right, bottom-left, top-right, top-left.
local SHAPES = {
  ROUND = { true, true, true, true },
  SQUARE = { false, false, false, false },
  ["CORNER-TOPLEFT"] = { false, false, false, true },
  ["CORNER-TOPRIGHT"] = { false, false, true, false },
  ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
  ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
  ["SIDE-LEFT"] = { false, true, false, true },
  ["SIDE-RIGHT"] = { true, false, true, false },
  ["SIDE-TOP"] = { false, false, true, true },
  ["SIDE-BOTTOM"] = { true, true, false, false },
  ["TRICORNER-TOPLEFT"] = { false, true, true, true },
  ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
  ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
  ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function settings()
  local db = ns.db
  if not db then return nil end
  db.minimap = db.minimap or {}
  return db.minimap
end

-- The offset from the minimap's centre for an angle: on the circle where the
-- corner is round, pushed out to the square's edge where it is not.
function MinimapButton.Offset(angle, width, height, shape)
  local rad = math.rad(angle or MinimapButton.DEFAULT_ANGLE)
  local x, y = math.cos(rad), math.sin(rad)
  local q = 1
  if x < 0 then q = q + 1 end
  if y > 0 then q = q + 2 end
  local rounded = (SHAPES[shape or "ROUND"] or SHAPES.ROUND)[q]
  local w, h = (width or 140) / 2 + 5, (height or 140) / 2 + 5
  if rounded then
    return x * w, y * h
  end
  local dw, dh = math.sqrt(2 * w * w) - 10, math.sqrt(2 * h * h) - 10
  return math.max(-w, math.min(x * dw, w)), math.max(-h, math.min(y * dh, h))
end

function MinimapButton.UpdatePosition()
  local button, s = MinimapButton.button, settings()
  if not (button and s) then return end
  local shape = type(GetMinimapShape) == "function" and GetMinimapShape() or "ROUND"
  local x, y = MinimapButton.Offset(s.angle, Minimap:GetWidth(), Minimap:GetHeight(), shape)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- The angle from the minimap's centre to the cursor, in degrees.
local function cursorAngle()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  if not (mx and px and scale and scale > 0) then return nil end
  return math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
end

local function showTooltip(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText("ForeverPath " .. tostring(ns.VERSION or ""), 0.84, 0.71, 0.42)
  local goals = ns.goals and ns.goals:Count({ open = true }) or 0
  GameTooltip:AddLine(string.format("%d open goal%s", goals, goals == 1 and "" or "s"), 1, 1, 1)
  GameTooltip:AddLine("Left-click: open or close the window", 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Right-click: show or hide the goal tracker", 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Drag: move around the minimap", 0.8, 0.8, 0.8)
  GameTooltip:Show()
end

function MinimapButton.Create()
  if MinimapButton.button then return MinimapButton.button end
  if not _G.Minimap then return nil end
  local button = CreateFrame("Button", "ForeverPathMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  background:SetSize(24, 24)
  background:SetPoint("CENTER", button, "CENTER", 0, 1)

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ns.UI.LOGO)
  icon:SetSize(21, 21)
  icon:SetPoint("CENTER", button, "CENTER", 0, 1)
  button.icon = icon

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(50, 50)
  border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

  button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
      ns.UI.Tracker.Toggle()
    else
      ns.UI.MainFrame.Toggle()
    end
  end)
  button:SetScript("OnMouseDown", function() icon:SetPoint("CENTER", button, "CENTER", 1, 0) end)
  button:SetScript("OnMouseUp", function() icon:SetPoint("CENTER", button, "CENTER", 0, 1) end)
  button:SetScript("OnEnter", showTooltip)
  button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  button:SetScript("OnDragStart", function(self)
    if GameTooltip then GameTooltip:Hide() end
    self:SetScript("OnUpdate", function()
      local angle, s = cursorAngle(), settings()
      if angle and s then
        s.angle = angle
        MinimapButton.UpdatePosition()
      end
    end)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    icon:SetPoint("CENTER", button, "CENTER", 0, 1)
  end)

  MinimapButton.button = button
  MinimapButton.UpdatePosition()
  return button
end

function MinimapButton.Refresh()
  local s = settings()
  if not s then return end
  if s.hide then
    if MinimapButton.button then MinimapButton.button:Hide() end
    return
  end
  local button = MinimapButton.Create()
  if button then
    MinimapButton.UpdatePosition()
    button:Show()
  end
end

function MinimapButton.SetShown(shown)
  local s = settings()
  if not s then return end
  s.hide = not shown
  MinimapButton.Refresh()
end

function MinimapButton.ResetPosition()
  local s = settings()
  if not s then return end
  s.angle = MinimapButton.DEFAULT_ANGLE
  MinimapButton.UpdatePosition()
end

function MinimapButton.Init()
  MinimapButton.Refresh()
end
