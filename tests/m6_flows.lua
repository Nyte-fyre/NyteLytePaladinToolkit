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
-- Two rows from 8 icons: 4+4, 5+4, 5+5, 6+5; one row below that or when off.
assert(cdSettings.twoRows == true, "two rows on by default")
for count, want in pairs({ [7] = 12, [8] = 4, [9] = 5, [10] = 5, [11] = 6 }) do
	assert(CD.IconsPerRow(cdSettings, count) == want, count .. " icons: " .. want .. " per row")
end
cdSettings.twoRows = false
assert(CD.IconsPerRow(cdSettings, 11) == 12, "off: one row")
cdSettings.twoRows = true
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

-- Oath of Light: tracked from your casts and confirmed by group scans.
local OATH_ID = 900200
table.insert(MOCK.book, { name = "Oath of Light", spellID = OATH_ID, itemType = 1 })
P.SpellRegistry:Refresh()
local Oath = P.Oath
assert(Oath:IsKnown(), "Oath of Light learned")
local function oathStatus()
	for _, r in ipairs(BS:Evaluate()) do
		if r.id == "oath" then
			return r.status, r
		end
	end
end
assert(oathStatus() == nil, "solo: no Oath check")
MOCK.inGroup = true
MOCK.party = {
	{ unit = "party1", name = "Beefy", class = "WARRIOR", guid = TANK, role = "TANK" },
	{ unit = "party2", name = "Stabby", class = "ROGUE", guid = ROGUE2 },
}
MOCK.unitAuras = { party1 = {}, party2 = {} }
MOCK.fire("GROUP_ROSTER_UPDATE")
settle()
assert(oathStatus() == "missing", "in a group with no Oath: red")
local function cast(target, castId)
	MOCK.fire("UNIT_SPELLCAST_SENT", "player", target, castId, OATH_ID)
	MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", castId, OATH_ID)
end
cast("Stabby", "c1")
local st, r = oathStatus()
assert(st == "wrong" and r.detail:find("Stabby", 1, true) and r.detail:find("Beefy", 1, true),
	"Oath on the rogue while Beefy tanks: yellow")
-- Recast on the tank in combat: followed from the cast events alone.
MOCK.combat = true
cast("Beefy", "c2")
st, r = oathStatus()
assert(st == "ok" and Oath:Get().name == "Beefy" and Oath:Get().source == "cast", "in-combat recast on the tank")
assert(math.abs(Oath:Remaining() - 300) < 1, "default 5 minute timer")
MOCK.combat = false
if not MOCK_NO_AURAS then
	-- Out of combat the scan confirms it with the real timer and duration.
	MOCK.unitAuras.party1 = { { name = "Oath of Light", spellId = OATH_ID, duration = 240,
		expirationTime = GetTime() + 200, mine = true } }
	P.Roster:Scan()
	assert(Oath:Get().source == "aura" and math.abs(Oath:Remaining() - 200) < 1, "aura timer wins")
	assert(P.db.oathDuration == 240, "duration learned")
	-- Last minute: expiring.
	MOCK.unitAuras.party1[1].expirationTime = GetTime() + 30
	P.Roster:Scan()
	assert(oathStatus() == "expiring", "last minute: expiring")
	-- Another paladin's Oath on the tank isn't yours.
	MOCK.unitAuras.party1 = { { name = "Oath of Light", spellId = OATH_ID, duration = 240,
		expirationTime = GetTime() + 200 } }
	P.Roster:Scan()
	assert(Oath:Get() == nil and oathStatus() == "missing", "someone else's Oath doesn't count; yours is gone")
end
-- No roles assigned: any target is fine.
MOCK.party[1].role = nil
MOCK.fire("GROUP_ROSTER_UPDATE")
settle()
cast("Stabby", "c3")
assert(oathStatus() == "ok", "no tank role known: Oath on anyone is fine")
slash("oath")
slash("check")
P.db.oathDuration = nil
Oath.state = nil
for i = #MOCK.book, 1, -1 do
	if MOCK.book[i].spellID == OATH_ID then
		table.remove(MOCK.book, i)
	end
end
P.SpellRegistry:Refresh()
MOCK.unitAuras = {}
MOCK.inGroup = false
MOCK.party = {}
MOCK.fire("GROUP_ROSTER_UPDATE")
settle()

-- Holy Seal reminders: Light on bosses (without your Judgement of Light),
-- Mana at low mana (display only: the game's curve sets the alpha).
if not MOCK_NO_AURAS then
	local ST = P.modules.SealTracker
	local HS = P.HolySeals
	local stSettings = P.Config:GetModuleSettings("SealTracker")
	stSettings.holySealReminders = true
	assert(P.SpecProfile:GetSpec() == "holy", "holy for this test")
	for _, r in ipairs(BS:Evaluate()) do
		assert(r.id ~= "seal", "Holy: no generic Seal check")
	end
	assert(HS:Reminder() == nil, "neither Seal learned: no reminder")
	table.insert(MOCK.book, { name = "Seal of Wisdom", spellID = 900300, itemType = 1 })
	table.insert(MOCK.book, { name = "Seal of Light", spellID = 900301, itemType = 1 })
	P.SpellRegistry:Refresh()
	-- Outside an instance: only the low-mana reminder (Righteousness is up).
	assert(HS:Reminder() == "mana", "low-mana reminder outside instances: " .. tostring(HS:Reminder()))
	local f = CreateFrame("Frame")
	for _, case in ipairs({ { 0.8, 0 }, { 0.36, 0 }, { 0.35, 1 }, { 0.2, 1 } }) do
		MOCK.manaPercent = case[1]
		assert(HS:ApplyLowManaAlpha(f), "curve applied")
		assert(f:GetAlpha() == case[2], "mana " .. case[1] .. " -> alpha " .. case[2] .. ", got " .. tostring(f:GetAlpha()))
	end
	MOCK.secretPower = true
	assert(HS:ApplyLowManaAlpha(f), "a secret result still goes straight to the alpha")
	MOCK.secretPower = nil
	ST:Render()
	-- A boss in a dungeon: Light.
	MOCK.instance, MOCK.targetLevel, MOCK.targetName = "party", -1, "Big Boss"
	assert(HS:TargetIsBoss(), "boss detected")
	assert(HS:Reminder() == "light", "boss without Judgement of Light: Light")
	ST:Render()
	-- In combat: cast Seal of Light, then judge: Judgement of Light tracked.
	MOCK.combat = true
	MOCK.fire("PLAYER_REGEN_DISABLED")
	settle()
	MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 900301)
	settle()
	assert(HS:Reminder() == "mana", "Seal of Light up: no Light reminder")
	MOCK.fire("UNIT_SPELLCAST_SENT", "player", "Big Boss", "j1", 20271)
	MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "j1", 20271)
	assert(HS:GetJudgementOfLight(), "Judgement of Light tracked from your cast")
	-- Back to Seal of Wisdom while Judgement of Light is up: nothing to remind.
	MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s2", 900300)
	settle()
	assert(HS:Reminder() == nil, "Wisdom up, Judgement of Light up: no reminder")
	-- Judgement of Light runs out: Light again.
	MOCK.advance(11)
	assert(HS:GetJudgementOfLight() == nil, "Judgement of Light expired")
	assert(HS:Reminder() == "light", "Judgement of Light gone: Light again")
	-- A trash target: no boss.
	MOCK.targetLevel = nil
	assert(HS:Reminder() == nil, "not a boss, Wisdom up: no reminder")
	-- Forever's dungeon bosses are plain elites: the encounter marks them.
	MOCK.fire("ENCOUNTER_START", 444, "Interrogator Vishas", 1, 5)
	assert(HS:TargetIsBoss() and HS:Reminder() == "light", "elite during an encounter: boss")
	MOCK.fire("ENCOUNTER_END", 444, "Interrogator Vishas", 1, 5, 1)
	assert(not HS:TargetIsBoss(), "encounter over: not a boss")
	ST:Render()
	MOCK.combat = false
	MOCK.fire("PLAYER_REGEN_ENABLED")
	settle()
	assert(P.db.holySealLog and #P.db.holySealLog > 0, "reminder events logged")
	-- Option off: Holy gets the normal Seal check back.
	stSettings.holySealReminders = false
	assert(HS:Reminder() == nil, "option off: no reminders")
	stSettings.holySealReminders = true
	MOCK.instance, MOCK.targetName, MOCK.manaPercent = nil, nil, 1
	for i = #MOCK.book, 1, -1 do
		if MOCK.book[i].spellID == 900300 or MOCK.book[i].spellID == 900301 then
			table.remove(MOCK.book, i)
		end
	end
	P.SpellRegistry:Refresh()
end

-- Light's Vigil (opt-in): a timer from your own casts, red in combat when none is up.
do
	local VIGIL_ID = 900400
	table.insert(MOCK.book, { name = "Light's Vigil", spellID = VIGIL_ID, itemType = 1 })
	P.SpellRegistry:Refresh()
	local Vigil = P.Vigil
	local bsSettings = P.Config:GetModuleSettings("BuffSentinel")
	local function vigilStatus()
		for _, r in ipairs(BS:Evaluate()) do
			if r.id == "vigil" then
				return r.status, r
			end
		end
	end
	assert(Vigil:IsKnown(), "Light's Vigil learned")
	assert(vigilStatus() == nil, "off by default")
	bsSettings.checkVigil = true
	assert(vigilStatus() == "idle", "none up out of combat: idle")
	MOCK.combat = true
	assert(vigilStatus() == "missing", "none up in combat: red")
	MOCK.fire("UNIT_SPELLCAST_SENT", "player", "Ragnaros", "v1", VIGIL_ID)
	MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "v1", VIGIL_ID)
	local st, r = vigilStatus()
	assert(st == "active" and r.aura.name:find("Ragnaros", 1, true), "cast on the boss: timer")
	assert(math.abs(Vigil:Remaining() - 30) < 1, "30 second default")
	BS:Render()
	MOCK.advance(26)
	assert(vigilStatus() == "expiring", "last 5 seconds: pulse")
	MOCK.advance(5)
	assert(vigilStatus() == "missing", "ran out in combat: red")
	MOCK.combat = false
	assert(P.db.vigilLog and #P.db.vigilLog == 1, "cast logged")
	slash("check")
	bsSettings.checkVigil = false
	Vigil.state = nil
	for i = #MOCK.book, 1, -1 do
		if MOCK.book[i].spellID == VIGIL_ID then
			table.remove(MOCK.book, i)
		end
	end
	P.SpellRegistry:Refresh()
end

-- Localization: a locale file fills PK.L only on its own client; missing
-- keys fall back to English.
do
	assert(P.L["Holy"] == "Holy", "English by default")
	assert(P.NewLocale("enUS") == nil and P.NewLocale("deDE") == nil, "other locales skip their file")
	local saved = P.LOCALE
	P.LOCALE = "deDE"
	local L = P.NewLocale("deDE")
	assert(L == P.L, "the client's own locale fills the table")
	L["Holy"] = "Heilig"
	assert(P.L["Holy"] == "Heilig" and P.L["Protection"] == "Protection", "translated, untranslated falls back")
	L["Holy"] = nil
	P.LOCALE = saved
	-- A German spellbook: the English name matches nothing, the spell ID does.
	local savedBook = MOCK.book
	MOCK.book = { { name = "Segen der Macht", spellID = 19740, itemType = 1 } }
	local book = { { name = "Segen der Macht", spellID = 19740, itemType = "Spell" } }
	local r = P.Spells.Resolve(P.Spells.byKey.BLESSING_MIGHT, P.Spells.IndexSpellbook(book))
	assert(r.name == "Segen der Macht" and r.spellID == 19740 and r.known, "found by ID on a German client")
	MOCK.book = savedBook
end

-- Proc stacks next to the Seal: read out of combat, kept (timer running,
-- stacks marked *) in combat, where Forever blocks aura reads.
if not MOCK_NO_AURAS then
	local AS = P.AuraService
	table.insert(MOCK.auras, { name = "Vengeance", spellId = 20050, applications = 3, duration = 30,
		expirationTime = GetTime() + 20 })
	AS:Scan()
	local v, src = AS:GetProc("VENGEANCE")
	assert(v and v.stacks == 3 and src == "aura", "Vengeance found by ID with its stacks")
	P.modules.SealTracker:UpdateProcs()
	MOCK.combat = true
	AS:Scan()
	v, src = AS:GetProc("VENGEANCE")
	assert(v and v.stacks == 3, "kept through combat")
	-- Crits on your target add Vengeance stacks (Ret), up to 5.
	local realSpec = P.SpecProfile.GetSpec
	P.SpecProfile.GetSpec = function()
		return "ret"
	end
	MOCK.fire("UNIT_COMBAT", "target", "WOUND", "", 100, 1)
	assert(AS:GetProc("VENGEANCE").stacks == 3, "a normal hit doesn't add Vengeance")
	MOCK.fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 100, 1)
	v, src = AS:GetProc("VENGEANCE")
	assert(v.stacks == 4 and src == "predicted" and math.abs(AS:Remaining(v) - 30) < 1, "crit: +1 stack, 30 s")
	MOCK.fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 100, 2)
	MOCK.fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 100, 1)
	assert(AS:GetProc("VENGEANCE").stacks == 5, "capped at 5")
	MOCK.advance(25)
	MOCK.fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 100, 1)
	MOCK.advance(10)
	v = AS:GetProc("VENGEANCE")
	assert(v and v.stacks == 1, "older stacks ran out one by one, the newest is left")
	MOCK.advance(-35)
	P.SpecProfile.GetSpec = realSpec
	MOCK.combat = false
	table.remove(MOCK.auras)
	AS:Scan()
	assert(AS:GetProc("VENGEANCE") == nil, "gone after combat when it's gone")
	local check = P.db.procLog and P.db.procLog[#P.db.procLog]
	assert(check and check.vengGuess == 1 and check.vengReal == nil and check.crits == 4, "guess vs real logged")
end

-- Max-stacks glow: on and off without errors (fallback edge in the mocks).
do
	local f = CreateFrame("Frame")
	P.Theme.SetGlow(f, true)
	assert(f.glowOn == true, "glow on")
	P.Theme.SetGlow(f, false)
	assert(f.glowOn == false, "glow off")
end

-- Warning sounds: picked per warning; "None" is silent; custom files exist.
do
	local S = P.Sounds
	assert(S:Get("missing").key == "RAID_WARNING", "raid warning by default")
	assert(S:Cycle("missing").key == "READY_CHECK", "cycles to the next sound")
	assert(S:Cycle("missing", -1).key == "RAID_WARNING", "right-click goes back")
	S:Set("seal", "NONE")
	S:Play("seal")
	assert(S.byKey.CUSTOM1 and S.byKey.CUSTOM5.file == "custom5", "custom file slots")
	S:Preview(S.byKey.CUSTOM1)
	S:Set("seal", "RAID_WARNING")
end

-- Infusion of Light (Holy): a heal crit right after your own Flash of
-- Light / Holy Shock; your next Holy Light uses it.
if not MOCK_NO_AURAS then
	local AS = P.AuraService
	table.insert(MOCK.book, { name = "Flash of Light", spellID = 19750, itemType = 1 })
	table.insert(MOCK.book, { name = "Holy Light", spellID = 635, itemType = 1 })
	P.SpellRegistry:Refresh()
	assert(P.SpecProfile:GetSpec() == "holy", "holy for this test")
	MOCK.combat = true
	MOCK.fire("PLAYER_REGEN_DISABLED")
	AS:Scan()
	MOCK.fire("UNIT_COMBAT", "party1", "HEAL", "CRITICAL", 500, 2)
	assert(AS:GetProc("INFUSION_OF_LIGHT") == nil, "someone else's crit heal doesn't count")
	MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "h1", 19750)
	MOCK.fire("UNIT_COMBAT", "party1", "HEAL", "", 500, 2)
	assert(AS:GetProc("INFUSION_OF_LIGHT") == nil, "no crit, no proc")
	MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "h2", 19750)
	MOCK.fire("UNIT_COMBAT", "party1", "HEAL", "CRITICAL", 500, 2)
	local inf, src = AS:GetProc("INFUSION_OF_LIGHT")
	assert(inf and src == "predicted" and math.abs(AS:Remaining(inf) - 15) < 1, "crit Flash of Light: Infusion")
	MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "h3", 635)
	assert(AS:GetProc("INFUSION_OF_LIGHT") == nil, "Holy Light uses it")
	MOCK.combat = false
	MOCK.fire("PLAYER_REGEN_ENABLED")
	AS:Scan()
	table.remove(MOCK.book)
	table.remove(MOCK.book)
	P.SpellRegistry:Refresh()
end

-- DB v5: Buff Sentinel moves up only where it was never moved.
local oldDb = { version = 4, profiles = { P1 = { layout = {
	holy = { BuffSentinel = { point = "CENTER", x = 0, y = -120, scale = 1 } },
	ret = { BuffSentinel = { point = "CENTER", x = 40, y = -120, scale = 1 } },
} } } }
P.Config.Migrate(oldDb)
assert(oldDb.version == 5, "migrated to v5")
assert(oldDb.profiles.P1.layout.holy.BuffSentinel.y == -110, "default spot raised")
assert(oldDb.profiles.P1.layout.ret.BuffSentinel.y == -120, "moved frames left alone")

M6_OK = true
