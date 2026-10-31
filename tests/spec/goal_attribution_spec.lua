local H = require("harness")

-- Domain/GoalAttribution over hand-made data: no providers involved.
describe("GoalAttribution", function()
  local ns, GA
  before_each(function()
    ns = H.fresh()
    GA = ns.GoalAttribution
  end)

  local function itemGoal(id, itemID, goalType)
    return { id = id, type = goalType or "OBTAIN_ITEM", target = { itemID = itemID, quantity = 1 } }
  end

  it("places item goals on the first free slot their item fits, in priority order", function()
    local ring1, ring2, ring3 = itemGoal("a", 1), itemGoal("b", 2), itemGoal("c", 3)
    local helm, cloth = itemGoal("d", 4), itemGoal("e", 5)
    local slotsOf = { [1] = { "Finger1", "Finger2" }, [2] = { "Finger1", "Finger2" }, [3] = { "Finger1", "Finger2" }, [4] = { "Head" }, [5] = {} }
    local slots, tracked = GA.PlaceOnSlots({ ring1, ring2, ring3, helm, cloth }, function(itemID) return slotsOf[itemID] end)
    assert_eq(slots.Finger1, ring1)
    assert_eq(slots.Finger2, ring2)
    assert_eq(slots.Head, helm)
    assert_eq(tracked, 4, "the third ring is gear without a free slot; cloth is not gear")
  end)

  it("maps quests to the goals they feed and groups the board by goal", function()
    local QUEST = 100
    local goal = itemGoal("g", 7)
    local view = { tree = { summary = { missingLeaves = { { itemID = 7, count = 2 } } } } }
    local entry = { id = QUEST, name = "A Quest", level = 12, instance = "Barrens" }
    local feeds = GA.QuestFeeds({ { goal = goal, view = view, name = "Get the item" } }, {
      questsRewarding = function(itemID) return itemID == 7 and { entry } or {} end,
      reputationQuests = function() return {} end,
    })
    assert_eq(feeds[QUEST].goals[1].count, 2)
    local open = { completed = false }
    local board = GA.QuestBoard("goal", false, {
      quests = { entry, { id = 200, name = "Unrelated", level = 5, instance = "Barrens" } },
      logEntries = {}, feeds = feeds, questGoals = {},
      nameOf = function(g) return g.id end, state = function() return open end,
      stateLabel = function() return "Available", "partial", "available" end,
      questName = function(id) return "Quest " .. id end, get = function() return nil end,
    })
    assert_eq(#board.groups, 1, "only quests that serve a goal")
    assert_eq(board.groups[1].label, "Get the item")
    assert_eq(board.groups[1].rows[1].stateKey, "available")
    assert_eq(board.feedCount, 1)
    assert_eq(board.total, 1)
  end)
end)
