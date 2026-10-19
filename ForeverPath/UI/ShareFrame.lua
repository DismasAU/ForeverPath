-- The share window: a text box with an export string to copy, or an empty
-- one to paste someone else's into (/fp export, /fp import).
local _, ns = ...

local Widgets = ns.UI.Widgets
local Theme = ns.UI.Theme
local C = Theme.Colors

local ShareFrame = {}
ns.UI.ShareFrame = ShareFrame

local function create()
  local frame = Widgets.Frame(UIParent, "ForeverPathShareFrame", { bg = C.panel, border = C.line })
  frame:SetSize(520, 320)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame.title = Widgets.Text(frame, "panelHeading", "", { caps = true })
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)
  frame.hint = Widgets.Text(frame, "small", "", { wrap = true })
  frame.hint:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
  frame.hint:SetPoint("RIGHT", frame, "RIGHT", -14, 0)

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -62)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 46)
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetMaxLetters(0)
  box:SetWidth(460)
  Widgets.ApplyFont(box, "small")
  box:SetScript("OnEscapePressed", function() frame:Hide() end)
  scroll:SetScrollChild(box)
  frame.box = box

  frame.import = Widgets.Button(frame, "Import", { primary = true, onClick = function()
    local ok, message = ns.Share.Import(box:GetText())
    frame.status:SetText(Theme.ColorText(ok and "ok" or "missing", message))
    if ns.UI.MainFrame then ns.UI.MainFrame.SetStatus(message, ok and "ok" or "error") end
    if ok then box:SetText("") end
  end })
  frame.import:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 12)
  frame.close = Widgets.Button(frame, "Close", { close = true, onClick = function() frame:Hide() end })
  frame.close:SetPoint("RIGHT", frame.import, "LEFT", -8, 0)
  frame.status = Widgets.Text(frame, "small", "", { wrap = true })
  frame.status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 16)
  frame.status:SetPoint("RIGHT", frame.close, "LEFT", -10, 0)
  frame:Hide()
  return frame
end

function ShareFrame.Get()
  if not ShareFrame.frame then ShareFrame.frame = create() end
  return ShareFrame.frame
end

-- Shows this account's export, selected for Ctrl+C.
function ShareFrame.ShowExport()
  local frame = ShareFrame.Get()
  local text, counts = ns.Share.Export()
  frame.title:SetText(Theme.Upper("Export your Forever data"))
  if not text then
    frame.hint:SetText(tostring(counts))
    frame.box:SetText("")
  else
    frame.hint:SetText("Press Ctrl+C to copy, then send it to a friend or guildmate; they paste it with /fp import. Contains: " .. ns.Share.Describe(counts) .. ".")
    frame.box:SetText(text)
  end
  frame.import:Hide()
  frame.status:SetText("")
  frame:Show()
  frame.box:SetFocus()
  frame.box:HighlightText()
  return text, counts
end

-- An empty box to paste an export into.
function ShareFrame.ShowImport()
  local frame = ShareFrame.Get()
  frame.title:SetText(Theme.Upper("Import Forever data"))
  frame.hint:SetText("Paste an export from /fp export (Ctrl+V) and press Import. Importing the same player again replaces their earlier copy; your own data always comes first.")
  frame.box:SetText("")
  frame.import:Show()
  frame.status:SetText("")
  frame:Show()
  frame.box:SetFocus()
end
