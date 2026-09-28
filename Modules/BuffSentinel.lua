local _, PK = ...

-- Buff Sentinel: "what am I missing?" A row of icons for your own Seal,
-- Paladin aura, Righteous Fury (per spec) and a Blessing. By default only
-- problems show: missing (grey with a red border) or expiring soon
-- (pulsing, with time left). In combat it keeps the last known state (see
-- AuraService). A missing Seal only matters in combat (owner's call), so out
-- of combat it's "idle" and not shown; in combat your own casts are readable,
-- so a missing Seal there is real. `/ptk check` prints the same checks to
-- chat, and a ready check does it automatically.

local AS = PK.AuraService
local Frames = PK.Frames
local M = PK:RegisterModule("BuffSentinel", {})

local SOUND_THROTTLE = 15
local lastSound = 0
local lastStatus = {}
local icons = {}
local ticker

local function settings()
	return PK.Config:GetModuleSettings("BuffSentinel")
end

local function registryIcon(key)
	local r = PK.SpellRegistry:Get(key)
	return r and r.icon
end

local function knowsAny(category)
	for _, r in pairs(PK.SpellRegistry.byKey) do
		if r.category == category and r.known then
			return true
		end
	end
	return false
end

local function formatTime(sec)
	if not sec or sec == math.huge then
		return ""
	elseif sec >= 60 then
		return math.floor(sec / 60 + 0.5) .. "m"
	end
	return math.floor(sec) .. "s"
end

-- Builds the list of checks for the current spec.
-- Each: { id, label, status = ok|expiring|missing|idle, aura, icon, remaining }
-- ("idle": not checked right now, e.g. the Seal out of combat)
function M:Evaluate()
	local s = settings()
	local spec = PK.SpecProfile:GetSpec()
	local threshold = PK.profile.alerts.expiringThresholdSec or 120
	local results = {}

	local inCombat = PK.Compat.InCombat()
	local function add(id, label, aura, fallbackIcon, long, combatOnly)
		local remaining = AS:Remaining(aura)
		local status
		if aura and remaining then
			status = (long and remaining < threshold) and "expiring" or "ok"
		elseif combatOnly and not inCombat then
			status = "idle"
		else
			status = "missing"
		end
		results[#results + 1] = {
			id = id,
			label = label,
			status = status,
			aura = aura,
			icon = (aura and aura.icon) or fallbackIcon,
			remaining = remaining,
		}
	end

	if s.checkSeal and knowsAny("seal") then
		local seal = AS:GetSeal()
		add("seal", "Seal", seal, registryIcon("SEAL_RIGHTEOUSNESS"), false, true)
	end
	-- Your own row in the Blessing grid, only if one really exists (set by
	-- you, Auto-suggest or your leader). No row: nothing to compare against.
	local myRow, myId = nil, PK.Compat.UnitGUID("player")
	if myId and PK.profile.blessing and PK.profile.blessing.assignments then
		myRow = PK.profile.blessing.assignments[myId]
	end

	if s.checkAura and knowsAny("aura") then
		local current = AS:GetPaladinAura()
		local assigned = myRow and myRow.aura
		local assignedEntry = assigned and PK.Spells.byKey[assigned]
		local assignedName = assignedEntry and (PK.SpellRegistry:Get(assigned) or {}).name or
			(assignedEntry and assignedEntry.names[1])
		if current and assignedName and current.name ~= assignedName then
			-- Running an Aura, but not the assigned one: yellow, showing the one to switch to.
			results[#results + 1] = {
				id = "aura",
				label = "Aura",
				status = "wrong",
				aura = current,
				icon = registryIcon(assigned) or current.icon,
				detail = current.name .. " active, assigned: " .. assignedName,
			}
		else
			add("aura", "Aura", current, (assigned and registryIcon(assigned)) or registryIcon("AURA_DEVOTION"), false, false)
		end
	end
	if s.checkDuplicateAura and not inCombat then
		local dup = AS:GetDuplicateAura()
		if dup then
			-- Forever hides who cast other players' buffs, so usually unknown.
			local who = (dup.source and PK.Compat.UnitDisplayName(dup.source)) or "another paladin"
			results[#results + 1] = {
				id = "auraDup",
				label = "Aura",
				status = "duplicate",
				aura = dup,
				icon = dup.icon,
				other = who,
			}
		end
	end
	if s.rfSpecs[spec] and PK.SpellRegistry:IsKnown("RIGHTEOUS_FURY") then
		add("rf", "Righteous Fury", AS:GetByKey("RIGHTEOUS_FURY"), registryIcon("RIGHTEOUS_FURY"), true, false)
	end
	if s.checkBlessing and knowsAny("blessing") then
		local _, myClass = UnitClass("player")
		local expected = myRow and PK.Blessings.AssignedFor({ [myId] = myRow }, myId, myClass, myId)
		if expected then
			-- Your row says which Blessing you give yourself.
			local aura = AS:GetBlessingByKey(expected)
			local entry = PK.Spells.byKey[expected]
			local fallback = registryIcon(expected) or registryIcon("BLESSING_MIGHT")
			if aura and not AS.IsMine(aura) and AS:Remaining(aura) then
				-- It's there, but another paladin cast it: yellow.
				results[#results + 1] = {
					id = "blessing",
					label = "Blessing",
					status = "wrong",
					aura = aura,
					icon = aura.icon or fallback,
					remaining = AS:Remaining(aura),
					detail = (entry and entry.names[1] or "Blessing") .. " is from another paladin, not you",
				}
			else
				add("blessing", "Blessing", aura, fallback, true, false)
			end
		else
			add("blessing", "Blessing", AS:GetBlessing(), registryIcon("BLESSING_MIGHT"), true, false)
		end
	end
	return results
end

local function pulse(icon, on)
	if on then
		if not icon.pulse and icon.CreateAnimationGroup then
			local ag = icon:CreateAnimationGroup()
			if ag then
				ag:SetLooping("BOUNCE")
				local a = ag:CreateAnimation("Alpha")
				a:SetFromAlpha(1)
				a:SetToAlpha(0.35)
				a:SetDuration(0.6)
				icon.pulse = ag
			end
		end
		if icon.pulse and not icon.pulse:IsPlaying() then
			icon.pulse:Play()
		end
	elseif icon.pulse then
		icon.pulse:Stop()
		icon:SetAlpha(1)
	end
end

function M:Render()
	if not self.enabled then
		return
	end
	local s = settings()
	local results = self:Evaluate()
	local anchor = Frames:GetAnchor("BuffSentinel")
	local size = s.iconSize or 32

	local shown = {}
	for _, r in ipairs(results) do
		if (s.showAll and r.status ~= "idle") or r.status == "missing" or r.status == "expiring"
			or r.status == "duplicate" or r.status == "wrong" then
			shown[#shown + 1] = r
		end
	end

	for i, r in ipairs(shown) do
		local icon = icons[i]
		if not icon then
			icon = Frames:AcquireIcon(anchor, size)
			icons[i] = icon
		end
		icon:SetSize(size, size)
		icon:ClearAllPoints()
		icon:SetPoint("LEFT", anchor, "LEFT", (i - 1) * (size + 4), 0)
		icon.icon:SetTexture(r.icon or 134400)
		if r.status == "missing" then
			icon:SetState("missing")
		elseif r.status == "wrong" then
			icon:SetState("wrong")
		else
			icon:SetState("ready")
		end
		if r.status == "duplicate" then
			icon:SetText("2x")
		else
			icon:SetText(r.status == "expiring" and formatTime(r.remaining) or "")
		end
		pulse(icon, r.status == "expiring")
		icon:Show()
	end
	for i = #shown + 1, #icons do
		pulse(icons[i], false)
		icons[i]:Hide()
	end
	anchor:SetSize(math.max(160, #shown * (size + 4)), size)

	-- Sound when something newly goes missing (out of combat only).
	local newlyMissing = false
	for _, r in ipairs(results) do
		if r.status == "missing" and lastStatus[r.id] and lastStatus[r.id] ~= "missing" then
			newlyMissing = true
		end
		lastStatus[r.id] = r.status
	end
	if newlyMissing and PK.profile.alerts.sound and not PK.Compat.InCombat() and GetTime() - lastSound > SOUND_THROTTLE then
		lastSound = GetTime()
		PK.Compat.PlaySound("RAID_WARNING", 8959)
	end
end

-- Prints every check to chat. Returns the number of problems.
function M:PrintCheck(reason)
	local results = self:Evaluate()
	local problems = 0
	local parts = {}
	for _, r in ipairs(results) do
		local text
		if r.status == "ok" then
			text = "|cff40ff40" .. (r.aura and r.aura.name or "ok") .. "|r"
		elseif r.status == "expiring" then
			problems = problems + 1
			text = "|cffffd040" .. (r.aura and r.aura.name or "?") .. " (" .. formatTime(r.remaining) .. " left)|r"
		elseif r.status == "idle" then
			text = "|cff909090checked in combat|r"
		elseif r.status == "wrong" then
			problems = problems + 1
			text = "|cffffd940" .. tostring(r.detail) .. "|r"
		elseif r.status == "duplicate" then
			problems = problems + 1
			text = "|cffffd040" .. (r.aura and r.aura.name or "?") .. " is also running from " .. tostring(r.other)
				.. " (they don't stack)|r"
		else
			problems = problems + 1
			text = "|cffff4040missing|r"
		end
		parts[#parts + 1] = r.label .. ": " .. text
	end
	if #parts == 0 then
		PK:Print((reason or "check") .. ": nothing to check yet (no Seals, Auras or Blessings learned).")
	else
		PK:Print((reason or "check") .. ": " .. table.concat(parts, ", "))
	end
	return problems
end

function M:OnEnable()
	local function render()
		M:Render()
	end
	PK:On("PK_AURAS_UPDATED", self, render)
	PK:On("PK_SPELLS_UPDATED", self, render)
	PK:On("PK_PROFILE_CHANGED", self, render)
	PK:On("PK_SETTINGS_CHANGED", self, render)
	PK:RegisterEvent("PLAYER_REGEN_DISABLED", self, render)
	PK:RegisterEvent("PLAYER_REGEN_ENABLED", self, render)
	PK:RegisterEvent("READY_CHECK", self, function()
		if M:PrintCheck("ready check") > 0 and PK.profile.alerts.sound then
			PK.Compat.PlaySound("RAID_WARNING", 8959)
		end
	end)
	if C_Timer.NewTicker then
		ticker = C_Timer.NewTicker(1, render)
	end
	Frames:GetAnchor("BuffSentinel"):Show()
	self:Render()
end

function M:OnDisable()
	PK:Off("PK_AURAS_UPDATED", self)
	PK:Off("PK_SPELLS_UPDATED", self)
	PK:Off("PK_PROFILE_CHANGED", self)
	PK:Off("PK_SETTINGS_CHANGED", self)
	PK:UnregisterEvent("READY_CHECK", self)
	PK:UnregisterEvent("PLAYER_REGEN_DISABLED", self)
	PK:UnregisterEvent("PLAYER_REGEN_ENABLED", self)
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	for _, icon in ipairs(icons) do
		pulse(icon, false)
		Frames:ReleaseIcon(icon)
	end
	icons = {}
end

function M:OnSpecChanged()
	self:Render()
end

PK:RegisterCommand("check", function()
	M:PrintCheck("check")
end, "check your Seal, Aura, Blessing and Righteous Fury now")
