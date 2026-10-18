-- Recipe catalogue: the Forever client's own recipe tables.
--
-- Data/RecipeCatalogue.lua is generated from the installed client by
-- tools/DbExtract (scripts\extract_db.ps1). It holds every profession recipe
-- and every item-use combine the client knows (Eye of Sulfuras + Sulfuron
-- Hammer -> Sulfuras, three lesser essences -> a greater one), with reagents,
-- skill ranks, the plans or pattern that teaches each recipe, and the names,
-- quality and binding of every item involved.
--
-- This module decodes those compact rows into the shape Domain/RecipeModel.lua
-- describes (source = "catalogue", static = true) so the planner and the
-- resolver can lay out the whole path to an item before anyone on the account
-- has learned the recipe. Recipes recorded from profession windows stay the
-- primary source; the catalogue fills in everything else.
local _, ns = ...

ns.Data = ns.Data or {}

local Recipes = {
  byOutputItem = nil,   -- itemID -> { { kind, id } } built on first use
  decoded = {},         -- spellID -> recipe
  decodedCombines = {}, -- spellID -> combine recipe
}
ns.Data.Recipes = Recipes

Recipes.COMBINE_PROFESSION = "Combine"
Recipes.Bind = { NONE = 0, PICKUP = 1, EQUIP = 2, USE = 3, QUEST = 4 }

local function catalogue()
  local c = ns.Data.Catalogue
  if type(c) == "table" and type(c.recipes) == "table" then return c end
  return nil
end

function Recipes.IsAvailable()
  local c = catalogue()
  return c ~= nil and next(c.recipes) ~= nil
end

-- { build, buildName, product, locale, generated, hotfixBuild, counts } or nil.
function Recipes.Info()
  local c = catalogue()
  if not c then return nil end
  return {
    build = c.build, buildName = c.buildName, product = c.product, locale = c.locale,
    generated = c.generated, hotfixBuild = c.hotfixBuild, counts = c.counts or {},
  }
end

function Recipes.Count()
  local c = catalogue()
  return c and c.counts and c.counts.recipes or 0
end

function Recipes.CombineCount()
  local c = catalogue()
  return c and c.counts and c.counts.combines or 0
end

function Recipes.ProfessionName(skillLine)
  local c = catalogue()
  local p = c and c.professions and c.professions[skillLine]
  return p and p[1] or nil
end

function Recipes.ProfessionID(name)
  local c = catalogue()
  if not c or not c.professions or type(name) ~= "string" then return nil end
  for id, p in pairs(c.professions) do
    if p[1] == name then return id end
  end
  return nil
end

local function itemRow(itemID)
  local c = catalogue()
  return c and c.items and c.items[itemID] or nil
end

function Recipes.ItemName(itemID)
  local row = itemRow(itemID)
  local name = row and row[1] or nil
  if name == "" then return nil end
  return name
end

function Recipes.ItemQuality(itemID)
  local row = itemRow(itemID)
  if not row or row[1] == "" then return nil end
  return row[2]
end

-- classID, subclassID (Enum.ItemClass / subclass) for every item the
-- catalogue refers to, named or not; nil when the item is unknown to it.
function Recipes.ItemClass(itemID)
  local row = itemRow(itemID)
  if not row or row[4] == nil then return nil end
  return row[4], row[5]
end

-- Recipes.Bind value, or nil when the catalogue does not know the item.
function Recipes.ItemBind(itemID)
  local row = itemRow(itemID)
  if not row or row[1] == "" then return nil end
  return row[3]
end

-- Bound from the moment you get it: nobody can buy it, mail it or craft it for you.
function Recipes.IsSoulbound(itemID)
  local bind = Recipes.ItemBind(itemID)
  return bind == Recipes.Bind.PICKUP or bind == Recipes.Bind.QUEST
end

-- itemID -> { name, quality, bind } for every item the catalogue names.
function Recipes.Items()
  local c = catalogue()
  return c and c.items or {}
end

local function flatReagents(list)
  local out = {}
  for i = 1, #(list or {}), 2 do
    out[#out + 1] = { itemID = list[i], quantity = list[i + 1], slotIndex = #out + 1 }
  end
  return out
end

local function idList(value)
  if type(value) == "number" then return { value } end
  if type(value) == "table" then return value end
  return {}
end

-- A profession recipe in RecipeModel shape, plus:
--   skill = { min, yellow, green, grey }, teachItems, teachItemID, acquire
function Recipes.Get(spellID)
  local cached = Recipes.decoded[spellID]
  if cached then return cached end
  local c = catalogue()
  local row = c and c.recipes[spellID]
  if not row then return nil end
  local yellow, grey = row[6] or 0, row[7] or 0
  local recipe = {
    recipeID = spellID,
    name = row[1],
    icon = row[8] ~= 0 and row[8] or nil,
    outputItemID = row[3],
    quantityMin = row[4],
    quantityMax = row[4],
    recipeType = 1,
    professionID = row[2],
    professionName = Recipes.ProfessionName(row[2]),
    reagents = flatReagents(row[11]),
    source = "catalogue",
    static = true,
    skill = { min = row[5] or 0, yellow = yellow, green = math.floor((yellow + grey) / 2), grey = grey },
    teachItems = idList(row[9]),
    acquire = row[10],
  }
  recipe.teachItemID = recipe.teachItems[1]
  Recipes.ApplyTrainer(recipe)
  Recipes.decoded[spellID] = recipe
  return recipe
end

-- The client's tables do not carry the skill a trainer requires (it is
-- server data), so the trainer recorder (Providers/TrainerProvider.lua)
-- supplies it through Recipes.trainerLookup(spellID) -> { skill, rank, cost,
-- trainer, zone, subzone }. The recorded rank replaces a lower catalogue
-- value and the recipe remembers where it is taught.
Recipes.trainerLookup = nil

function Recipes.ApplyTrainer(recipe)
  local lookup = Recipes.trainerLookup
  if type(lookup) ~= "function" then return recipe end
  local ok, record = pcall(lookup, recipe.recipeID)
  if not ok or type(record) ~= "table" then return recipe end
  recipe.trainer = { name = record.trainer, zone = record.zone, subzone = record.subzone, cost = record.cost, skill = record.skill, rank = record.rank }
  if tonumber(record.rank) and record.rank > (recipe.skill.min or 0) then
    recipe.skill.min = record.rank
    recipe.skill.source = "trainer"
  end
  return recipe
end

-- Drops decoded recipes so new trainer data is picked up on the next lookup.
function Recipes.Invalidate()
  Recipes.decoded = {}
end

-- An item-use combine in RecipeModel shape: professionID 0, combine = true.
-- The used item counts as a reagent when it is spent, as a tool otherwise
-- (tools = items of which any one must be in the bags).
function Recipes.GetCombine(spellID)
  local cached = Recipes.decodedCombines[spellID]
  if cached then return cached end
  local c = catalogue()
  local row = c and c.combines and c.combines[spellID]
  if not row then return nil end
  local reagents = flatReagents(row[6])
  local useItems = row[5] or {}
  local consumes = row[4] == 1
  local tools = {}
  for _, useItem in ipairs(useItems) do
    local listed = false
    for _, reagent in ipairs(reagents) do
      if reagent.itemID == useItem then listed = true end
    end
    if not listed then
      if consumes then
        reagents[#reagents + 1] = { itemID = useItem, quantity = 1, slotIndex = #reagents + 1 }
      else
        tools[#tools + 1] = useItem
      end
    end
  end
  local combine = {
    recipeID = spellID,
    name = row[1],
    outputItemID = row[2],
    quantityMin = row[3],
    quantityMax = row[3],
    recipeType = 1,
    professionID = 0,
    professionName = Recipes.COMBINE_PROFESSION,
    combine = true,
    reagents = reagents,
    tools = tools,
    useItems = useItems,
    consumesUseItem = consumes,
    source = "catalogue",
    static = true,
  }
  Recipes.decodedCombines[spellID] = combine
  return combine
end

-- itemID -> list of { kind = "recipe" | "combine", id = spellID }, recipes first.
function Recipes.Index()
  if Recipes.byOutputItem then return Recipes.byOutputItem end
  local index = {}
  local c = catalogue()
  if c then
    for spellID, row in pairs(c.recipes) do
      local list = index[row[3]]
      if not list then list = {} index[row[3]] = list end
      list[#list + 1] = { kind = "recipe", id = spellID }
    end
    for spellID, row in pairs(c.combines or {}) do
      local list = index[row[2]]
      if not list then list = {} index[row[2]] = list end
      list[#list + 1] = { kind = "combine", id = spellID }
    end
    for _, list in pairs(index) do
      table.sort(list, function(a, b)
        if a.kind ~= b.kind then return a.kind == "recipe" end
        return a.id < b.id
      end)
    end
  end
  Recipes.byOutputItem = index
  return index
end

-- Every catalogue recipe and combine that produces itemID, or nil.
function Recipes.Lookup(itemID)
  local entries = Recipes.Index()[itemID]
  if not entries then return nil end
  local out = {}
  for _, entry in ipairs(entries) do
    local recipe = entry.kind == "recipe" and Recipes.Get(entry.id) or Recipes.GetCombine(entry.id)
    if recipe then out[#out + 1] = recipe end
  end
  if #out == 0 then return nil end
  return out
end

function Recipes.IsCraftable(itemID)
  return Recipes.Index()[itemID] ~= nil
end

-- Every catalogue recipe (spell ids, ascending) of a profession skill line.
function Recipes.ForProfession(professionID)
  if not Recipes.byProfession then
    local index = {}
    local c = catalogue()
    for spellID, row in pairs(c and c.recipes or {}) do
      local list = index[row[2]]
      if not list then list = {} index[row[2]] = list end
      list[#list + 1] = spellID
    end
    for _, list in pairs(index) do table.sort(list) end
    Recipes.byProfession = index
  end
  return Recipes.byProfession[professionID] or {}
end

-- { { id, name, category } } for every profession in the catalogue, by name.
function Recipes.Professions()
  local c = catalogue()
  local out = {}
  for id, p in pairs(c and c.professions or {}) do
    out[#out + 1] = { id = id, name = p[1], category = p[2] }
  end
  table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
  return out
end

-- Profession id and name from free text (case-insensitive, prefix allowed).
function Recipes.FindProfession(text)
  if type(text) ~= "string" then return nil end
  local wanted = string.lower(text:gsub("^%s+", ""):gsub("%s+$", ""))
  if wanted == "" then return nil end
  local prefix
  for _, p in ipairs(Recipes.Professions()) do
    local name = string.lower(p.name or "")
    if name == wanted then return p.id, p.name end
    if not prefix and name:sub(1, #wanted) == wanted then prefix = p end
  end
  if prefix then return prefix.id, prefix.name end
  return nil
end

-- Recipes whose name contains text: { { spellID, name, professionName, professionID } },
-- exact matches first, then prefix matches, then the rest, each by name.
function Recipes.Search(text, limit, professionName)
  local c = catalogue()
  if not c or type(text) ~= "string" then return {} end
  local needle = string.lower(text:gsub("^%s+", ""):gsub("%s+$", ""))
  if needle == "" then return {} end
  local wantedProfession = professionName and Recipes.ProfessionID(professionName) or nil
  local hits = {}
  for spellID, row in pairs(c.recipes) do
    local name = row[1] or ""
    local lower = string.lower(name)
    local position = lower:find(needle, 1, true)
    if position and (not wantedProfession or row[2] == wantedProfession) then
      local rank = lower == needle and 0 or (position == 1 and 1 or 2)
      hits[#hits + 1] = { spellID = spellID, name = name, professionID = row[2], professionName = Recipes.ProfessionName(row[2]), rank = rank }
    end
  end
  table.sort(hits, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.name ~= b.name then return a.name < b.name end
    return a.spellID < b.spellID
  end)
  if limit and #hits > limit then
    for i = #hits, limit + 1, -1 do hits[i] = nil end
  end
  return hits
end

-- Recipe spell id by recipe name (case-insensitive), preferring the given
-- profession when several professions share a name. Used when a trainer
-- line carries no spell link.
function Recipes.SpellIDByName(name, professionName)
  if type(name) ~= "string" or name == "" then return nil end
  local c = catalogue()
  if not c then return nil end
  if not Recipes.byName then
    local index = {}
    for spellID, row in pairs(c.recipes) do
      local key = string.lower(row[1] or "")
      local list = index[key]
      if not list then list = {} index[key] = list end
      list[#list + 1] = spellID
    end
    for _, list in pairs(index) do table.sort(list) end
    Recipes.byName = index
  end
  local list = Recipes.byName[string.lower(name)]
  if not list then return nil end
  if professionName then
    local wanted = Recipes.ProfessionID(professionName)
    for _, spellID in ipairs(list) do
      if wanted and c.recipes[spellID][2] == wanted then return spellID end
    end
  end
  return list[1]
end

-- One line for the status bar and /fp catalogue.
function Recipes.Status()
  local info = Recipes.Info()
  if not info or Recipes.Count() == 0 then
    return "Recipe catalogue missing: run scripts\\extract_db.ps1 to generate it from the client."
  end
  return string.format("Recipe catalogue: %d recipes, %d combines, %d items (client build %s, generated %s).",
    info.counts.recipes or 0, info.counts.combines or 0, info.counts.items or 0, tostring(info.build), tostring(info.generated))
end

-- Chat lines describing how itemID is made. nameOf(itemID) -> display name.
function Recipes.Lines(itemID, nameOf)
  nameOf = nameOf or function(id) return Recipes.ItemName(id) or ("Item " .. tostring(id)) end
  local lines = {}
  for _, recipe in ipairs(Recipes.Lookup(itemID) or {}) do
    local parts = {}
    for _, reagent in ipairs(recipe.reagents) do
      parts[#parts + 1] = string.format("%d %s", reagent.quantity, nameOf(reagent.itemID))
    end
    local head
    if recipe.combine then
      head = string.format("Combine (use %s): %s x%d", nameOf(recipe.useItems[1] or 0), recipe.name, recipe.quantityMin)
    else
      local skill = recipe.skill
      head = string.format("%s %d (yellow %d, grey %d): %s x%d", recipe.professionName or "?", skill.min, skill.yellow, skill.grey, recipe.name, recipe.quantityMin)
      if recipe.teachItemID then
        head = head .. " - taught by " .. nameOf(recipe.teachItemID)
      elseif recipe.trainer and recipe.trainer.name then
        local where = recipe.trainer.zone or "?"
        if recipe.trainer.subzone then where = where .. " - " .. recipe.trainer.subzone end
        head = head .. string.format(" - trainer %s (%s)", recipe.trainer.name, where)
      else
        head = head .. " - trainer (requirement not recorded yet)"
      end
    end
    lines[#lines + 1] = head
    lines[#lines + 1] = "  needs " .. table.concat(parts, ", ")
    if recipe.tools and #recipe.tools > 0 then
      lines[#lines + 1] = "  using " .. nameOf(recipe.tools[1]) .. " (not consumed)"
    end
  end
  return lines
end
