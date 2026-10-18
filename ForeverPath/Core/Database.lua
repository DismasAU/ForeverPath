-- SavedVariables lifecycle: defaults, versioned migrations and loading.
--
-- Two saved tables:
--   ForeverPathDB      account-wide: settings, recipe cache (recipe data is the
--                      same for every character), item name cache.
--   ForeverPathCharDB  per character: goals, which recipes this character knows,
--                      scanned professions, bank snapshot, window and tracker layout.
local _, ns = ...

local Database = {}
ns.Database = Database

local WINDOW_DEFAULTS = {
  width = 1000,
  height = 700,
  point = "CENTER",
  relativePoint = "CENTER",
  x = 0,
  y = 0,
}

Database.DEFAULTS = {
  global = {
    schemaVersion = ns.SCHEMA_VERSION,
    settings = {
      debug = false,
      includeBank = true,   -- count bank items as owned
      includeAlts = false,  -- count alts' snapshotted bags/bank as owned
      autoComplete = true,  -- complete goals when the item lands in your bags
      toasts = true,        -- celebration toast on completion
      completeSound = true, -- level-up fanfare on completion
    },
    characters = {},   -- "Name-Realm" -> snapshot (see Providers/CharacterProvider.lua)
    vendors = {},      -- itemID -> { [npcName] = { price, stack, limited, zone, subzone, seenAt } }
    trainers = {},     -- recipe spellID -> { skill, rank, cost, trainer, zone, subzone, seenAt } (see Providers/TrainerProvider.lua)
    trainerNPCs = {},  -- trainer name -> { zone, subzone, recipes, seenAt }
    recipes = {},      -- recipeID -> normalized recipe (see Domain/RecipeModel.lua)
    itemRecipes = {},  -- outputItemID -> { [recipeID] = true }
    itemNames = {},    -- itemID -> name (cheap cache for display and name search)
  },
  char = {
    schemaVersion = ns.SCHEMA_VERSION,
    goals = {},        -- goalID -> goal (see Domain/GoalModel.lua)
    selectedGoalId = nil,
    knownRecipes = {}, -- recipeID -> true (learned) / false (seen but not learned)
    professions = {},  -- professionID -> { name, skillLevel, maxSkillLevel, scannedAt, recipeCount }
    bankCache = { items = {}, scannedAt = nil },
    window = WINDOW_DEFAULTS,
    tracker = {
      hidden = false,
      collapsed = false,
      page = 1,
      point = "TOPRIGHT",
      relativePoint = "TOPRIGHT",
      x = -20,
      y = -220,
    },
    ui = {
      screen = "dashboard",
      materialSort = "missing",
      goalSort = "priority",
    },
    shopping = {
      bought = {},     -- itemID -> true (ticked off)
      included = {},   -- goalID -> true/false override of the default membership
      sort = "missing",
      filter = "all",
    },
  },
}
Database.WINDOW_DEFAULTS = WINDOW_DEFAULTS

-- Ordered migrations. Each entry: { version = N, up = function(db) ... end }.
-- A migration runs when the stored schemaVersion is below N. Keep them idempotent.
Database.migrations = {
  global = {
    -- v2: the window layout moved to the character database (copied in Load).
    { version = 2, up = function(db) db.window = nil end },
  },
  char = {
    -- v2: goals gained `tracked` and `priority`; statuses gained QUEUED/COMPLETED.
    { version = 2, up = function(db)
      local index = 0
      for _, goal in pairs(db.goals or {}) do
        if type(goal) == "table" then
          index = index + 1
          if goal.tracked == nil then goal.tracked = true end
          if goal.status == nil then goal.status = "ACTIVE" end
          if goal.priority == nil then goal.priority = index end
        end
      end
    end },
  },
}

-- Pure migration runner. Returns true plus the list of applied versions, or
-- false plus a reason. A database newer than this addon is left untouched.
function Database.Migrate(db, migrations, targetVersion)
  local from = tonumber(db.schemaVersion) or 0
  if from > targetVersion then
    return false, "newer"
  end
  local ordered = {}
  for i = 1, #(migrations or {}) do
    ordered[#ordered + 1] = migrations[i]
  end
  table.sort(ordered, function(a, b) return a.version < b.version end)
  local applied = {}
  for _, migration in ipairs(ordered) do
    if migration.version > from and migration.version <= targetVersion then
      local ok, err = pcall(migration.up, db)
      if not ok then
        return false, string.format("migration %d failed: %s", migration.version, tostring(err))
      end
      applied[#applied + 1] = migration.version
      db.schemaVersion = migration.version
    end
  end
  db.schemaVersion = targetVersion
  return true, applied
end

-- Prepares one saved table: migrations first (they see the raw stored shape),
-- then defaults for anything still missing.
function Database.Prepare(stored, defaults, migrations, targetVersion)
  if type(stored) ~= "table" then
    stored = {}
  end
  local hadVersion = stored.schemaVersion ~= nil
  local ok, info = Database.Migrate(stored, migrations, targetVersion)
  if not ok and info == "newer" then
    ns.Log.Print("Saved data was written by a newer ForeverPath version (schema %s). Running read-only compatible mode.", tostring(stored.schemaVersion))
  elseif not ok then
    ns.Log.Error("Database migration problem: %s", tostring(info))
  elseif hadVersion and #info > 0 then
    ns.Log.Debug("Applied migrations: %s", ns.Util.Join(info))
  end
  ns.Util.ApplyDefaults(stored, defaults)
  return stored
end

-- Reads the SavedVariables globals (nil on first run) and installs ns.db / ns.chardb.
-- Must be called from ADDON_LOADED or later: the client fills the globals right
-- before that event, after the addon files have already executed.
function Database.Load()
  local globalRaw = _G.ForeverPathDB
  local charRaw = _G.ForeverPathCharDB
  -- v1 stored the window account-wide; carry it over to this character once.
  if type(globalRaw) == "table" and type(globalRaw.window) == "table" then
    if type(charRaw) ~= "table" then charRaw = {} end
    if charRaw.window == nil then
      charRaw.window = ns.Util.DeepCopy(globalRaw.window)
    end
  end
  local globalTable = Database.Prepare(globalRaw, Database.DEFAULTS.global, Database.migrations.global, ns.SCHEMA_VERSION)
  local charTable = Database.Prepare(charRaw, Database.DEFAULTS.char, Database.migrations.char, ns.SCHEMA_VERSION)
  _G.ForeverPathDB = globalTable
  _G.ForeverPathCharDB = charTable
  ns.db = globalTable
  ns.chardb = charTable
  ns.Log.debugEnabled = globalTable.settings.debug and true or false
  return globalTable, charTable
end

function Database.IsLoaded()
  return ns.db ~= nil and ns.chardb ~= nil
end
