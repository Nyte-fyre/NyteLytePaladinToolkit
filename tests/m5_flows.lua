-- Post-M5 features: rebuff alert after combat, pre-pull report, Seal warning.
local P = NyteLytePaladinToolkit
local BM, ST = P.modules.BlessingManager, P.modules.SealTracker
local function slash(msg)
	SlashCmdList.NYTELYTEPALADINTOOLKIT(msg)
end
local function settle()
	for _ = 1, 3 do
		MOCK.runTimers()
	end
end
local function printedSince(n, text)
	for i = n + 1, #MOCK.printed do
		if MOCK.printed[i]:find(text, 1, true) then
			return MOCK.printed[i]
		end
	end
	return nil
end
local function might(sec)
	return { name = "Blessing of Might", spellId = 19740, duration = 3600, expirationTime = GetTime() + sec }
end

if not MOCK_NO_AURAS then
	slash("holy")
	P.profile.blessing.assignments = {}
	MOCK.inGroup = true
	MOCK.party = {
		{ unit = "party1", name = "Stabby", class = "ROGUE" },
		{ unit = "party2", name = "Frosty", class = "MAGE" },
	}
	MOCK.unitAuras.party1 = { might(3000) }
	table.insert(MOCK.auras, might(3000))
	MOCK.fire("GROUP_ROSTER_UPDATE")
	settle()
	assert(BM.needingCount == 0, "everyone blessed before the pull")

	-- 1. Stabby dies mid-fight (Blessings drop); after combat we flag him.
	MOCK.fire("PLAYER_REGEN_DISABLED")
	MOCK.combat = true
	MOCK.unitAuras.party1 = {}
	MOCK.combat = false
	local n = #MOCK.printed
	MOCK.fire("PLAYER_REGEN_ENABLED")
	settle()
	local line = printedSince(n, "After combat")
	assert(line and line:find("Stabby", 1, true), "post-combat alert names Stabby: " .. tostring(line))
	local button = _G.NyteLytePaladinToolkitBuffButton
	assert(button.glow:IsShown(), "buff button pulses")
	assert(button:GetAttribute("unit") == "party1", "and targets him")

	-- The pulse stops by itself after 20 seconds...
	MOCK.runTimers(true)
	assert(not button.glow:IsShown(), "pulse times out")
	BM:SetPulse(true)
	-- ...or as soon as rebuffing clears the need.
	MOCK.unitAuras.party1 = { might(3600) }
	P.Roster:Scan()
	assert(not button.glow:IsShown(), "pulse stops once nobody needs it")

	-- A fight where nothing changes stays quiet.
	MOCK.fire("PLAYER_REGEN_DISABLED")
	MOCK.combat = true
	MOCK.combat = false
	n = #MOCK.printed
	MOCK.fire("PLAYER_REGEN_ENABLED")
	settle()
	assert(not printedSince(n, "After combat"), "no alert when nothing changed")

	-- Turned off: no alert even when someone needs it.
	P.Config:GetModuleSettings("BlessingManager").postCombatAlert = false
	MOCK.fire("PLAYER_REGEN_DISABLED")
	MOCK.unitAuras.party1 = {}
	n = #MOCK.printed
	MOCK.fire("PLAYER_REGEN_ENABLED")
	settle()
	assert(not printedSince(n, "After combat"), "alert respects the setting")
	P.Config:GetModuleSettings("BlessingManager").postCombatAlert = true

	-- 2. Pre-pull report: missing and running out within 10 minutes.
	MOCK.unitAuras.party1 = { might(360) }
	n = #MOCK.printed
	slash("buffs")
	line = printedSince(n, "running out within 10m")
	assert(line and line:find("Stabby (6m)", 1, true), "report lists Stabby at 6m: " .. tostring(line))
	MOCK.unitAuras.party1 = {}
	n = #MOCK.printed
	MOCK.fire("READY_CHECK", "Leader", 30)
	line = printedSince(n, "Ready check")
	assert(line and line:find("missing", 1, true) and line:find("Stabby", 1, true), "ready check reports missing Stabby")
	MOCK.unitAuras.party1 = { might(3000) }
	n = #MOCK.printed
	slash("buffs")
	assert(printedSince(n, "last more than 10 minutes"), "all good message")
	MOCK.combat = true
	n = #MOCK.printed
	slash("buffs")
	assert(printedSince(n, "can't be read in combat"), "report refuses in combat")
	MOCK.combat = false

	-- 4. Seal warning: only in combat, only in the last 5 seconds.
	local seal
	for _, a in ipairs(MOCK.auras) do
		if a.spellId == 21084 then
			seal = a
		end
	end
	local oldExp = seal.expirationTime
	seal.expirationTime = GetTime() + 3
	MOCK.fire("UNIT_AURA", "player", {})
	settle()
	ST:Render()
	assert(not ST.warning, "no warning out of combat")
	MOCK.combat = true
	ST:UpdateTimer()
	assert(ST.warning, "warning in the last seconds in combat")
	P.Config:GetModuleSettings("SealTracker").warnSeconds = 0
	ST:UpdateTimer()
	assert(not ST.warning, "warning can be turned off")
	P.Config:GetModuleSettings("SealTracker").warnSeconds = 5
	seal.expirationTime = oldExp
	MOCK.combat = false
	MOCK.fire("UNIT_AURA", "player", {})
	settle()
	ST:UpdateTimer()
	assert(not ST.warning, "plenty of time: no warning")

	-- Clean up.
	table.remove(MOCK.auras)
	MOCK.unitAuras = {}
	MOCK.inGroup = false
	MOCK.party = {}
	MOCK.fire("GROUP_ROSTER_UPDATE")
	settle()
end

M5_OK = true
