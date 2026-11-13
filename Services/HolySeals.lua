local _, PK = ...

-- Holy Seal reminders, shown by the Seal Tracker:
--  * "Light": you're targeting a boss in a dungeon or raid, your Judgement
--    of Light isn't on it, and Seal of Light isn't up. Judgement of Light
--    is followed from your own casts (Judgement while Seal of Light is
--    active; cast events stay readable in combat). Other paladins'
--    Judgements can't be seen in combat.
--  * "Mana": your mana is at or under the low-mana line (35%). Forever
--    keeps your mana secret, so the addon never sees the number: the game
--    evaluates a curve (1 below the line, 0 above) and the result is passed
--    straight to the reminder's alpha. Display only, no decisions.
-- What worked and what didn't is logged to NyteLytePaladinToolkitDB.holySealLog
-- so it can be checked from the saved variables.

local Compat = PK.Compat
local Secrets = PK.Secrets
local AS = PK.AuraService
local HS = { jol = nil }
PK.HolySeals = HS

local DEFAULT_JOL_DURATION = 10 -- Classic's Judgement of Light; Forever's unverified
local LOG_MAX = 60
local pendingTarget -- Judgement target name from UNIT_SPELLCAST_SENT
local logged = {}

local function log(event, fields, onceKey)
	local db = PK.db
	if not db or (onceKey and logged[onceKey]) then
		return
	end
	if onceKey then
		logged[onceKey] = true
	end
	db.holySealLog = db.holySealLog or {}
	local row = { t = time(), event = event, inCombat = Compat.InCombat() or nil }
	for k, v in pairs(fields or {}) do
		row[k] = v
	end
	table.insert(db.holySealLog, row)
	while #db.holySealLog > LOG_MAX do
		table.remove(db.holySealLog, 1)
	end
end
HS.Log = log

local function safe(fn, ...)
	if not fn then
		return nil
	end
	local ok, v = pcall(fn, ...)
	if not ok or Compat.IsSecret(v) then
		return nil
	end
	return v
end

local function describe(v)
	if Compat.IsSecret(v) then
		return "<secret>"
	end
	return tostring(v)
end

-- Boss context ----------------------------------------------------------------------------

-- In a dungeon or raid, targeting a boss? Bosses: anything attackable
-- during a boss encounter (ENCOUNTER_START..END; Forever's dungeon bosses
-- are plain "elite" with a normal level and no boss1 unit, seen in Scarlet
-- Monastery), level -1 / "worldboss", or one of the boss1..boss5 units.
function HS:TargetIsBoss()
	local okI, inInstance, instanceType = pcall(IsInInstance)
	if not okI or Compat.IsSecret(inInstance) or not inInstance or Compat.IsSecret(instanceType)
		or (instanceType ~= "party" and instanceType ~= "raid") then
		return false
	end
	if not safe(UnitExists, "target") or safe(UnitCanAttack, "player", "target") == false then
		return false
	end
	local classification = safe(UnitClassification, "target")
	local level = safe(UnitLevel, "target")
	local isBoss = HS.encounter ~= nil or classification == "worldboss" or level == -1
	if not isBoss then
		for i = 1, 5 do
			if safe(UnitExists, "boss" .. i) and safe(UnitIsUnit, "target", "boss" .. i) then
				isBoss = true
				break
			end
		end
	end
	local name = safe(UnitName, "target")
	log("bossCheck", {
		target = name,
		classification = describe(UnitClassification and select(2, pcall(UnitClassification, "target"))),
		level = describe(UnitLevel and select(2, pcall(UnitLevel, "target"))),
		boss1 = safe(UnitExists, "boss1") and true or false,
		instanceType = instanceType,
		encounter = HS.encounter,
		isBoss = isBoss,
	}, "boss:" .. tostring(name) .. ":" .. tostring(classification) .. ":" .. tostring(level) .. ":"
		.. tostring(HS.encounter) .. ":" .. tostring(Compat.InCombat()))
	return isBoss
end

-- Judgement of Light (yours) ---------------------------------------------------------------

local function jolDuration()
	return (PK.db and PK.db.jolDuration) or DEFAULT_JOL_DURATION
end

-- Your Judgement of Light on the current target, as { target, expires }, or nil.
function HS:GetJudgementOfLight()
	local j = self.jol
	if not j or j.expires <= GetTime() then
		return nil
	end
	local name = safe(UnitName, "target")
	-- Target name unreadable: assume it's still the one you judged.
	if name and j.target and name ~= j.target and not j.target:find("^" .. name:gsub("%p", "%%%0") .. " ") then
		return nil
	end
	return j
end

PK:RegisterEvent("UNIT_SPELLCAST_SENT", HS, function(_, _, unit, target, _, spellID)
	if Compat.IsSecret(unit) or unit ~= "player" then
		return
	end
	local id = Secrets.SafeNumber(spellID)
	local r = PK.SpellRegistry:Get("JUDGEMENT")
	if id and r and (r.spellID == id or (r.ids and r.ids[id])) then
		pendingTarget = Secrets.SafeString(target)
	end
end)

PK:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", HS, function(_, _, unit, _, spellID)
	if Compat.IsSecret(unit) or unit ~= "player" then
		return
	end
	local id = Secrets.SafeNumber(spellID)
	local r = PK.SpellRegistry:Get("JUDGEMENT")
	if not (id and r and (r.spellID == id or (r.ids and r.ids[id]))) then
		return
	end
	local seal = AS:GetSeal()
	local sealKey = AS.SealKey(seal)
	local target = pendingTarget or safe(UnitName, "target")
	pendingTarget = nil
	log("judgement", { seal = seal and seal.name, sealKey = sealKey, target = target })
	if sealKey == "SEAL_LIGHT" then
		HS.jol = { target = target, expires = GetTime() + jolDuration() }
		PK:Fire("PK_HOLY_SEALS_UPDATED")
	end
end)

PK:RegisterEvent("PLAYER_TARGET_CHANGED", HS, function()
	PK:Fire("PK_HOLY_SEALS_UPDATED")
end)
PK:RegisterEvent("ENCOUNTER_START", HS, function(_, _, encounterID, encounterName)
	log("encounterStart", { id = describe(encounterID), name = describe(encounterName) })
	HS.encounter = Secrets.SafeString(encounterName) or "boss"
	PK:Fire("PK_HOLY_SEALS_UPDATED")
end)
PK:RegisterEvent("ENCOUNTER_END", HS, function()
	HS.encounter = nil
	HS.jol = nil
	PK:Fire("PK_HOLY_SEALS_UPDATED")
end)

-- Low mana (display only) ------------------------------------------------------------------

local manaCurve, manaCurveFor

-- A curve that is 1 at or below the low-mana line and 0 above it, built
-- once per line value. nil if the client can't do it.
local function curveFor(percent)
	if manaCurve ~= nil and manaCurveFor == percent then
		return manaCurve or nil
	end
	manaCurveFor = percent
	manaCurve = false
	local create = Compat.Resolve("C_CurveUtil.CreateCurve")
	if not create or not UnitPowerPercent then
		log("manaApi", { createCurve = create ~= nil, unitPowerPercent = UnitPowerPercent ~= nil }, "manaApi")
		return nil
	end
	local ok, curve = pcall(create)
	if not ok or not curve or not curve.AddPoint then
		log("manaApi", { curve = "create failed: " .. tostring(curve) }, "manaApi")
		return nil
	end
	local line = percent / 100
	local okPoints = pcall(function()
		curve:AddPoint(0, 1)
		curve:AddPoint(line, 1)
		curve:AddPoint(line + 0.005, 0)
		curve:AddPoint(1, 0)
	end)
	if not okPoints then
		log("manaApi", { curve = "AddPoint failed" }, "manaApi")
		return nil
	end
	manaCurve = curve
	log("manaApi", { curve = "ok", line = percent }, "manaApi")
	return curve
end

-- Sets frame's alpha to 1 when mana is at or below the line, else 0,
-- without the addon ever reading the mana value. Returns false if the
-- client can't do it (then the caller hides the frame).
function HS:ApplyLowManaAlpha(frame)
	local s = PK.Config:GetModuleSettings("SealTracker")
	local curve = curveFor(s.holyManaPercent or 35)
	if not curve then
		return false
	end
	local manaType = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
	local ok, value = pcall(UnitPowerPercent, "player", manaType, false, curve)
	if not ok then
		log("manaApi", { evaluate = "failed: " .. tostring(value) }, "manaEval")
		return false
	end
	local okAlpha, err = pcall(frame.SetAlpha, frame, value)
	if not okAlpha then
		log("manaApi", { setAlpha = "failed: " .. tostring(err), secret = Compat.IsSecret(value) }, "manaAlpha")
		return false
	end
	log("manaApi", { setAlpha = "ok", secret = Compat.IsSecret(value) }, "manaAlphaOk")
	return true
end

-- The reminder to show right now: "light", "mana" or nil.
-- "mana" means "show the low-mana reminder" (visible only below the line).
function HS:Reminder()
	if not AS:HolySealMode() then
		return nil
	end
	local registry = PK.SpellRegistry
	local sealKey = AS.SealKey((AS:GetSeal()))
	if registry:IsKnown("SEAL_LIGHT") and self:TargetIsBoss() and not self:GetJudgementOfLight()
		and sealKey ~= "SEAL_LIGHT" then
		return "light"
	end
	if registry:IsKnown("SEAL_WISDOM") and sealKey ~= "SEAL_WISDOM" then
		return "mana"
	end
	return nil
end
