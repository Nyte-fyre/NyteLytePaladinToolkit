-- M1 flows, run after login by run_tests.py (mocks + addon already loaded).
local P = NyteLytePaladinToolkit
local function slash(msg)
	SlashCmdList.NYTELYTEPALADINTOOLKIT(msg)
end

assert(NyteLytePaladinToolkitDB.version == 1, "db version")
assert(NyteLytePaladinToolkitDB.profileKeys["Tester-Beta Realm"] == "Default", "profile key")
assert(P.profile and P.profile.specMode == "auto", "default spec mode")

-- Spec switching
local changes = 0
P:On("PK_SPEC_CHANGED", "test", function()
	changes = changes + 1
end)
slash("prot")
assert(P.SpecProfile:GetSpec() == "prot", "manual prot")
slash("ret")
slash("auto")
assert(P.SpecProfile:GetSpec() == "holy", "auto should detect holy from Holy Shock")
assert(P.SpecProfile:GetDecision().method == "known spells", "detection method")
assert(changes == 3, "expected 3 spec changes, got " .. changes)
slash("spec")
P.SpecProfile:Cycle()
assert(P.profile.specMode == "holy", "cycle auto -> holy")
P:Off("PK_SPEC_CHANGED", "test")

-- Frames
slash("unlock")
assert(P.profile.locked == false, "unlocked")
assert(P.Frames.anchors.CooldownHUD, "anchor created on unlock")
slash("lock")
assert(P.profile.locked == true, "locked")
P.Config:SetLayout("holy", "CooldownHUD", "CENTER", 12, -40)
assert(P.Config:GetLayout("holy", "CooldownHUD").x == 12, "layout saved")
slash("reset")
assert(P.Config:GetLayout("holy", "CooldownHUD").y == -190, "layout reset to preset")

-- Settings
local before = MOCK.settingsOpened
slash("")
slash("config")
assert(MOCK.settingsOpened == before + 2, "settings opened")
MOCK.combat = true
slash("")
assert(MOCK.settingsOpened == before + 2, "settings must not open in combat")
MOCK.combat = false
MOCK.fire("PLAYER_REGEN_ENABLED")
assert(MOCK.settingsOpened == before + 3, "settings open after combat")
P.Settings:Refresh()

-- Module toggles
P.Config:SetModuleEnabled("TankKit", "holy", true)
assert(P.Config:IsModuleEnabled("TankKit", "holy"), "toggle on")

-- Export / import
P.profile.cooldownLists.holy = { "HOLY_SHOCK" }
P.profile.alerts.expiringThresholdSec = 45
local s = P.Config:ExportProfile()
assert(type(s) == "string" and s:find("^NLPT:1:%x+:"), "export format")
assert(not s:find("|", 1, true), "export must not contain pipes")
P.Config:ResetProfile()
assert(#P.profile.cooldownLists.holy > 1, "reset restores preset list")
assert(P.Config:ImportProfile("  " .. s .. "\n"), "import round trip")
assert(#P.profile.cooldownLists.holy == 1, "imported list must not be refilled from defaults")
assert(P.profile.alerts.expiringThresholdSec == 45, "imported number")
assert(P.Config:IsModuleEnabled("TankKit", "holy"), "imported toggle")
local ok, err = P.Config:ImportProfile("garbage")
assert(not ok and err:find("isn't"), "garbage rejected")
local tampered = s:sub(1, -6) .. (s:sub(-5, -5) == "A" and "B" or "A") .. s:sub(-4)
ok = P.Config:ImportProfile(tampered)
assert(not ok, "tampered string rejected")
-- Unknown keys and wrong types are dropped on import.
local evil = P.Serializer.Encode({ specMode = "paladin", locked = "yes", junk = { a = 1 }, alerts = { sound = false } })
assert(P.Config:ImportProfile(evil), "partial import accepted")
assert(P.profile.specMode == "auto" and P.profile.locked == true and P.profile.junk == nil, "sanitised")
assert(P.profile.alerts.sound == false and P.profile.alerts.expiringThresholdSec == 120, "merged with defaults")
slash("export")
slash("import")

-- Combat queue
MOCK.combat = true
local ran = false
assert(P.CombatQueue:Run("x", function()
	ran = true
end) == false)
assert(not ran, "queued in combat")
MOCK.combat = false
MOCK.fire("PLAYER_REGEN_ENABLED")
assert(ran, "ran after combat")

-- Icons: secret numbers must be ignored, not errored on.
local ic = P.Frames:AcquireIcon(UIParent, 30)
ic:SetSpell(20271)
ic:SetState("missing")
ic:SetCooldownNumbers(MOCK.secret(), 5)
ic:SetCooldownFromDuration(nil)
P.Frames:ReleaseIcon(ic)

-- Secrets (secret detection needs issecretvalue)
if not MOCK_NO_SECRETS then
	assert(P.Secrets.State(MOCK.secret()) == "secret")
	assert(P.Secrets.SafeNumber(MOCK.secret()) == nil)
	assert(P.Secrets.Read(UnitHealth, "player") == "secret")
end
assert(P.Secrets.State(nil) == "unavailable")
assert(P.Secrets.State(0) == "value")
assert(P.Secrets.Read(nil) == "unavailable")

-- Spell registry refresh on SPELLS_CHANGED (debounced)
MOCK.fire("SPELLS_CHANGED")
MOCK.runTimers()
MOCK.runTimers()
assert(P.SpellRegistry:IsKnown("JUDGEMENT"), "registry knows Judgement")
assert(P.SpellRegistry:Get("JUDGEMENT").icon == 135920, "icon resolved")

M1_OK = true
