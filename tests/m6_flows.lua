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
-- Frame sizes: slash command, clamping, mouse wheel, reset.
local F = P.Frames
slash("scale button 150")
assert(math.abs(F:GetScale("BlessingManager") - 1.5) < 1e-9, "button at 150%")
slash("scale seal 500")
assert(F:GetScale("SealTracker") == P.Config.SCALE_MAX, "clamped to 200%")
slash("scale all 10%")
for _, module in ipairs(P.Presets.MODULES) do
	assert(F:GetScale(module) == P.Config.SCALE_MIN, "clamped to 50%: " .. module)
end
slash("scale all 100")
slash("scale")
slash("scale nonsense 120")
assert(F:GetScale("TankKit") == 1, "unknown frame name changes nothing")
F:SetLocked(false)
local anchor = F:GetAnchor("BuffSentinel")
anchor:GetScript("OnMouseWheel")(anchor, 1)
assert(math.abs(F:GetScale("BuffSentinel") - 1.05) < 1e-9, "wheel up: +5%")
F:SetLocked(true)
anchor:GetScript("OnMouseWheel")(anchor, 1)
assert(math.abs(F:GetScale("BuffSentinel") - 1.05) < 1e-9, "locked: wheel does nothing")
-- A bad imported value never reaches the frame.
P.Config:GetLayout(P.SpecProfile:GetSpec(), "CooldownHUD").scale = 40
F:ApplyLayout("CooldownHUD")
assert(F:GetScale("CooldownHUD") == P.Config.SCALE_MAX, "bad saved scale clamped")
slash("scale reset")
assert(F:GetScale("BuffSentinel") == F:DefaultScale("BuffSentinel"), "sizes reset")
P.Settings:Refresh()

-- Reordering the cooldown bar: /ptk cd move, and click-to-reorder while unlocked.
local CD = P.modules.CooldownHUD
local spec = P.SpecProfile:GetSpec()
local function list()
	return P.profile.cooldownLists[spec]
end
local function iconIds()
	local out = {}
	for _, icon in ipairs(CD:GetIcons()) do
		out[#out + 1] = icon.spellID
	end
	return out
end
local cdSettings = P.Config:GetModuleSettings("CooldownHUD")
cdSettings.showUnknown = true -- show every list entry as an icon
P:Fire("PK_SETTINGS_CHANGED")
local original = P.Config.DeepCopy(list())
local n = #list()
assert(n >= 3 and CD:IconCount() >= 2, "need icons to reorder")
slash("cd move Lay on Hands first")
assert(list()[1] == "LAY_ON_HANDS", "Lay on Hands first: " .. tostring(list()[1]))
assert(#list() == n, "nothing lost")
slash("cd move lay on hands last")
assert(list()[n] == "LAY_ON_HANDS", "Lay on Hands last")
slash("cd move Lay on Hands 2")
assert(list()[2] == "LAY_ON_HANDS", "Lay on Hands second")
slash("cd move Nonexistent Spell 1")
slash("cd move Lay on Hands somewhere")
assert(list()[2] == "LAY_ON_HANDS", "bad input changes nothing")
slash("cd")

-- Click mode: locked does nothing; unlocked pick + drop moves it.
local icons = CD:GetIcons()
local first, second = icons[1], icons[2]
local before = iconIds()
first:GetScript("OnMouseDown")(first)
first:GetScript("OnMouseUp")(first, "LeftButton")
assert(iconIds()[1] == before[1], "locked: clicks don't reorder")
F:SetLocked(false)
icons = CD:GetIcons()
first, second = icons[1], icons[2]
local moved = first.spellID
first:GetScript("OnMouseDown")(first)
first:GetScript("OnMouseUp")(first, "LeftButton") -- pick up
second:GetScript("OnMouseDown")(second)
second:GetScript("OnMouseUp")(second, "LeftButton") -- drop on the second
assert(iconIds()[2] == moved and iconIds()[1] ~= moved, "first icon moved to second place")
-- Right-click cancels a pick-up.
icons = CD:GetIcons()
icons[1]:GetScript("OnMouseUp")(icons[1], "LeftButton")
icons[2]:GetScript("OnMouseUp")(icons[2], "RightButton")
local after = iconIds()
icons = CD:GetIcons()
icons[2]:GetScript("OnMouseUp")(icons[2], "LeftButton")
icons[2]:GetScript("OnMouseUp")(icons[2], "LeftButton") -- same icon again: cancel
assert(table.concat(iconIds(), ",") == table.concat(after, ","), "cancel leaves the order alone")
-- A drag is not a click.
icons = CD:GetIcons()
icons[1]:GetScript("OnMouseDown")(icons[1])
icons[1]:GetScript("OnDragStart")(icons[1])
icons[1]:GetScript("OnMouseUp")(icons[1], "LeftButton")
icons[1]:GetScript("OnDragStop")(icons[1])
icons[2]:GetScript("OnMouseDown")(icons[2])
icons[2]:GetScript("OnMouseUp")(icons[2], "LeftButton")
assert(table.concat(iconIds(), ",") ~= "" and CD:IconCount() == #after, "drag didn't pick anything up")
F:SetLocked(true)
P.profile.cooldownLists[spec] = original
cdSettings.showUnknown = false
P:Fire("PK_SETTINGS_CHANGED")

M6_OK = true
