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
