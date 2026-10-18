-- Preview modules: Equipment and Reputations.
-- Each shows the "coming in a later version" empty state from the handoff.
local _, ns = ...

local Widgets = ns.UI.Widgets

ns.UI.Screens = ns.UI.Screens or {}

local PREVIEWS = {
  equipment = { label = "Equipment", text = "Equipped gear, best-in-slot targets and upgrade goals per slot." },
  reputations = { label = "Reputations", text = "Reputation goals with standing progress and the turn-ins that move them." },
}

local function Create(parent, key)
  local def = PREVIEWS[key]
  local screen = CreateFrame("Frame", nil, parent)
  local panel = Widgets.Panel(screen, def.label)
  panel:SetAllPoints(screen)
  local empty = Widgets.EmptyState(panel.body, def.label .. " - coming in a later version", def.text)
  empty:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, -60)
  empty:SetPoint("TOPRIGHT", panel.body, "TOPRIGHT", 0, -60)
  empty:SetHeight(100)
  function screen:Refresh() end
  return screen
end

for key, def in pairs(PREVIEWS) do
  ns.UI.Screens[key] = { label = def.label, preview = true, Create = Create }
end
