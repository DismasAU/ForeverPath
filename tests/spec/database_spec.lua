local H = require("harness")

describe("Database", function()
  local ns
  before_each(function() ns = H.fresh() end)

  it("runs migrations in order and stamps the schema version", function()
    local db = { legacyGoals = { "a" } }
    local log = {}
    local migrations = {
      { version = 2, up = function(d) log[#log + 1] = 2; d.goalsV2 = d.legacyGoals; d.legacyGoals = nil end },
      { version = 1, up = function(d) log[#log + 1] = 1; d.touched = true end },
    }
    local ok, applied = ns.Database.Migrate(db, migrations, 2)
    assert_true(ok)
    assert_deep_eq(applied, { 1, 2 })
    assert_deep_eq(log, { 1, 2 })
    assert_eq(db.schemaVersion, 2)
    assert_deep_eq(db.goalsV2, { "a" })
    assert_nil(db.legacyGoals)
  end)

  it("skips migrations already applied", function()
    local db = { schemaVersion = 1 }
    local ran = false
    local ok, applied = ns.Database.Migrate(db, { { version = 1, up = function() ran = true end } }, 1)
    assert_true(ok)
    assert_eq(#applied, 0)
    assert_false(ran)
  end)

  it("refuses to downgrade newer data", function()
    local db = { schemaVersion = 99, keep = true }
    local ok, reason = ns.Database.Migrate(db, {}, 1)
    assert_false(ok)
    assert_eq(reason, "newer")
    assert_eq(db.schemaVersion, 99)
  end)

  it("reports a failing migration", function()
    local db = {}
    local ok, reason = ns.Database.Migrate(db, { { version = 1, up = function() error("boom") end } }, 1)
    assert_false(ok)
    assert_match(reason, "migration 1 failed")
  end)

  it("creates saved tables on first run", function()
    ns.Database.Load()
    assert_not_nil(_G.ForeverPathDB)
    assert_not_nil(_G.ForeverPathCharDB)
    assert_eq(ns.db.schemaVersion, ns.SCHEMA_VERSION)
    assert_eq(ns.chardb.schemaVersion, ns.SCHEMA_VERSION)
    assert_eq(ns.db.settings.includeBank, true)
    assert_deep_eq(ns.chardb.goals, {})
  end)

  it("keeps existing settings and fills missing defaults", function()
    _G.ForeverPathDB = { settings = { debug = true } }
    _G.ForeverPathCharDB = { goals = { x = "garbage" } }
    ns.Database.Load()
    assert_eq(ns.db.settings.debug, true)
    assert_eq(ns.db.settings.includeBank, true)
    assert_eq(ns.chardb.window.width, 1000)
    assert_eq(ns.chardb.tracker.page, 1)
    assert_eq(ns.chardb.ui.screen, "dashboard")
    assert_eq(ns.Log.debugEnabled, true)
    assert_eq(ns.chardb.goals.x, "garbage", "sanitising goals is the store's job, not the loader's")
  end)

  it("migrates v1 data: window moves per character, goals gain tracking fields", function()
    local goal = { id = "fp-1-1-0001", type = "CRAFT_ITEM", target = { itemID = 2996, quantity = 2 }, createdAt = 5 }
    _G.ForeverPathDB = { schemaVersion = 1, settings = {}, window = { width = 900, height = 600, point = "TOPLEFT", x = 10, y = -10 } }
    _G.ForeverPathCharDB = { schemaVersion = 1, goals = { [goal.id] = goal } }
    ns.Database.Load()
    assert_eq(ns.db.schemaVersion, 2)
    assert_nil(ns.db.window, "window removed from the account table")
    assert_eq(ns.chardb.schemaVersion, 2)
    assert_eq(ns.chardb.window.width, 900)
    assert_eq(ns.chardb.window.point, "TOPLEFT")
    assert_eq(ns.chardb.window.relativePoint, "CENTER", "missing fields come from defaults")
    local migrated = ns.chardb.goals[goal.id]
    assert_eq(migrated.tracked, true)
    assert_eq(migrated.status, "ACTIVE")
    assert_eq(migrated.priority, 1)
  end)
end)
