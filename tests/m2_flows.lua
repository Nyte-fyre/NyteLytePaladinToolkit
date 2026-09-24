-- M2 flows (Buff Sentinel, Seal Tracker, Cooldown HUD), run after m1_flows.lua.
local P = NyteLytePaladinToolkit
local AS = P.AuraService
local BS, ST, CD = P.modules.BuffSentinel, P.modules.SealTracker, P.modules.CooldownHUD
local function slash(msg)
	SlashCmdList.NYTELYTEPALADINTOOLKIT(msg)
end
local function statusOf(id)
	for _, r in ipairs(BS:Evaluate()) do
		if r.id == id then
			return r.status
		end
	end
	return nil
end
local function rescan()
	MOCK.fire("UNIT_AURA", "player", { isFullUpdate = true })
	MOCK.runTimers()
end

slash("holy")
assert(BS.enabled and ST.enabled and CD.enabled, "Holy enables the three M2 modules")

-- Aura checks need an aura API (skipped in the "no C_UnitAuras" scenario).
if not MOCK_NO_AURAS then
-- Out of combat: everything readable.
rescan()
assert(not AS.frozen, "not frozen out of combat")
assert(statusOf("seal") == "ok", "seal ok")
assert(statusOf("aura") == "ok", "aura from stance bar")
assert(statusOf("blessing") == "missing", "no blessing yet")
assert(statusOf("rf") == nil, "no Righteous Fury check as Holy")

-- A Blessing with 60s left is "expiring" (threshold 120s).
table.insert(MOCK.auras, { name = "Blessing of Might", spellId = 19740, duration = 3600, expirationTime = GetTime() + 60 })
rescan()
assert(statusOf("blessing") == "expiring", "blessing expiring")
slash("check")
MOCK.fire("READY_CHECK", "Leader", 30)

-- Combat: auras unreadable -> frozen snapshot, timers keep running.
MOCK.combat = true
MOCK.fire("PLAYER_REGEN_DISABLED")
rescan()
assert(AS.frozen, "frozen in combat")
assert(statusOf("blessing") == "expiring", "blessing state kept while frozen")
assert(statusOf("seal") == "ok", "seal kept while frozen")

-- Casting a Seal in combat predicts it.
MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 21084)
local seal, source = AS:GetSeal()
assert(seal and source == "predicted", "seal predicted from cast")
assert(seal.duration == 30, "learned 30s duration")
ST:Render()

-- When the prediction runs out while blind: "unknown", not a false alarm.
MOCK.advance(61)
assert(statusOf("seal") == "unknown", "seal unknown when blind")
ST:Render()
assert(statusOf("blessing") == "missing", "blessing expired by its own timer")

-- Cooldowns with secret numbers must not error.
MOCK.fire("SPELL_UPDATE_COOLDOWN")
CD:Update()

-- Leaving combat unfreezes and rescans.
MOCK.combat = false
MOCK.fire("PLAYER_REGEN_ENABLED")
MOCK.runTimers()
assert(not AS.frozen, "unfrozen after combat")
table.remove(MOCK.auras) -- drop the blessing again
MOCK.advance(-61)
end -- aura checks

-- Cooldown HUD: only learned spells from the Holy list (Holy Shock, Holy Strike in the mocks).
CD:Rebuild()
assert(CD:IconCount() == 2, "expected 2 learned Holy cooldowns, got " .. CD:IconCount())
P.Config:GetModuleSettings("CooldownHUD").showUnknown = true
P:Fire("PK_SETTINGS_CHANGED")
assert(CD:IconCount() == 2, "unknown spells without spell IDs stay hidden")
P.Config:GetModuleSettings("CooldownHUD").showUnknown = false
P:Fire("PK_SETTINGS_CHANGED")

-- Global cooldown vs real cooldown (isOnGCD is readable in combat on Forever).
for _, combat in ipairs({ false, true }) do
	MOCK.combat = combat
	MOCK.cooldowns[900001] = { active = true, gcd = true } -- Holy Strike (mock ID): only the GCD
	MOCK.cooldowns[20473] = { active = true, gcd = false } -- Holy Shock: real cooldown
	CD:Update()
	local st = CD:IconStates()
	assert(st[900001] == "ready", "GCD must not count as a cooldown (combat=" .. tostring(combat) .. ")")
	assert(st[20473] == "cooldown", "real cooldown shown (combat=" .. tostring(combat) .. ")")
	MOCK.cooldowns[20473] = { active = false, gcd = false }
	CD:Update()
	assert(CD:IconStates()[20473] == "ready", "inactive = ready")
end
MOCK.combat = false
MOCK.cooldowns = {}

-- Group-only entries (Purify is "@group" in the Holy defaults).
MOCK.inGroup = true
MOCK.fire("GROUP_ROSTER_UPDATE")
MOCK.runTimers()
assert(CD:IconCount() == 3, "Purify shows in a group, got " .. CD:IconCount())
MOCK.inGroup = false
MOCK.fire("GROUP_ROSTER_UPDATE")
MOCK.runTimers()
assert(CD:IconCount() == 2, "Purify hidden solo")
slash("cd group Holy Strike")
assert(CD:IconCount() == 1, "Holy Strike made group-only")
slash("cd group holy strike")
assert(CD:IconCount() == 2, "Holy Strike back to always")

-- /ptk cd editing
slash("cd")
slash("cd add Judgement")
assert(CD:IconCount() == 3, "Judgement added")
slash("cd add Judgement")
slash("cd remove judgement")
assert(CD:IconCount() == 2, "Judgement removed")
slash("cd add Some Custom Spell")
slash("cd remove Some Custom Spell")
slash("cd reset")

-- Spec switch rebuilds; module toggles apply live.
slash("prot")
assert(CD.enabled and CD:IconCount() == 0, "prot list rebuilt (no Prot defensives learned in the mocks)")
P.Config:SetModuleEnabled("CooldownHUD", "prot", false)
assert(not CD.enabled, "disabled live")
P.Config:SetModuleEnabled("CooldownHUD", "prot", true)
assert(CD.enabled, "re-enabled live")
assert(statusOf("rf") == "missing", "Righteous Fury required as Prot")
slash("holy")

-- Settings option toggles
P.Config:GetModuleSettings("BuffSentinel").showAll = true
P:Fire("PK_SETTINGS_CHANGED")
P.Config:GetModuleSettings("SealTracker").showBar = false
P:Fire("PK_SETTINGS_CHANGED")
P.Settings:Refresh()

M2_OK = true
