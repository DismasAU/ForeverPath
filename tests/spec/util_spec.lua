local H = require("harness")

describe("Util", function()
  local ns
  before_each(function() ns = H.fresh() end)

  it("parses integers strictly", function()
    assert_eq(ns.Util.ParseInt("42"), 42)
    assert_eq(ns.Util.ParseInt(" 7 "), 7)
    assert_eq(ns.Util.ParseInt("-2"), -2)
    assert_eq(ns.Util.ParseInt(3), 3)
    assert_nil(ns.Util.ParseInt("4.5"))
    assert_nil(ns.Util.ParseInt(4.5))
    assert_nil(ns.Util.ParseInt("12abc"))
    assert_nil(ns.Util.ParseInt(""))
    assert_nil(ns.Util.ParseInt(nil))
  end)

  it("applies defaults without overwriting existing values", function()
    local target = { settings = { debug = true }, extra = "keep" }
    ns.Util.ApplyDefaults(target, { settings = { debug = false, includeBank = true }, window = { width = 10 } })
    assert_eq(target.settings.debug, true)
    assert_eq(target.settings.includeBank, true)
    assert_eq(target.window.width, 10)
    assert_eq(target.extra, "keep")
  end)

  it("formats relative time", function()
    assert_eq(ns.Util.FormatAgo(nil), "never")
    assert_eq(ns.Util.FormatAgo(1000, 1030), "just now")
    assert_eq(ns.Util.FormatAgo(1000, 1000 + 5 * 60), "5m ago")
    assert_eq(ns.Util.FormatAgo(1000, 1000 + 3 * 3600), "3h ago")
    assert_eq(ns.Util.FormatAgo(1000, 1000 + 2 * 86400), "2d ago")
  end)

  it("recognises plain serializable data", function()
    assert_true(ns.Util.IsPlainData({ a = 1, b = { c = "x", d = true } }))
    assert_false(ns.Util.IsPlainData({ f = function() end }))
    local cyclic = {}
    cyclic.self = cyclic
    assert_false(ns.Util.IsPlainData(cyclic))
    assert_false(ns.Util.IsPlainData(setmetatable({}, {})))
  end)

  it("deep copies tables", function()
    local original = { nested = { value = 1 } }
    local copy = ns.Util.DeepCopy(original)
    copy.nested.value = 2
    assert_eq(original.nested.value, 1)
  end)
end)
