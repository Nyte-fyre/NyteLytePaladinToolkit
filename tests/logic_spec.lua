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

-- Config helpers
local target = { a = 1, list = { "x" }, sub = { keep = false } }
C.FillDefaults(target, { a = 2, b = 3, list = { "x", "y", "z" }, sub = { keep = true, add = 1 } })
assert(target.a == 1 and target.b == 3, "fill keeps existing, adds missing")
assert(#target.list == 1, "lists are not merged")
assert(target.sub.keep == false and target.sub.add == 1, "nested fill")
local db = C.Migrate({})
assert(db.version == 1 and db.profiles and db.profileKeys, "migrate from nothing")

LOGIC_OK = true
