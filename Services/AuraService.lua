local _, PK = ...

-- The one place that reads the player's own buffs.
--
-- Probe #1 showed Forever returns nothing for the player's auras in combat,
-- so this keeps a snapshot:
--  * Out of combat it rescans on every UNIT_AURA (fully readable).
--  * In combat, if a scan comes back empty or secret, the snapshot is
--    "frozen": the last known buffs are kept, and their timers keep
--    counting down from the expiration times read before combat.
--  * While frozen, the player's own casts (readable in combat, probe #2)
--    update predictions: Seal, Righteous Fury, Twist of Light Echo, Iron
--    Creed. The active Paladin aura comes from the stance bar, which stays
--    readable in combat.
-- Fires PK_AURAS_UPDATED after every change.

local Compat = PK.Compat
local Secrets = PK.Secrets
local AS = { auras = {}, frozen = false }
PK.AuraService = AS

-- Durations learned from readable auras, used for predictions in combat.
local learnedDuration = {}
local DEFAULT_SEAL_DURATION = 30

local function readAura(a)
	local name = Secrets.SafeString(select(2, Secrets.Field(a, "name")))
	local spellID = Secrets.SafeNumber(select(2, Secrets.Field(a, "spellId")))
	if not name or not spellID then
		return nil
	end
	local duration = Secrets.SafeNumber(select(2, Secrets.Field(a, "duration"))) or 0
	local expiration = Secrets.SafeNumber(select(2, Secrets.Field(a, "expirationTime"))) or 0
	return {
		name = name,
		spellID = spellID,
		icon = Secrets.SafeNumber(select(2, Secrets.Field(a, "icon"))),
		duration = duration,
		expirationTime = expiration, -- 0 = no expiry
		instanceID = Secrets.SafeNumber(select(2, Secrets.Field(a, "auraInstanceID"))),
		fromPlayer = Secrets.SafeBool(select(2, Secrets.Field(a, "isFromPlayerOrPlayerPet"))),
	}
end

-- Rescans the player's buffs. Returns true if the result was trusted.
function AS:Scan()
	-- In combat Forever refuses aura reads outright ("Auras cannot be accessed
	-- when secret"), so skip the call when the client says auras are secret.
	if Compat.InCombat() and Compat.AurasAreSecret() then
		if not self.frozen then
			self.frozen = true
			PK:Debug("AuraService: frozen (auras secret)")
		end
		self.stanceSpellID = Compat.GetActiveStanceSpell()
		PK:Fire("PK_AURAS_UPDATED")
		return false
	end
	local list = Compat.GetAuras("player", "HELPFUL")
	local auras, unreadable = {}, 0
	for _, a in ipairs(list) do
		local aura = readAura(a)
		if aura then
			auras[#auras + 1] = aura
			if aura.duration > 0 then
				learnedDuration[aura.spellID] = aura.duration
			end
		else
			unreadable = unreadable + 1
		end
	end
	local inCombat = Compat.InCombat()
	-- In combat an empty or partly secret result means "can't see", not "no buffs".
	if inCombat and (#auras == 0 or unreadable > 0) then
		if not self.frozen then
			self.frozen = true
			PK:Debug("AuraService: frozen (%d readable, %d unreadable)", #auras, unreadable)
		end
	else
		self.auras = auras
		self.frozen = false
		self.predictedSeal = nil
		self.echo = nil
		self.ironCreed = nil
	end
	self.stanceSpellID = Compat.GetActiveStanceSpell()
	PK:Fire("PK_AURAS_UPDATED")
	return not self.frozen
end

-- Seconds left on an aura, math.huge for no expiry, or nil if expired.
function AS:Remaining(aura)
	if not aura then
		return nil
	end
	if not aura.expirationTime or aura.expirationTime == 0 then
		return math.huge
	end
	local left = aura.expirationTime - GetTime()
	if left <= 0 then
		return nil
	end
	return left
end

-- First current aura matching predicate(aura), skipping expired ones.
function AS:Find(predicate)
	for _, aura in ipairs(self.auras) do
		if self:Remaining(aura) and predicate(aura) then
			return aura
		end
	end
	return nil
end

function AS:FindBySpellIDs(ids)
	return self:Find(function(a)
		return ids[a.spellID] == true
	end)
end

function AS:FindByNamePrefix(prefix)
	return self:Find(function(a)
		return a.name:sub(1, #prefix) == prefix
	end)
end

-- Registry keys in `category` -> set of the player's spell IDs for them.
local function idsForCategory(category)
	local ids = {}
	for _, r in pairs(PK.SpellRegistry.byKey) do
		if r.category == category and r.spellID then
			ids[r.spellID] = true
		end
	end
	return ids
end
AS.IdsForCategory = idsForCategory

-- The active Seal: the real aura when readable, else the in-combat prediction.
function AS:GetSeal()
	local aura = self:FindBySpellIDs(idsForCategory("seal")) or self:FindByNamePrefix("Seal of ")
	if aura then
		return aura, "aura"
	end
	local p = self.predictedSeal
	if p and self:Remaining(p) then
		return p, "predicted"
	end
	return nil
end

-- The active Paladin aura: stance bar first (readable in combat), then buffs.
function AS:GetPaladinAura()
	local stance = self.stanceSpellID
	if stance then
		local info = Compat.GetSpellInfo(stance)
		return {
			name = info and info.name or "?",
			spellID = stance,
			icon = info and info.iconID,
			duration = 0,
			expirationTime = 0,
		}, "stance"
	end
	local aura = self:FindBySpellIDs(idsForCategory("aura"))
	if aura then
		return aura, "aura"
	end
	return nil
end

-- Any Blessing on the player (from anyone, any rank).
function AS:GetBlessing()
	return self:FindByNamePrefix("Blessing of ") or self:FindByNamePrefix("Greater Blessing of ")
end

function AS:GetByKey(key)
	local r = PK.SpellRegistry:Get(key)
	if not r or not r.spellID then
		return nil
	end
	return self:Find(function(a)
		return a.spellID == r.spellID or a.name == r.name
	end)
end

-- Events --------------------------------------------------------------------------------------

local function queueScan()
	PK:Debounce("AuraService", 0.1, function()
		AS:Scan()
	end)
end

PK:RegisterEvent("UNIT_AURA", AS, function(_, _, unit)
	if not Compat.IsSecret(unit) and unit == "player" then
		queueScan()
	end
end)

-- Predictions while blind ------------------------------------------------------------------
-- Forever hides your buffs in combat but not your own casts (probe #2), so
-- casts update the frozen snapshot: a new Seal replaces the old one,
-- Righteous Fury is refreshed, Twist of Light's Echo and Iron Creed are
-- inferred from the rules in their tooltips. Predicted auras carry
-- predicted = true and are shown with a * by the modules.

-- Unverified Forever durations; replaced by the real ones once seen out of combat.
local DEFAULT_DURATION = { TWIST_ECHO = 10, IRON_CREED = 6 }

-- Seals whose replacement grants Twist of Light's Echo (Ret talent).
local TWISTABLE = { SEAL_COMMAND = true, SEAL_RIGHTEOUSNESS = true, SEAL_FURY = true, SEAL_JUSTICE = true }

local function registryKeyFor(spellID)
	for key, r in pairs(PK.SpellRegistry.byKey) do
		if r.spellID == spellID then
			return key, r
		end
	end
	return nil
end

local function predictedAura(spellID, name, icon, durationKey)
	local duration = learnedDuration[spellID] or DEFAULT_DURATION[durationKey or ""] or DEFAULT_SEAL_DURATION
	return {
		name = name or "?",
		spellID = spellID,
		icon = icon,
		duration = duration,
		expirationTime = GetTime() + duration,
		predicted = true,
	}
end

local function removeWhere(predicate)
	for i = #AS.auras, 1, -1 do
		if predicate(AS.auras[i]) then
			table.remove(AS.auras, i)
		end
	end
end

function AS:PredictCast(spellID)
	local key, r = registryKeyFor(spellID)
	if not key then
		return false
	end
	local info = Compat.GetSpellInfo(spellID)
	local name, icon = (info and info.name) or r.name, (info and info.iconID) or r.icon
	local registry = PK.SpellRegistry

	if r.category == "seal" then
		local previous = self:GetSeal()
		local seals = idsForCategory("seal")
		removeWhere(function(a)
			return seals[a.spellID] or a.name:sub(1, 8) == "Seal of "
		end)
		self.predictedSeal = predictedAura(spellID, name, icon)
		-- Twist of Light: swapping away from a twistable Seal grants Echo.
		if previous and previous.spellID ~= spellID and registry:IsKnown("TWIST_OF_LIGHT") then
			local prevKey = registryKeyFor(previous.spellID)
			if prevKey and TWISTABLE[prevKey] then
				local echo = registry:Get("TWIST_ECHO")
				self.echo = predictedAura(echo and echo.spellID or 0, "Echo", previous.icon, "TWIST_ECHO")
				self.echo.replacedSeal = previous.name
			end
		end
		return true
	elseif key == "RIGHTEOUS_FURY" then
		removeWhere(function(a)
			return a.spellID == spellID
		end)
		self.auras[#self.auras + 1] = predictedAura(spellID, name, icon)
		return true
	elseif key == "HOLY_STRIKE" and registry:IsKnown("IRON_CREED") and self:GetByKey("RIGHTEOUS_FURY") then
		-- Iron Creed: Holy Strike with Righteous Fury active grants damage reduction.
		local ic = registry:Get("IRON_CREED")
		self.ironCreed = predictedAura(ic.spellID, ic.name or "Iron Creed", ic.icon, "IRON_CREED")
		return true
	end
	return false
end

-- Twist of Light's Echo: the real buff when readable, else the prediction.
-- The returned aura has replacedSeal when predicted.
function AS:GetEcho()
	local aura = self:GetByKey("TWIST_ECHO")
	if aura then
		return aura, "aura"
	end
	if self.echo and self:Remaining(self.echo) then
		return self.echo, "predicted"
	end
	return nil
end

function AS:GetIronCreed()
	local aura = self:GetByKey("IRON_CREED")
	if aura then
		return aura, "aura"
	end
	if self.ironCreed and self:Remaining(self.ironCreed) then
		return self.ironCreed, "predicted"
	end
	return nil
end

PK:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", AS, function(_, _, unit, _, spellID)
	if Compat.IsSecret(unit) or unit ~= "player" or not AS.frozen then
		return
	end
	local id = Secrets.SafeNumber(spellID)
	if id and AS:PredictCast(id) then
		PK:Fire("PK_AURAS_UPDATED")
	end
end)

PK:RegisterEvent("UPDATE_SHAPESHIFT_FORM", AS, queueScan)
PK:RegisterEvent("PLAYER_REGEN_ENABLED", AS, queueScan)
PK:RegisterEvent("PLAYER_REGEN_DISABLED", AS, queueScan)
PK:RegisterEvent("PLAYER_ENTERING_WORLD", AS, queueScan)
PK:On("PK_READY", AS, function()
	AS:Scan()
end)
PK:On("PK_SPELLS_UPDATED", AS, queueScan)
