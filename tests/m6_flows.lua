-- Batch 5/6/7/9: exceptions, tank-aware suggest, coverage, duplicate Aura.
local P = NyteLytePaladinToolkit
local BM, BS = P.modules.BlessingManager, P.modules.BuffSentinel
local B = P.Blessings
local function slash(msg)
	SlashCmdList.NYTELYTEPALADINTOOLKIT(msg)
end
local function settle()
	for _ = 1, 3 do
		MOCK.runTimers()
	end
end
local ME = "Player-1-TESTER"
local TANK, ROGUE2 = "Player-1-BEEFY", "Player-1-STABBY"

slash("holy")
P.profile.blessing.assignments = {}
MOCK.inGroup = true
MOCK.party = {
	{ unit = "party1", name = "Beefy", class = "WARRIOR", guid = TANK, role = "TANK" },
	{ unit = "party2", name = "Stabby", class = "ROGUE", guid = ROGUE2 },
}
MOCK.fire("GROUP_ROSTER_UPDATE")
settle()
assert(P.Roster:Find(TANK).role == "TANK", "roster knows the tank")
assert(#BM:Tanks() == 1, "one tank")

-- 7. Exceptions: Stabby gets nothing from us, the tank gets Might.
assert(BM:SetOverride(ME, ROGUE2, B.NONE))
assert(B.AssignedFor(BM:Effective(), ME, "ROGUE", ROGUE2) == nil, "Stabby excluded")
MOCK.sent = {}
assert(BM:SetOverride(ME, TANK, "BLESSING_MIGHT"))
MOCK.tick(40)
local sent
for _, m in ipairs(MOCK.sent) do
	if m.text:find("^ROW|") then
		sent = m.text
	end
end
assert(sent and sent:find("1-BEEFY=MI", 1, true) and sent:find("1-STABBY=NO", 1, true), "exceptions synced: " .. tostring(sent))
-- Editing a class cell keeps the exceptions.
BM:SetAssignment(ME, "MAGE", "BLESSING_WISDOM")
assert(BM:Effective()[ME].overrides[TANK] == "BLESSING_MIGHT", "exceptions survive class edits")

if not MOCK_NO_AURAS then
	-- The buff button honors exceptions: Stabby (NONE) is never targeted.
	P.Roster:Scan()
	local button = _G.NyteLytePaladinToolkitBuffButton
	assert(button:GetAttribute("unit") ~= "party2", "excluded player never targeted")
	MOCK.unitAuras.party1 = {}
	P.Roster:Scan()
	local unit = button:GetAttribute("unit")
	assert(unit == "party1" or unit == "player", "someone who needs it is targeted: " .. tostring(unit))
end

-- Clearing an exception.
assert(BM:SetOverride(ME, ROGUE2, nil))
assert(BM:Effective()[ME].overrides[ROGUE2] == nil, "exception cleared")

-- The exceptions cap.
for i = 1, B.MAX_OVERRIDES do
	BM:SetOverride(ME, string.format("Player-9-%08X", i), "BLESSING_MIGHT")
end
local count = 0
for _ in pairs(BM:Effective()[ME].overrides) do
	count = count + 1
end
assert(count == B.MAX_OVERRIDES, "capped at " .. B.MAX_OVERRIDES .. ", got " .. count)
P.profile.blessing.assignments = {}

-- 6. Tank-aware auto-suggest.
BM:ApplySuggestion()
local row = BM:Effective()[ME]
assert(row.classes.WARRIOR ~= "BLESSING_SALVATION" or (row.overrides and row.overrides[TANK]),
	"the tank never keeps Salvation")

-- Grid: right-click opens exceptions; the popup refreshes.
slash("bless")
P.BlessingGrid:Refresh()
P.BlessingGrid.OpenExceptions(ME, "ROGUE")
P.BlessingGrid:Refresh()
assert(_G.NyteLytePaladinToolkitExceptions, "exceptions window built")
-- Clicking the rogue's cell in the popup cycles: default -> first Blessing -> ... -> None -> default.
local prow = P.BlessingGrid.popupRows[1]
assert(prow.member and prow.member.guid == ROGUE2, "popup lists Stabby: " .. tostring(prow.member and prow.member.name))
local click = prow.cell:GetScript("OnClick")
click(prow.cell, "LeftButton")
local first = BM:Effective()[ME].overrides[ROGUE2]
assert(first and first ~= B.NONE, "first click sets a Blessing exception: " .. tostring(first))
MOCK.ctrl = true
click(prow.cell, "LeftButton")
MOCK.ctrl = false
assert(BM:Effective()[ME].overrides[ROGUE2] == nil, "ctrl-click steps back to the class default")
click(prow.cell, "RightButton")
assert(BM:Effective()[ME].overrides[ROGUE2] == B.NONE, "right-click from default goes to None")
MOCK.shift = true
click(prow.cell, "LeftButton")
MOCK.shift = false
assert(BM:Effective()[ME].overrides[ROGUE2] == nil, "shift-click clears")
P.BlessingGrid:Hide()

-- 5. Coverage: the rogue has nothing from anyone.
if not MOCK_NO_AURAS then
	MOCK.unitAuras.party2 = {}
	P.Roster:Scan()
	local gaps = BM:CoverageText()
	assert(gaps:find("Stabby", 1, true), "coverage lists Stabby: " .. gaps)
	local n = #MOCK.printed
	slash("buffs")
	local found = false
	for i = n + 1, #MOCK.printed do
		found = found or MOCK.printed[i]:find("group missing", 1, true) ~= nil
	end
	assert(found, "/ptk buffs includes group coverage")
end

-- 9. Duplicate Aura: another paladin's Devotion Aura on us.
if not MOCK_NO_AURAS then
	local devotion
	for _, a in ipairs(MOCK.auras) do
		if a.spellId == 465 then
			devotion = a
		end
	end
	devotion.fromOther = true -- another paladin's (stronger) Devotion Aura
	MOCK.fire("UNIT_AURA", "player", {})
	settle()
	local dup
	for _, r in ipairs(BS:Evaluate()) do
		if r.id == "auraDup" then
			dup = r
		end
	end
	assert(dup and dup.status == "duplicate", "duplicate Aura detected")
	slash("check")
	devotion.fromOther = nil
	MOCK.fire("UNIT_AURA", "player", {})
	settle()
	for _, r in ipairs(BS:Evaluate()) do
		assert(r.id ~= "auraDup", "no duplicate once it's ours again")
	end
end

-- Yellow "not as assigned": wrong Aura, or your Blessing cast by someone else.
if not MOCK_NO_AURAS then
	local function status(id)
		for _, r in ipairs(BS:Evaluate()) do
			if r.id == id then
				return r.status, r
			end
		end
	end
	P.profile.blessing.assignments = {}
	assert(status("aura") == "ok", "no row: running any Aura is fine")
	P.profile.blessing.assignments[ME] = { classes = { PALADIN = "BLESSING_MIGHT" }, aura = "AURA_RETRIBUTION",
		seq = 1, ts = 1, by = ME }
	local st, r = status("aura")
	assert(st == "wrong" and r.detail:find("assigned: Retribution Aura", 1, true), "Devotion active, Retribution assigned: yellow")
	-- Might on us from another paladin: yellow; from us: fine; missing: red.
	local might = { name = "Blessing of Might", spellId = 19740, duration = 3600, expirationTime = GetTime() + 3000,
		fromOther = true }
	table.insert(MOCK.auras, might)
	MOCK.fire("UNIT_AURA", "player", {})
	settle()
	st, r = status("blessing")
	assert(st == "wrong" and r.detail:find("another paladin", 1, true), "Might from someone else: yellow")
	-- An NPC/object buff never counts as a paladin's Blessing; our own copy wins if both exist.
	table.insert(MOCK.auras, { name = "Blessing of Might", spellId = 19740, duration = 3600,
		expirationTime = GetTime() + 3000 })
	MOCK.fire("UNIT_AURA", "player", {})
	settle()
	assert(status("blessing") == "ok", "our own copy alongside theirs: fine")
	table.remove(MOCK.auras)
	MOCK.fire("UNIT_AURA", "player", {})
	settle()
	might.fromOther = nil
	MOCK.fire("UNIT_AURA", "player", {})
	settle()
	assert(status("blessing") == "ok", "our own Might: fine")
	table.remove(MOCK.auras)
	MOCK.fire("UNIT_AURA", "player", {})
	settle()
	assert(status("blessing") == "missing", "no Might: red")
	BS:Render()
	slash("check")
	P.profile.blessing.assignments = {}
end

MOCK.unitAuras = {}
MOCK.inGroup = false
MOCK.party = {}
MOCK.fire("GROUP_ROSTER_UPDATE")
settle()
P.profile.blessing.assignments = {}
M6_OK = true
