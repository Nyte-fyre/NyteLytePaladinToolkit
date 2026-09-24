-- M3 flows (Tank Kit, Twist of Light Echo, Iron Creed), run after m2_flows.lua.
local P = NyteLytePaladinToolkit
local AS = P.AuraService
local TK, ST = P.modules.TankKit, P.modules.SealTracker
local function slash(msg)
	SlashCmdList.NYTELYTEPALADINTOOLKIT(msg)
end
local function rescan()
	MOCK.fire("UNIT_AURA", "player", { isFullUpdate = true })
	MOCK.runTimers()
end

slash("prot")
assert(TK.enabled, "Tank Kit on for Prot")

-- Aura-dependent parts need an aura API.
if not MOCK_NO_AURAS then
	-- Teach the mock character some Prot/Ret spells and talents.
	local added = {
		{ name = "Seal of Fury", spellID = 900010, itemType = 1 },
		{ name = "Seal of Command", spellID = 900011, itemType = 1 },
		{ name = "Twist of Light", spellID = 900012, itemType = 1 },
		{ name = "Iron Creed", spellID = 900013, itemType = 1 },
		{ name = "Consecration", spellID = 26573, itemType = 1 },
		{ name = "Seal of the Crusader", spellID = 21082, itemType = 1 },
	}
	local bookSize = #MOCK.book
	for _, b in ipairs(added) do
		table.insert(MOCK.book, b)
	end
	MOCK.fire("SPELLS_CHANGED")
	MOCK.runTimers()
	MOCK.runTimers()
	assert(TK:State().icons == 3, "Judgement, Consecration, Holy Strike; got " .. TK:State().icons)

	-- Righteous Fury warning
	rescan()
	TK:UpdateAuras()
	assert(TK:State().warningShown, "RF warning while missing")
	local auraCount = #MOCK.auras
	table.insert(MOCK.auras, { name = "Righteous Fury", spellId = 25780, duration = 1800, expirationTime = GetTime() + 1800 })
	rescan()
	assert(not TK:State().warningShown, "RF warning hidden once active")

	-- Seal of Fury makes Judgement a taunt.
	local sealIndex
	for i, a in ipairs(MOCK.auras) do
		if a.spellId == 21084 then
			sealIndex = i
		end
	end
	local oldSeal = MOCK.auras[sealIndex]
	MOCK.auras[sealIndex] = { name = "Seal of Fury", spellId = 900010, duration = 30, expirationTime = GetTime() + 30 }
	rescan()
	assert(TK:State().taunt, "TAUNT label with Seal of Fury")

	-- Combat: casts drive predictions.
	MOCK.combat = true
	MOCK.fire("PLAYER_REGEN_DISABLED")
	rescan()
	assert(AS.frozen, "frozen")
	MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 900001) -- Holy Strike (mock ID)
	TK:UpdateAuras()
	assert(TK:State().ironCreed, "Iron Creed predicted from Holy Strike with RF")
	assert(select(2, AS:GetIronCreed()) == "predicted", "Iron Creed marked predicted")

	-- Twist of Light: Seal of Fury -> Seal of Command grants Echo of Seal of Fury.
	MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 900011)
	local echo, source = AS:GetEcho()
	assert(echo and source == "predicted" and echo.replacedSeal == "Seal of Fury", "Echo predicted")
	assert(AS:GetSeal().name == "Seal of Command", "new Seal predicted")
	assert(not TK:State().taunt, "no taunt label once Seal of Fury is gone")
	ST:Render()
	ST:UpdateEcho()
	-- Swapping away from Command (twistable) to any Seal also grants Echo.
	MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 21082) -- Seal of the Crusader
	assert(AS:GetEcho().replacedSeal == "Seal of Command", "Echo of Seal of Command")
	-- Crusader isn't twistable: swapping away from it gives no new Echo.
	AS.echo = nil
	MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-4", 21084)
	assert(AS:GetEcho() == nil, "no Echo from replacing Seal of the Crusader")

	-- Predictions expire on their own.
	MOCK.advance(11)
	assert(AS:GetIronCreed() == nil, "Iron Creed expired")
	MOCK.advance(-11)

	-- Leaving combat clears predictions.
	MOCK.combat = false
	MOCK.fire("PLAYER_REGEN_ENABLED")
	MOCK.runTimers()
	assert(AS.echo == nil and AS.ironCreed == nil, "predictions cleared after combat")

	-- Ready check / zone-in reminders with RF present: silent.
	MOCK.fire("READY_CHECK", "Leader", 30)
	MOCK.fire("PLAYER_ENTERING_WORLD")
	MOCK.runTimers()

	-- Restore mock state.
	MOCK.auras[sealIndex] = oldSeal
	while #MOCK.auras > auraCount do
		table.remove(MOCK.auras)
	end
	while #MOCK.book > bookSize do
		table.remove(MOCK.book)
	end
	MOCK.fire("SPELLS_CHANGED")
	MOCK.runTimers()
	MOCK.runTimers()
	rescan()
end

-- Tank Kit is off for Ret/Holy by default and toggles live.
slash("ret")
assert(not TK.enabled, "Tank Kit off for Ret")
P.Config:SetModuleEnabled("TankKit", "ret", true)
assert(TK.enabled, "Tank Kit enabled for Ret on request")
P.Config:SetModuleEnabled("TankKit", "ret", false)
assert(not TK.enabled, "and off again")
slash("holy")

M3_OK = true
