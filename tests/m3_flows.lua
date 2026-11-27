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

	-- Unsealed Wrath (Echo): landed melee hits store the active Seal, up to 3.
	MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 900011)
	assert(AS:GetSeal().name == "Seal of Command", "new Seal predicted")
	assert(not TK:State().taunt, "no taunt label once Seal of Fury is gone")
	assert(AS:GetEcho() == nil, "a Seal cast alone stores nothing")
	local function hit(unit, action, descriptor, school)
		MOCK.fire("UNIT_COMBAT", unit or "target", action or "WOUND", descriptor or "", 100, school or 1)
	end
	hit()
	local echo, source = AS:GetEcho()
	assert(echo and source == "predicted" and echo.sealName == "Seal of Command" and echo.stacks == 1,
		"first hit stores Seal of Command")
	hit()
	hit()
	hit()
	assert(AS:GetEcho().stacks == 3, "capped at 3 stacks")
	hit("target", "WOUND", "", 2) -- Holy damage (Seal proc, Judgement) isn't a melee hit
	hit("nameplate1") -- the same hit again under another unit
	hit("target", "PARRY") -- not landed
	assert(AS:GetEcho().stacks == 3 and AS.hitStats.hits == 5, "only landed hits on the target count")
	ST:Render()
	ST:UpdateEcho()
	-- A new Seal: the stacks stay until the next hit, which consumes them and
	-- starts storing the new Seal.
	MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 21082) -- Seal of the Crusader
	assert(AS:GetEcho().sealName == "Seal of Command" and AS:GetEcho().stacks == 3, "kept until the next hit")
	assert(AS.twist, "twist pending")
	hit() -- a swing right after the cast still uses the old Seal
	assert(AS:GetEcho().sealName == "Seal of Command" and AS:GetEcho().stacks == 3, "swing in flight: old Seal")
	MOCK.advance(1)
	hit()
	echo = AS:GetEcho()
	assert(echo.sealName == AS:GetSeal().name and echo.stacks == 1 and AS.twist == nil, "consumed, new Seal stored")
	-- Each copy lasts its own 15 s: stacks fall off one at a time.
	hit()
	MOCK.advance(10)
	hit()
	assert(AS:GetEcho().stacks == 3, "three copies")
	MOCK.advance(6)
	assert(AS:GetEcho().stacks == 1, "the two older copies ran out")
	MOCK.advance(10)
	assert(AS:GetEcho() == nil, "last copy ran out")
	-- The game's buff change can come before the hit report: a buff swapped
	-- in and out while a twist is pending is the Echo swap.
	hit()
	hit()
	MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-7", 900011) -- Seal of Command
	MOCK.fire("UNIT_AURA", "player", { addedAuras = {}, removedAuraInstanceIDs = {} }) -- the cast's own change
	assert(AS:GetEcho().sealName ~= "Seal of Command", "the cast's own buff change isn't the swap")
	MOCK.advance(0.8)
	MOCK.fire("UNIT_AURA", "player", { addedAuras = {}, removedAuraInstanceIDs = {} })
	echo = AS:GetEcho()
	assert(echo.sealName == "Seal of Command" and echo.stacks == 1 and AS.twist == nil, "swapped on the buff change")
	MOCK.advance(0.5)
	hit()
	assert(AS:GetEcho().stacks == 2, "then hits stack as usual")
	MOCK.advance(-27.3)
	local usedLogged = false
	for _, line in ipairs(AS.hitStats.trail or {}) do
		usedLogged = usedLogged or line:find("used", 1, true) ~= nil
	end
	assert(usedLogged, "trail shows the used stacks")

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
