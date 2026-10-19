local H = require("harness")
local Mock = H.Mock

local LINEN, THREAD, WOOLEN_BOLT = 2589, 2320, 2964
local STORM = 77777 -- a quest nothing ships facts for

describe("Codec", function()
  local ns, Codec
  before_each(function()
    ns = H.fresh()
    Codec = ns.Codec
  end)

  it("round-trips plain data without executing anything", function()
    local value = {
      1, 2, 3, -7, 0, 1.5, -0.25, 2 ^ 40, true, false,
      name = "Mangy Wolf", odd = "pipes | colons : semis ; newline \n and \0 bytes {}",
      nested = { deep = { deeper = { "x" } }, [42] = "answer" },
      empty = {},
    }
    local text = assert(Codec.Serialize(value))
    local back = Codec.Deserialize(text)
    assert_eq(back[1], 1)
    assert_eq(back[4], -7)
    assert_eq(back[6], 1.5)
    assert_eq(back[7], -0.25)
    assert_eq(back[8], 2 ^ 40)
    assert_true(back[9])
    assert_false(back[10])
    assert_eq(back.name, "Mangy Wolf")
    assert_eq(back.odd, value.odd)
    assert_eq(back.nested.deep.deeper[1], "x")
    assert_eq(back.nested[42], "answer")
    assert_eq(next(back.empty), nil)
    assert_eq(Codec.Serialize(value), text, "stable output")
    -- Refusals.
    assert_nil((Codec.Serialize({ f = function() end })))
    assert_nil((Codec.Serialize({ n = 0 / 0 })))
    for _, bad in ipairs({ "", "{", "s5:abc", "i12", "{i1;", "q", "{T}", "i1;i2;", "s-1:" }) do
      local v, err = Codec.Deserialize(bad)
      assert_nil(v, "rejects " .. bad)
      assert_not_nil(err)
    end
    local bomb = string.rep("{i1;", 40) .. "z" .. string.rep("}", 40)
    assert_nil((Codec.Deserialize(bomb)), "nesting is limited")
    -- Base64 over every byte value.
    local bytes = {}
    for i = 0, 255 do bytes[#bytes + 1] = string.char(i) end
    local all = table.concat(bytes)
    for cut = 0, 2 do
      local s = all:sub(1, #all - cut)
      assert_eq(Codec.Base64Decode(Codec.Base64Encode(s)), s)
    end
    assert_eq(Codec.Base64Encode("Man"), "TWFu")
    assert_eq(Codec.Base64Encode("Ma"), "TWE=")
    assert_nil((Codec.Base64Decode("TWF")))
    assert_nil((Codec.Base64Decode("TW!u")))
    -- Paste-safe strings: base64, or the client's compression when present.
    local packed = Codec.Pack({ a = 1 })
    assert_match(packed, "^FPX1:b:[A-Za-z0-9+/=]+$")
    assert_eq(Codec.Unpack(packed).a, 1)
    assert_eq(Codec.Unpack("  " .. packed .. "\n").a, 1, "whitespace around a paste is fine")
    _G.C_EncodingUtil = {
      CompressString = function(s) return "C" .. s end, DecompressString = function(s) return s:sub(2) end,
      EncodeBase64 = function(s) return Codec.Base64Encode(s) end, DecodeBase64 = function(s) return Codec.Base64Decode(s) end,
    }
    packed = Codec.Pack({ a = 2 })
    assert_match(packed, "^FPX1:z:")
    assert_eq(Codec.Unpack(packed).a, 2)
    _G.C_EncodingUtil = nil
    local _, err = Codec.Unpack(packed)
    assert_match(err, "cannot decompress")
    assert_match(select(2, Codec.Unpack("hello")), "not a ForeverPath export")
    assert_match(select(2, Codec.Unpack("FPX1:b:@@@@")), "damaged export")
  end)
end)

describe("Sharing learned data", function()
  it("exports one account's Forever data and imports it on another, once", function()
    -- Account A learns loot, a quest giver, a merchant and a trainer.
    local ns = H.fresh()
    H.login(ns)
    ns.db.shareToken = "aaaa0000aaaa0000"
    Mock.character.name = "Thandrel"
    Mock.AddItem(LINEN, { name = "Linen Cloth" })
    Mock.AddItem(THREAD, { name = "Coarse Thread" })
    local wolf = Mock.CreatureGUID(525, 1)
    Mock.targetGUID, Mock.targetName = wolf, "Mangy Wolf"
    Mock.OpenLoot({ { itemID = LINEN, quantity = 2, sources = { wolf, 2 } } })
    Mock.CloseLoot()
    Mock.position = { mapID = 1441, x = 0.535, y = 0.426 }
    Mock.zone = "Thousand Needles"
    Mock.OfferQuest(STORM, "Prate Cloudseer")
    Mock.CloseQuestWindow()
    Mock.zone = "Durotar"
    Mock.OpenMerchant("Tharynn Bouden", { { THREAD, 8 } })
    Mock.RunTimers()
    Mock.CloseMerchant()
    Mock.OpenTrainer("Georgio Bolero", { { name = "Tailoring", type = "header" },
      { spellID = WOOLEN_BOLT, name = "Bolt of Woolen Cloth", type = "available", skill = "Tailoring", rank = 75, cost = 500 } })
    Mock.RunTimers()
    local text, counts = ns.Share.Export()
    assert_match(text, "^FPX1:b:")
    assert_eq(counts.lootSeen, 1)
    assert_eq(counts.questFacts, 1)
    assert_eq(counts.vendors, 1)
    assert_eq(counts.trainers, 1)
    -- The window shows it ready to copy.
    local shown = ns.UI.ShareFrame.ShowExport()
    assert_match(shown, "^FPX1:b:")
    assert_match(ns.UI.ShareFrame.frame.hint:GetText(), "1 loot sources, 1 quests, 1 vendor items, 1 trainer recipes")
    Mock.RunSlash("export")
    assert_output("Export ready %(1 loot sources")
    -- An import of your own export is refused.
    local ok, message = ns.Share.Import(text)
    assert_false(ok)
    assert_match(message, "came from this account")

    -- Account B has none of it.
    ns = H.fresh()
    H.login(ns)
    ns.db.shareToken = "bbbb0000bbbb0000"
    Mock.AddItem(LINEN, { name = "Linen Cloth" })
    Mock.AddItem(THREAD, { name = "Coarse Thread" })
    assert_eq(#ns.LootLearner.ItemHints(LINEN), 0)
    assert_nil(ns.QuestProvider.Giver(STORM))
    assert_eq(#ns.VendorProvider.VendorsFor(THREAD), 0)
    assert_nil(ns.TrainerProvider.Requirement(WOOLEN_BOLT))
    ok, message = ns.Share.Import(text)
    assert_true(ok, message)
    assert_eq(message, "Imported Thandrel-Stormhold's data: 1 loot sources, 1 quests, 1 vendor items, 1 trainer recipes.")
    local hint = ns.LootLearner.ItemHints(LINEN)[1]
    assert_eq(hint.label, "Dropped by Mangy Wolf")
    assert_eq(hint.detail, "Durotar - seen 1 time in 1 loot on Forever (with shared data)")
    assert_true(hint.shared)
    assert_eq(ns.QuestProvider.Giver(STORM).name, "Prate Cloudseer")
    assert_eq(ns.QuestProvider.Giver(STORM).mapID, 1441)
    local vendors = ns.VendorProvider.VendorsFor(THREAD)
    assert_eq(vendors[1].name, "Tharynn Bouden")
    assert_true(vendors[1].shared)
    assert_eq(ns.VendorProvider.GetPrice(THREAD).copper, 8)
    assert_eq(ns.TrainerProvider.Requirement(WOOLEN_BOLT).rank, 75)
    assert_eq(ns.Data.Recipes.Get(WOOLEN_BOLT).skill.min, 75, "shared trainer data reaches the catalogue")
    -- Importing again replaces, never doubles.
    ok, message = ns.Share.Import(text)
    assert_true(ok)
    assert_match(message, "^Updated Thandrel%-Stormhold's data")
    assert_eq(ns.LootLearner.ItemHints(LINEN)[1].detail, "Durotar - seen 1 time in 1 loot on Forever (with shared data)")
    -- B's own loot adds to the shared counts; own data comes first everywhere.
    local wolf2 = Mock.CreatureGUID(525, 2)
    Mock.targetGUID, Mock.targetName = wolf2, "Mangy Wolf"
    Mock.OpenLoot({ { itemID = THREAD, quantity = 1, sources = { wolf2, 1 } } })
    Mock.CloseLoot()
    assert_eq(ns.LootLearner.ItemHints(LINEN)[1].detail, "Durotar - seen 1 time in 2 loots on Forever (with shared data)")
    Mock.OpenMerchant("Other Vendor", { { THREAD, 12 } })
    Mock.RunTimers()
    Mock.CloseMerchant()
    vendors = ns.VendorProvider.VendorsFor(THREAD)
    assert_eq(#vendors, 2)
    -- Listing and removing.
    assert_match(ns.Share.Status(), "^Shared data: imported from 1 player %(Thandrel%-Stormhold%)%.$")
    Mock.RunSlash("shared")
    assert_output("  1%. Thandrel%-Stormhold %- 1 loot sources")
    Mock.RunSlash("shared remove 1")
    assert_output("Removed Thandrel%-Stormhold's shared data%.")
    assert_eq(#ns.Share.List(), 0)
    assert_eq(ns.LootLearner.ItemHints(LINEN)[1] and ns.LootLearner.ItemHints(LINEN)[1].label or "none", "none")
    assert_nil(ns.TrainerProvider.Requirement(WOOLEN_BOLT))
    -- The import window.
    ns.UI.ShareFrame.ShowImport()
    local frame = ns.UI.ShareFrame.frame
    assert_true(frame.import:IsShown())
    frame.box:SetText("not an export")
    frame.import:Click()
    assert_match(frame.status:GetText(), "not a ForeverPath export")
    frame.box:SetText(text)
    frame.import:Click()
    assert_match(frame.status:GetText(), "Imported Thandrel%-Stormhold's data")
    assert_eq(frame.box:GetText(), "")
    assert_eq(#ns.Share.List(), 1)
    Mock.RunSlash("import " .. text)
    assert_output("Updated Thandrel%-Stormhold's data")
    assert_match(ns.Share.Status(), "1 player")
    -- Damaged or foreign data is refused.
    ok, message = ns.Share.Import(ns.Codec.Pack({ v = 99, author = "x" }))
    assert_false(ok)
    assert_match(message, "not a ForeverPath export of this version")
    ok, message = ns.Share.Import(ns.Codec.Pack({ v = 1, author = "x", lootSeen = "nope" }))
    assert_false(ok)
    assert_match(message, "damaged export %(lootSeen%)")
  end)
end)
