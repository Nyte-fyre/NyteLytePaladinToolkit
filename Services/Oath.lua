local _, PK = ...

-- Oath of Light (Holy talent): one ally at a time, 5 minutes, boosts your
-- Holy Light on them. Tracks who has yours and for how long:
--  * your casts: UNIT_SPELLCAST_SENT names the target and
--    UNIT_SPELLCAST_SUCCEEDED confirms it, both readable in combat, so a
--    recast mid-fight is followed (marked predicted);
--  * out of combat, the Roster scan finds your Oath on a group member
--    (sourceUnit == "player") and corrects the target and timer, or clears
--    it when the buff is gone.
-- The last events are kept in NyteLytePaladinToolkitDB.oathLog so the real
-- spell, name and duration can be checked from the saved variables.
-- Fires PK_OATH_UPDATED.

local Compat = PK.Compat
local Secrets = PK.Secrets
local Oath = { state = nil }
PK.Oath = Oath

local DEFAULT_DURATION = 300 -- 5 minutes per the talent text; replaced once seen
local LOG_MAX = 40
local pending -- { target, at } from UNIT_SPELLCAST_SENT

local function log(event, fields)
	local db = PK.db
	if not db then
		return
	end
	db.oathLog = db.oathLog or {}
	local row = { t = time(), event = event, inCombat = Compat.InCombat() or nil }
	for k, v in pairs(fields or {}) do
		row[k] = v
	end
	table.insert(db.oathLog, row)
	while #db.oathLog > LOG_MAX do
		table.remove(db.oathLog, 1)
	end
end

local function duration()
	return (PK.db and PK.db.oathDuration) or DEFAULT_DURATION
end

function Oath:IsKnown()
	return PK.SpellRegistry:IsKnown("OATH_OF_LIGHT")
end

-- Is this cast your Oath of Light? (any rank's ID, else the spell's name)
local function isOath(spellID)
	local r = PK.SpellRegistry:Get("OATH_OF_LIGHT")
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
	for _, n in ipairs(PK.Spells.byKey.OATH_OF_LIGHT.names) do
		if n == name then
			return true
		end
	end
	return false
end

-- The roster member a cast target name refers to. Cast targets can be the
-- first part of a two-part Forever name ("Nyte" for "Nyte Fyre").
local function memberByName(name)
	if not name then
		return nil
	end
	for _, m in ipairs(PK.Roster.members) do
		if m.name == name or m.name:sub(1, #name + 1) == name .. " " then
			return m
		end
	end
	return nil
end

local function set(state)
	Oath.state = state
	PK:Fire("PK_OATH_UPDATED")
end

-- { name, guid, expires, source = "cast" | "aura" } while active, else nil.
function Oath:Get()
	local s = self.state
	if s and (s.expires == 0 or s.expires > GetTime()) then
		return s
	end
	return nil
end

function Oath:Remaining()
	local s = self:Get()
	if not s then
		return nil
	end
	return s.expires == 0 and math.huge or s.expires - GetTime()
end

-- Members the game reports as tanks (roles may be unset: then none).
function Oath:Tanks()
	local out = {}
	for _, m in ipairs(PK.Roster.members) do
		if m.role == "TANK" then
			out[#out + 1] = m
		end
	end
	return out
end

function Oath:IsOnTank()
	local s = self:Get()
	if not s then
		return false
	end
	for _, m in ipairs(self:Tanks()) do
		if (s.guid and m.guid == s.guid) or m.name == s.name then
			return true
		end
	end
	return false
end

function Oath:InGroup()
	return (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) or false
end

-- Casts -----------------------------------------------------------------------------------

PK:RegisterEvent("UNIT_SPELLCAST_SENT", Oath, function(_, _, unit, target, _, spellID)
	if Compat.IsSecret(unit) or unit ~= "player" then
		return
	end
	local id = Secrets.SafeNumber(spellID)
	if id and isOath(id) then
		pending = { target = Secrets.SafeString(target), at = GetTime() }
		log("sent", { spellID = id, target = pending.target })
	end
end)

PK:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", Oath, function(_, _, unit, _, spellID)
	if Compat.IsSecret(unit) or unit ~= "player" then
		return
	end
	local id = Secrets.SafeNumber(spellID)
	if not (id and isOath(id)) then
		return
	end
	local target = pending and GetTime() - pending.at < 10 and pending.target or nil
	pending = nil
	local m = memberByName(target)
	log("cast", { spellID = id, target = target, matched = m and m.name or nil })
	set({
		name = (m and m.name) or target or "?",
		guid = m and m.guid,
		expires = GetTime() + duration(),
		source = "cast",
	})
end)

-- Out-of-combat confirmation from the group scan -------------------------------------------

PK:On("PK_ROSTER_UPDATED", Oath, function()
	if Compat.InCombat() or not Oath:IsKnown() then
		return
	end
	for _, m in ipairs(PK.Roster.members) do
		local o = m.myOath
		if o then
			if o.duration and o.duration > 0 and PK.db and PK.db.oathDuration ~= o.duration then
				PK.db.oathDuration = o.duration
				log("duration", { duration = o.duration, spellID = o.spellID })
			end
			local s = Oath.state
			if not s or s.guid ~= m.guid or s.source ~= "aura" then
				log("seen", { target = m.name, role = m.role, spellID = o.spellID,
					left = o.expirationTime > 0 and math.floor(o.expirationTime - GetTime()) or 0 })
			end
			set({ name = m.name, guid = m.guid, expires = o.expirationTime, source = "aura" })
			return
		end
	end
	-- Nobody has it. Clear only when we can tell: the target is in the group
	-- with readable buffs, or isn't in the group anymore.
	local s = Oath:Get()
	if s then
		local m = (s.guid and PK.Roster:Find(s.guid)) or memberByName(s.name)
		if not m or m.buffs ~= nil then
			log("gone", { target = s.name, reason = m and "buff missing" or "left group" })
			set(nil)
		end
	end
end)

PK:RegisterCommand("oath", function()
	if not Oath:IsKnown() then
		PK:Print("Oath of Light isn't learned on this character (it's a Holy talent).")
		return
	end
	local s = Oath:Get()
	local tanks = {}
	for _, m in ipairs(Oath:Tanks()) do
		tanks[#tanks + 1] = m.name
	end
	local tankText = #tanks > 0 and table.concat(tanks, ", ") or "none set (roles not assigned)"
	if s then
		local left = Oath:Remaining()
		PK:Print(string.format("Oath of Light is on %s%s, %s left. Tank: %s.", s.name,
			s.source == "cast" and " (from your cast*)" or "",
			left == math.huge and "no timer" or (math.floor(left / 60) .. "m " .. math.floor(left % 60) .. "s"),
			tankText))
	else
		PK:Print("no Oath of Light active. Tank: " .. tankText .. ".")
	end
end, "show who has your Oath of Light")
