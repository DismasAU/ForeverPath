local H = require("harness")

describe("GoalStore", function()
  local ns, GoalStore
  before_each(function()
    ns = H.fresh()
    GoalStore = ns.GoalStore
  end)

  local function newStore(storage, events)
    return GoalStore.New(storage or {}, {
      onChange = function(event, goal)
        if events then events[#events + 1] = event end
      end,
      now = function() return 1000 end,
    })
  end

  it("creates, lists in priority order and counts goals", function()
    local store = newStore()
    local a = store:Create("CRAFT_ITEM", { itemID = 1, quantity = 1 }, { now = 10 })
    local b = store:Create("CRAFT_ITEM", { itemID = 2, quantity = 1 }, { now = 5 })
    assert_eq(store:Count(), 2)
    local list = store:List()
    assert_eq(list[1].id, a.id, "first created gets priority 1 regardless of timestamps")
    assert_eq(list[2].id, b.id)
    a.priority, b.priority = nil, nil
    list = store:List()
    assert_eq(list[1].id, b.id, "without priorities, creation time decides")
  end)

  it("rejects invalid and duplicate goals", function()
    local store = newStore()
    local goal, err = store:Create("CRAFT_ITEM", { itemID = 0, quantity = 1 })
    assert_nil(goal)
    assert_match(err, "itemID")
    local ok = store:Create("CRAFT_ITEM", { itemID = 1, quantity = 1 })
    local dup, dupErr = store:Add(ok)
    assert_nil(dup)
    assert_eq(dupErr, "duplicate goal id")
  end)

  it("selects, removes and moves the selection", function()
    local events = {}
    local store = newStore(nil, events)
    local a = store:Create("CRAFT_ITEM", { itemID = 1, quantity = 1 }, { now = 1 })
    local b = store:Create("CRAFT_ITEM", { itemID = 2, quantity = 1 }, { now = 2 })
    assert_true(store:Select(b.id))
    assert_eq(store:GetSelected().id, b.id)
    assert_false(store:Select("missing"))
    assert_eq(store:Remove(b.id).id, b.id)
    assert_eq(store:GetSelectedID(), a.id, "selection falls back to the first remaining goal")
    assert_eq(store:Remove(a.id).id, a.id)
    assert_nil(store:GetSelectedID())
    assert_nil(store:Remove("missing"))
    assert_deep_eq(events, { "added", "added", "selected", "removed", "removed" })
  end)

  it("updates quantity through the store", function()
    local events = {}
    local store = newStore(nil, events)
    local goal = store:Create("CRAFT_ITEM", { itemID = 1, quantity = 1 })
    assert_true(store:SetQuantity(goal.id, 4))
    assert_eq(goal.target.quantity, 4)
    assert_eq(goal.updatedAt, 1000)
    local ok, err = store:SetQuantity(goal.id, -1)
    assert_false(ok)
    assert_match(err, "quantity")
    assert_false((store:SetQuantity("missing", 2)))
    assert_eq(events[#events], "updated")
  end)

  it("assigns priorities, filters by status and renumbers", function()
    local store = newStore()
    local a = store:Create("CRAFT_ITEM", { itemID = 1, quantity = 1 }, { now = 1 })
    local b = store:Create("CRAFT_ITEM", { itemID = 2, quantity = 1 }, { now = 2 })
    local c = store:Create("CRAFT_ITEM", { itemID = 3, quantity = 1 }, { now = 3 })
    assert_eq(a.priority, 1)
    assert_eq(c.priority, 3)
    assert_true(store:SetPriority(c.id, 1))
    local open = store:List({ open = true })
    assert_eq(open[1].id, c.id)
    assert_eq(open[2].id, a.id)
    assert_eq(a.priority, 2)
    assert_true(store:SetStatus(b.id, "PAUSED"))
    assert_eq(store:List({ status = "PAUSED" })[1].id, b.id)
    assert_eq(store:List({ open = true })[3].id, b.id, "paused goals sort after active ones")
    assert_true(store:SetStatus(a.id, "COMPLETED"))
    assert_eq(store:Count({ open = true }), 2)
    assert_eq(store:Count({ status = "COMPLETED" }), 1)
    assert_eq(c.priority, 1)
    assert_eq(b.priority, 2, "renumbered after completion")
    assert_true(store:SetTracked(c.id, false))
    assert_eq(#store:List({ open = true, tracked = true }), 1)
    assert_eq(store:List({ open = true, tracked = true })[1].id, b.id)
    local ok, err = store:SetStatus(a.id, "NOPE")
    assert_false(ok)
    assert_match(err, "status")
  end)

  it("finds goals by item", function()
    local store = newStore()
    local goal = store:Create("CRAFT_ITEM", { itemID = 77, quantity = 1 })
    assert_eq(store:FindByItem("CRAFT_ITEM", 77).id, goal.id)
    assert_nil(store:FindByItem("CRAFT_ITEM", 78))
    assert_nil(store:FindByItem("OBTAIN_ITEM", 77))
  end)

  it("drops malformed saved goals and clears a dangling selection", function()
    local good = ns.GoalModel.New("CRAFT_ITEM", { itemID = 1, quantity = 1 })
    local storage = {
      goals = {
        [good.id] = good,
        broken = { id = "broken", type = "CRAFT_ITEM", target = { itemID = "x" } },
        ["wrong-key"] = ns.GoalModel.New("CRAFT_ITEM", { itemID = 2, quantity = 1 }),
        notatable = 5,
      },
      selectedGoalId = "broken",
    }
    local store = newStore(storage)
    assert_eq(store.dropped, 3)
    assert_eq(store:Count(), 1)
    assert_nil(storage.selectedGoalId)
  end)

  it("round-trips through the storage table like SavedVariables", function()
    local storage = {}
    local store = newStore(storage)
    local goal = store:Create("CRAFT_ITEM", { itemID = 2996, quantity = 3 }, { now = 42 })
    store:Select(goal.id)
    assert_true(ns.Util.IsPlainData(storage), "storage must stay serializable")
    -- Simulate the client writing and reading the table back.
    local reloaded = H.Mock.deepcopy(storage)
    local store2 = newStore(reloaded)
    assert_eq(store2.dropped, 0)
    assert_eq(store2:Count(), 1)
    assert_eq(store2:GetSelected().target.itemID, 2996)
    assert_eq(store2:GetSelected().target.quantity, 3)
  end)

  it("stores per-item route overrides and validates them", function()
    local storage = {}
    local store = newStore(storage)
    local goal = store:Create("CRAFT_ITEM", { itemID = 4238, quantity = 1 }, { now = 42 })
    assert_true(store:SetRoute(goal.id, 2996, "buy"))
    assert_eq(goal.routes[2996], "buy")
    assert_true(store:SetRoute(goal.id, 2996, "craft"))
    assert_true(store:SetRoute(goal.id, 2996, nil))
    assert_nil(goal.routes, "an empty table is dropped")
    local ok, err = store:SetRoute(goal.id, 2996, "steal")
    assert_false(ok)
    assert_match(err, "route")
    assert_false(store:SetRoute(goal.id, "2996", "buy"))
    assert_false(store:SetRoute("nope", 2996, "buy"))
    assert_true(ns.Util.IsPlainData(storage))

    local bad = ns.GoalModel.New("CRAFT_ITEM", { itemID = 1, quantity = 1 })
    bad.routes = { [5] = "teleport" }
    local valid, reason = ns.GoalModel.Validate(bad)
    assert_false(valid)
    assert_match(reason, "route")
    bad.routes = { ["5"] = "buy" }
    assert_false(ns.GoalModel.Validate(bad))
    bad.routes = { [5] = "buy" }
    assert_true(ns.GoalModel.Validate(bad))
  end)

  it("switches goals between item types only", function()
    local storage = {}
    local store = newStore(storage)
    local goal = store:Create("CRAFT_ITEM", { itemID = 10411, quantity = 1 }, { now = 42 })
    assert_true(store:SetType(goal.id, "OBTAIN_ITEM"))
    assert_eq(goal.type, "OBTAIN_ITEM")
    assert_true(store:SetType(goal.id, "OBTAIN_ITEM"), "no-op is fine")
    local ok, err = store:SetType(goal.id, "COMPLETE_QUEST")
    assert_false(ok)
    assert_match(err, "different targets")
    assert_false((store:SetType(goal.id, "NOPE")))
    assert_false((store:SetType("missing", "CRAFT_ITEM")))
    assert_eq(store:FindByItem("OBTAIN_ITEM", 10411).id, goal.id)
  end)

end)
