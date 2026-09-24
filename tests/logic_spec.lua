-- Pure-logic unit tests (Serializer, SpecDecision, Config helpers).
local P = NyteLytePaladinToolkit
local S, D, C = P.Serializer, P.SpecDecision, P.Config

local function deepEqual(a, b)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- Serializer round trip
local sample = {
	str = "pipes | and \"quotes\" and \n newlines and ünïcode",
	empty = "",
	n = { 0, -1, 3.25, 1e10, -0.000123, 123456789012 },
	flags = { yes = true, no = false },
	nested = { a = { b = { c = { "deep" } } } },
	[7] = "numeric key",
}
local encoded = assert(S.Encode(sample))
local decoded = assert(S.Decode(encoded))
assert(deepEqual(sample, decoded), "serializer round trip")
assert(S.Encode({ f = function() end }) == nil, "functions rejected")
local cyc = {}
cyc.self = cyc
assert(S.Encode(cyc) == nil, "cycles rejected")
assert(S.Encode({ x = 0 / 0 }) == nil, "NaN rejected")

-- Base64 at every padding length
for len = 0, 9 do
	local str = string.sub("abcdefghi", 1, len) .. string.char(0, 255)
	assert(S.Base64Decode(S.Base64Encode(str)) == str, "base64 length " .. len)
end
assert(S.Base64Decode("ab$=") == nil, "bad base64 char")
assert(S.Base64Decode("abc") == nil, "bad base64 length")

-- Decode rejections
assert(S.Decode(nil) == nil)
assert(S.Decode("NLPT:9:00000000:QUJD") == nil, "future version rejected")
local okPayload = "NLPT:1:" .. S.Checksum("n1;") .. ":" .. S.Base64Encode("n1;")
assert(select(2, S.Decode(okPayload)):find("profile"), "non-table payload rejected")
local trailing = "{}x"
assert(S.Decode("NLPT:1:" .. S.Checksum(trailing) .. ":" .. S.Base64Encode(trailing)) == nil, "extra data rejected")
local badStr = "{s99:ab}"
assert(S.Decode("NLPT:1:" .. S.Checksum(badStr) .. ":" .. S.Base64Encode(badStr)) == nil, "bad string length rejected")

-- SpecDecision
local r = D.Decide("auto", { talentPoints = { holy = 11, prot = 0, ret = 2 } })
assert(r.spec == "holy" and r.confidence == "high" and r.method == "talent points")
r = D.Decide("auto", { talentPoints = { holy = 3, prot = 2, ret = 0 } })
assert(r.spec == "holy" and r.confidence == "low")
r = D.Decide("auto", { talentPoints = { holy = 5, prot = 5 }, knownSpecSpells = { ret = 1 } })
assert(r.spec == "ret" and r.method == "known spells", "tie falls through to known spells")
r = D.Decide("auto", { knownSpecSpells = { holy = 1, prot = 1 } })
assert(r.spec == "holy" and r.confidence == "none", "tie + nothing else = fallback")
r = D.Decide("prot", { talentPoints = { ret = 31 } })
assert(r.spec == "prot" and r.confidence == "manual" and r.detected.spec == "ret", "manual wins, detection kept")
r = D.Decide("bogus", {})
assert(r.mode == "auto", "invalid mode treated as auto")
assert(D.NextMode("auto") == "holy" and D.NextMode("ret") == "auto" and D.NextMode("x") == "auto")

assert(D.SpecForTalentX(1620) == "holy" and D.SpecForTalentX(5620) == "prot" and D.SpecForTalentX(10880) == "ret")
assert(D.SpecForTalentX(nil) == nil, "no x, no tree")

-- Config helpers
local target = { a = 1, list = { "x" }, sub = { keep = false } }
C.FillDefaults(target, { a = 2, b = 3, list = { "x", "y", "z" }, sub = { keep = true, add = 1 } })
assert(target.a == 1 and target.b == 3, "fill keeps existing, adds missing")
assert(#target.list == 1, "lists are not merged")
assert(target.sub.keep == false and target.sub.add == 1, "nested fill")
local db = C.Migrate({})
assert(db.version == 4 and db.profiles and db.profileKeys, "migrate from nothing")
local oldHoly = C.DeepCopy(P.Presets.previousCooldownLists.holy[1])
db = C.Migrate({ version = 1, profileKeys = {}, profiles = {
	untouched = { cooldownLists = { holy = oldHoly } },
	edited = { cooldownLists = { holy = { "HOLY_SHOCK" } } },
} })
assert(db.profiles.untouched.cooldownLists.holy[7] == "HAMMER_OF_JUSTICE", "untouched default list upgraded")
assert(#db.profiles.edited.cooldownLists.holy == 1, "edited list left alone")

-- Blessings: auto-suggest
local BL = P.Blessings
local set = function(...)
	local t = {}
	for _, k in ipairs({ ... }) do
		t[k] = true
	end
	return t
end
local sug = BL.Suggest({
	{ name = "Bee", blessings = set("BLESSING_MIGHT", "BLESSING_WISDOM"), auras = set("AURA_DEVOTION") },
	{ name = "Ay", blessings = set("BLESSING_KINGS", "BLESSING_MIGHT", "BLESSING_WISDOM"),
		auras = set("AURA_DEVOTION", "AURA_RETRIBUTION") },
})
assert(sug.Ay.classes.WARRIOR == "BLESSING_KINGS" and sug.Bee.classes.WARRIOR == "BLESSING_MIGHT", "warriors: Kings + Might")
assert(sug.Ay.classes.MAGE == "BLESSING_WISDOM" and sug.Bee.classes.MAGE == nil, "mages: Wisdom, never Might")
assert(sug.Ay.classes.ROGUE == "BLESSING_MIGHT" and sug.Bee.classes.ROGUE == nil, "rogues: Might; Bee has no Kings")
for _, class in ipairs(BL.CLASSES) do
	assert(sug.Ay.classes[class] == nil or sug.Ay.classes[class] ~= sug.Bee.classes[class], "no doubled blessing on " .. class)
end
assert(sug.Ay.aura == "AURA_DEVOTION" and sug.Bee.aura == nil, "distinct auras (Bee only knows Devotion)")
local unknown = BL.Suggest({ { name = "NoAddon" } })
assert(unknown.NoAddon.classes.WARRIOR == "BLESSING_MIGHT", "no-addon paladins assumed to know Might/Wisdom")

-- Blessings: message round trip and validation
local rowMsg = BL.Decode(BL.EncodeRow("Ay", { classes = sug.Ay.classes, aura = "AURA_RETRIBUTION", seq = 4, ts = 99 }))
assert(rowMsg.type == "ROW" and rowMsg.paladin == "Ay" and rowMsg.seq == 4 and rowMsg.ts == 99, "row header")
assert(rowMsg.aura == "AURA_RETRIBUTION" and rowMsg.classes.WARRIOR == "BLESSING_KINGS", "row body")
local hello = BL.Decode(BL.EncodeHello("0.4.0|x", set("BLESSING_KINGS"), set("AURA_DEVOTION")))
assert(hello.type == "HELLO" and hello.blessings.BLESSING_KINGS and hello.auras.AURA_DEVOTION, "hello")
assert(#BL.EncodeRow(string.rep("N", 48), { classes = sug.Ay.classes, aura = "AURA_DEVOTION", seq = 99999, ts = 1790235093 }) < 255,
	"rows fit in one addon message")
assert(BL.Decode("ROW|1|2|ba,d||") == nil and BL.Decode("ROW|1|2|a=b||") == nil, "names with , or = rejected")
assert(BL.Decode("ROW|1|2|" .. string.rep("x", 60) .. "||") == nil, "overlong names rejected")
assert(BL.Decode("NOPE|1") == nil and BL.Decode(nil) == nil, "unknown/nil rejected")
local junk = BL.Decode("ROW|1|2|Ay|ZZ|WA=ZZ,XX=KI,MA=WI")
assert(junk and junk.aura == nil and junk.classes.WARRIOR == nil and junk.classes.MAGE == "BLESSING_WISDOM", "unknown codes dropped")

-- Blessings: conflict rules
local A = {}
assert(BL.ApplyRow(A, "Ay", { classes = {}, seq = 1, ts = 10 }, { sender = "Ay" }))
assert(not BL.ApplyRow(A, "Ay", { classes = {}, seq = 2, ts = 10 }, { sender = "Bee" }), "no editing others without lead")
assert(BL.ApplyRow(A, "Ay", { classes = {}, seq = 2, ts = 5 }, { sender = "Lead", senderIsLeader = true }), "leader may edit")
assert(not BL.ApplyRow(A, "Ay", { classes = {}, seq = 1, ts = 50 }, { sender = "Ay" }), "lower seq loses")
assert(not BL.ApplyRow(A, "Ay", { classes = {}, seq = 2, ts = 4 }, { sender = "Ay" }), "same seq, older ts loses")
assert(not BL.ApplyRow(A, "Ay", { classes = {}, seq = 2, ts = 5 }, { sender = "Ay" }), "tie: leader's version wins")

-- Blessings: next missing
local members = {
	{ unit = "party1", name = "Dead", class = "ROGUE", usable = false, buffs = {} },
	{ unit = "party2", name = "Blind", class = "ROGUE", usable = true, buffs = nil },
	{ unit = "party3", name = "Mage", class = "MAGE", usable = true, buffs = {} },
	{ unit = "party4", name = "Rogue", class = "ROGUE", usable = true, buffs = {} },
}
local assign = { Me = { classes = { ROGUE = "BLESSING_MIGHT" } } }
local who, key = BL.NextMissing(assign, "Me", members)
assert(who.name == "Rogue" and key == "BLESSING_MIGHT", "skips dead, unreadable and unassigned")
assert(BL.CountMissing(assign, "Me", members) == 2, "count includes the dead rogue")

LOGIC_OK = true
