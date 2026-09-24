local _, PK = ...

-- Group roster for the Blessing Manager: who is in the group, their class,
-- whether they can be buffed right now, and which Blessings they have.
-- Scans only out of combat (group auras are secret in combat); in combat
-- the last scan is kept. Each member's Blessings are kept with their
-- expiration times so the buff button can pick the lowest timer.
-- Fires PK_ROSTER_UPDATED.

local Compat = PK.Compat
local Secrets = PK.Secrets
local Roster = { members = {}, paladins = {} }
PK.Roster = Roster

-- "Blessing of Might" / "Greater Blessing of Might" -> "BLESSING_MIGHT"
local function blessingNameMap()
	local map = {}
	for _, entry in ipairs(PK.Spells.list) do
		local key = entry.category == "blessing" and entry.key or PK.Blessings.GREATER[entry.key]
		if key then
			for _, name in ipairs(entry.names) do
				map[name] = key
			end
			-- Localized name from the player's spellbook, if resolved.
			local r = PK.SpellRegistry:Get(entry.key)
			if r and r.name then
				map[r.name] = key
			end
		end
	end
	return map
end

local function units()
	local list = {}
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	if IsInRaid and IsInRaid() then
		for i = 1, n do
			list[#list + 1] = "raid" .. i
		end
	else
		list[1] = "player"
		if IsInGroup and IsInGroup() then
			for i = 1, 4 do
				list[#list + 1] = "party" .. i
			end
		end
	end
	return list
end

local function safeCall(fn, ...)
	if not fn then
		return nil
	end
	local ok, v = pcall(fn, ...)
	if not ok or Compat.IsSecret(v) then
		return nil
	end
	return v
end

-- Blessings on a unit as { key = expirationTime } (0 = no expiry), or nil
-- if the unit's buffs can't be read.
local function readBlessings(unit, nameMap)
	local list, _, err = Compat.GetAuras(unit, "HELPFUL")
	if err then
		return nil
	end
	local set = {}
	for _, a in ipairs(list) do
		local name = Secrets.SafeString(select(2, Secrets.Field(a, "name")))
		if not name then
			return nil
		end
		local key = nameMap[name]
		if key then
			local exp = Secrets.SafeNumber(select(2, Secrets.Field(a, "expirationTime"))) or 0
			-- Keep the longest copy if the blessing shows up twice.
			if set[key] == nil or exp == 0 or (set[key] ~= 0 and exp > set[key]) then
				set[key] = exp
			end
		end
	end
	return set
end

function Roster:Scan()
	if Compat.InCombat() then
		return false
	end
	local nameMap = blessingNameMap()
	local members, paladins = {}, {}
	for _, unit in ipairs(units()) do
		if safeCall(UnitExists, unit) then
			local name = safeCall(UnitName, unit)
			-- UnitClass returns localized name, token; pcall adds a leading ok flag.
			local _, _, class = pcall(UnitClass, unit)
			class = Secrets.SafeString(class)
			if name and class then
				local online = safeCall(UnitIsConnected, unit) ~= false
				local dead = safeCall(UnitIsDeadOrGhost, unit) == true
				local visible = safeCall(UnitIsVisible, unit) ~= false
				local m = {
					unit = unit,
					name = name,
					class = class,
					online = online,
					dead = dead,
					visible = visible,
					usable = online and not dead and visible,
					buffs = readBlessings(unit, nameMap),
				}
				members[#members + 1] = m
				if class == "PALADIN" then
					paladins[#paladins + 1] = m
				end
			end
		end
	end
	self.members, self.paladins = members, paladins
	PK:Fire("PK_ROSTER_UPDATED")
	return true
end

-- Is `name` (short) the group leader or an assistant?
function Roster:IsLeaderOrAssist(name)
	if not (IsInGroup and IsInGroup()) then
		return name == UnitName("player")
	end
	for _, m in ipairs(self.members) do
		if m.name == name then
			return safeCall(UnitIsGroupLeader, m.unit) == true or safeCall(UnitIsGroupAssistant, m.unit) == true
		end
	end
	return false
end

-- Range check for casting `spellName` on unit: true, false, or nil if unknown.
function Roster:InRange(spellName, unit)
	if unit == "player" then
		return true
	end
	local fn = Compat.Resolve("C_Spell.IsSpellInRange")
	if not fn then
		return nil
	end
	local ok, v = pcall(fn, spellName, unit)
	if not ok or Compat.IsSecret(v) then
		return nil
	end
	return v
end

local function queueScan()
	PK:Debounce("Roster", 0.5, function()
		Roster:Scan()
	end)
end

PK:RegisterEvent("GROUP_ROSTER_UPDATE", Roster, queueScan)
PK:RegisterEvent("PLAYER_REGEN_ENABLED", Roster, queueScan)
PK:RegisterEvent("UNIT_AURA", Roster, function(_, _, unit)
	if Compat.InCombat() or Compat.IsSecret(unit) or type(unit) ~= "string" then
		return
	end
	if unit == "player" or unit:find("^party") or unit:find("^raid") then
		queueScan()
	end
end)
PK:On("PK_READY", Roster, queueScan)
PK:On("PK_SPELLS_UPDATED", Roster, queueScan)
