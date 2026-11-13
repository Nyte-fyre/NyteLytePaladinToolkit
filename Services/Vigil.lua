local _, PK = ...

-- Light's Vigil (Holy capstone talent): one at a time, on an ally or an
-- enemy, reported to last 30 seconds. Tracked from your own casts only
-- (UNIT_SPELLCAST_SENT names the target and UNIT_SPELLCAST_SUCCEEDED
-- confirms it; both stay readable in combat). Enemy debuffs can't be read in
-- combat, so the timer is a prediction: a recast replaces it.
-- Casts are logged to NyteLytePaladinToolkitDB.vigilLog so the real spell
-- and duration can be checked from the saved variables.
-- Fires PK_VIGIL_UPDATED.

local Compat = PK.Compat
local Secrets = PK.Secrets
local Vigil = { state = nil }
PK.Vigil = Vigil

local DEFAULT_DURATION = 30 -- reported; set NyteLytePaladinToolkitDB.vigilDuration to override
local LOG_MAX = 30
local pending -- { target, at } from UNIT_SPELLCAST_SENT

local function log(event, fields)
	local db = PK.db
	if not db then
		return
	end
	db.vigilLog = db.vigilLog or {}
	local row = { t = time(), event = event, inCombat = Compat.InCombat() or nil }
	for k, v in pairs(fields or {}) do
		row[k] = v
	end
	table.insert(db.vigilLog, row)
	while #db.vigilLog > LOG_MAX do
		table.remove(db.vigilLog, 1)
	end
end

local function duration()
	return (PK.db and PK.db.vigilDuration) or DEFAULT_DURATION
end

function Vigil:IsKnown()
	return PK.SpellRegistry:IsKnown("LIGHTS_VIGIL")
end

local function isVigil(spellID)
	local r = PK.SpellRegistry:Get("LIGHTS_VIGIL")
	if not r or not spellID then
		return false
	end
	if r.spellID == spellID or (r.ids and r.ids[spellID]) then
		return true
	end
	local name = Compat.GetSpellName(spellID)
	if type(name) ~= "string" or Compat.IsSecret(name) then
		return false
	end
	if r.name and name == r.name then
		return true
	end
	for _, n in ipairs(PK.Spells.byKey.LIGHTS_VIGIL.names) do
		if n == name then
			return true
		end
	end
	return false
end

-- { name, expires } while active, else nil.
function Vigil:Get()
	local s = self.state
	if s and s.expires > GetTime() then
		return s
	end
	return nil
end

function Vigil:Remaining()
	local s = self:Get()
	return s and (s.expires - GetTime()) or nil
end

PK:RegisterEvent("UNIT_SPELLCAST_SENT", Vigil, function(_, _, unit, target, _, spellID)
	if Compat.IsSecret(unit) or unit ~= "player" then
		return
	end
	local id = Secrets.SafeNumber(spellID)
	if id and isVigil(id) then
		pending = { target = Secrets.SafeString(target), at = GetTime() }
	end
end)

PK:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", Vigil, function(_, _, unit, _, spellID)
	if Compat.IsSecret(unit) or unit ~= "player" then
		return
	end
	local id = Secrets.SafeNumber(spellID)
	if not (id and isVigil(id)) then
		return
	end
	local target = pending and GetTime() - pending.at < 10 and pending.target or nil
	pending = nil
	log("cast", { spellID = id, target = target })
	Vigil.state = { name = (target and target ~= "") and target or "target", expires = GetTime() + duration() }
	PK:Fire("PK_VIGIL_UPDATED")
end)

-- An encounter ending ends whatever was on the boss.
PK:RegisterEvent("ENCOUNTER_END", Vigil, function()
	if Vigil.state then
		Vigil.state = nil
		PK:Fire("PK_VIGIL_UPDATED")
	end
end)
