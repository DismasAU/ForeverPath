-- Design tokens from the ForeverPath design handoff (design/component-helpers.js).
-- Colours are {r, g, b} in 0..1; `Hex` holds the inline "|cff..." form for text.
local _, ns = ...

ns.UI = ns.UI or {}
local Theme = {}
ns.UI.Theme = Theme

-- The ForeverPath mark (PNG, 128 px, the same file the TOC uses as IconTexture).
ns.UI.LOGO = "Interface\\AddOns\\ForeverPath\\Media\\ForeverPath-Mark.png"

local function rgb(hex)
  local r, g, b = hex:match("#?(%x%x)(%x%x)(%x%x)")
  return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end
Theme.RGB = rgb

local palette = {
  bg = "#171714", panel = "#24231F", raised = "#302D26", sidebar = "#1C1B18",
  inset = "#0E0E0C", track = "#0D0D0B", statusbar = "#11110E", tagBg = "#1A1916",
  bronze = "#8F7140", bronzeDim = "#6E5A36", line = "#3A3529", lineDark = "#4A4335",
  guide = "#5F5543", ring = "#2A251C", trackBorder = "#3D382D", rowLine = "#33302A",
  gold = "#D7B66A", goldLight = "#F3DFA6", text = "#E8DFCC", text2 = "#A9A18E",
  text3 = "#7D745F", tagText = "#C9C0AC",
  ok = "#64AE76", partial = "#D9A441", missing = "#D67A62", info = "#6F9FCA",
  okDark = "#2F6A3E", goldDark = "#8A6A2A", missingDark = "#8A3A2A",
  partialDark = "#8A6420", infoDark = "#35618A",
  primaryText = "#FBEBC0", closeText = "#F0D0B0",
  coinGold = "#E6C25A", coinSilver = "#C3C8CC", coinCopper = "#C07A45",
  tooltipHeader = "#FFD100",
  -- Quest level difficulty, as the default UI colours them.
  questTrivial = "#9D9D9D", questEasy = "#40C040", questStandard = "#FFD100", questHard = "#FF8040", questImpossible = "#FF2020",
  questReadyBg = "#1C2A1E", questReadyBorder = "#3E6A48",
}

Theme.Colors = {}
Theme.Hex = {}
for key, hex in pairs(palette) do
  Theme.Colors[key] = rgb(hex)
  Theme.Hex[key] = "|cff" .. hex:sub(2)
end
Theme.Colors.black = { 0, 0, 0 }
Theme.Colors.white = { 1, 1, 1 }
Theme.Hex.white = "|cffffffff"

-- Gradients: { top, bottom }
Theme.Gradients = {
  header = { rgb("#2E2B25"), rgb("#1F1E1A") },
  panelHeader = { rgb("#2C2A24"), rgb("#24231F") },
  button = { rgb("#3A352B"), rgb("#24211C") },
  buttonPrimary = { rgb("#6A5224"), rgb("#3E2E12") },
  buttonClose = { rgb("#6A2418"), rgb("#3A120C") },
  dropdown = { rgb("#2A2721"), rgb("#1C1B18") },
  navActive = { rgb("#3A3428"), rgb("#2A2720") },
  barGold = { rgb("#D7B66A"), rgb("#8A6A2A") },
  barOk = { rgb("#64AE76"), rgb("#2F6A3E") },
  barInfo = { rgb("#6F9FCA"), rgb("#35618A") },
  barMissing = { rgb("#D67A62"), rgb("#8A3A2A") },
  barPartial = { rgb("#D9A441"), rgb("#8A6420") },
}

-- Item quality colours apply to item names only; borders go around icons.
Theme.Quality = {
  [0] = rgb("#9D9D9D"), [1] = rgb("#F2EEE6"), [2] = rgb("#1EFF00"),
  [3] = rgb("#3B8EEA"), [4] = rgb("#B048F8"), [5] = rgb("#FF8000"),
}
Theme.QualityHex = {
  [0] = "|cff9D9D9D", [1] = "|cffF2EEE6", [2] = "|cff1EFF00",
  [3] = "|cff3B8EEA", [4] = "|cffB048F8", [5] = "|cffFF8000",
}
Theme.QualityBorder = {
  [0] = rgb("#6B6352"), [1] = rgb("#6B6352"), [2] = rgb("#1F8F12"),
  [3] = rgb("#2A6FC0"), [4] = rgb("#7A2AB8"), [5] = rgb("#7A2AB8"),
}

function Theme.QualityColor(quality)
  return Theme.Quality[quality] or Theme.Quality[1]
end

function Theme.ColorText(key, text)
  return (Theme.Hex[key] or "") .. tostring(text) .. "|r"
end

function Theme.QualityText(name, quality)
  return (Theme.QualityHex[quality] or Theme.QualityHex[1]) .. tostring(name) .. "|r"
end

function Theme.Upper(text)
  return string.upper(tostring(text or ""))
end

-- Fonts. The handoff uses Marcellus (headings) and Alegreya Sans (body); the
-- documented fallback is FRIZQT__ for headings and ARIALN for body. To bundle
-- the real fonts, place the TTFs in ForeverPath\Fonts and change these paths.
Theme.FontFiles = {
  heading = "Fonts\\FRIZQT__.TTF",
  body = "Fonts\\ARIALN.TTF",
}
local CLIENT_FALLBACK = { heading = "Fonts\\FRIZQT__.TTF", body = "Fonts\\ARIALN.TTF" }

-- role = { family, size, flags, colorKey }
local roles = {
  title = { "heading", 18, "", "gold" },
  hero = { "heading", 22, "", "text" },
  goalName = { "heading", 15, "", "text" },
  panelHeading = { "heading", 12, "", "gold" },
  bigNumber = { "heading", 20, "", "text" },
  bigNumberLarge = { "heading", 26, "", "text" },
  trackerTitle = { "heading", 11, "", "gold" },
  body = { "body", 13, "", "text" },
  bodyMuted = { "body", 13, "", "text2" },
  secondary = { "body", 12, "", "text2" },
  secondaryBright = { "body", 12, "", "text" },
  small = { "body", 11, "", "text2" },
  label = { "body", 10, "", "text2" },
  badge = { "body", 10, "", "text" },
  note = { "body", 10, "", "text2" },
  tagline = { "body", 9, "", "text2" },
  nav = { "body", 13, "", "text" },
  button = { "body", 12, "", "text" },
  tableHeader = { "body", 10, "", "text2" },
  number = { "body", 13, "", "text" },
}

-- Blizzard font objects used when CreateFont is unavailable (tests, odd clients).
Theme.Fallback = {
  title = "GameFontNormalLarge", hero = "GameFontNormalHuge", goalName = "GameFontNormal",
  panelHeading = "GameFontNormalSmall", bigNumber = "GameFontNormalLarge", bigNumberLarge = "GameFontNormalHuge",
  trackerTitle = "GameFontNormalSmall", body = "GameFontHighlight", bodyMuted = "GameFontDisable",
  secondary = "GameFontHighlightSmall", secondaryBright = "GameFontHighlightSmall", small = "GameFontDisableSmall",
  label = "GameFontDisableSmall", badge = "GameFontHighlightSmall", note = "GameFontDisableSmall",
  tagline = "GameFontDisableSmall", nav = "GameFontHighlight", button = "GameFontHighlightSmall",
  tableHeader = "GameFontDisableSmall", number = "GameFontHighlight",
}

Theme.Fonts = {}

function Theme.BuildFonts()
  if type(CreateFont) ~= "function" then
    return false
  end
  for role, def in pairs(roles) do
    local font = CreateFont("ForeverPathFont_" .. role)
    local file = Theme.FontFiles[def[1]] or CLIENT_FALLBACK[def[1]]
    local ok = font:SetFont(file, def[2], def[3])
    if ok == false then
      font:SetFont(CLIENT_FALLBACK[def[1]], def[2], def[3])
    end
    local color = Theme.Colors[def[4]] or Theme.Colors.text
    font:SetTextColor(color[1], color[2], color[3])
    Theme.Fonts[role] = font
  end
  return true
end

Theme.BuildFonts()
