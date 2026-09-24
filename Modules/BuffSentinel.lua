local _, PK = ...

-- Buff Sentinel: "what am I missing?" A row of icons for your own Seal,
-- Paladin aura, Righteous Fury (per spec) and a Blessing. By default only
-- problems show: missing (grey with a red border) or expiring soon
-- (pulsing, with time left). In combat it keeps the last known state (see
-- AuraService); a Seal it can't see in combat shows as "unknown" instead of
-- raising a false alarm. `/ptk check` prints the same checks to chat, and a
-- ready check does it automatically.

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
-- Each: { id, label, status = ok|expiring|missing|unknown, aura, icon, remaining }
function M:Evaluate()
	local s = settings()
	local spec = PK.SpecProfile:GetSpec()
	local threshold = PK.profile.alerts.expiringThresholdSec or 120
	local results = {}

	local function add(id, label, aura, fallbackIcon, long, unknownWhenFrozen)
		local remaining = AS:Remaining(aura)
		local status
		if aura and remaining then
			status = (long and remaining < threshold) and "expiring" or "ok"
		elseif unknownWhenFrozen and AS.frozen then
			status = "unknown"
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
	if s.checkAura and knowsAny("aura") then
		add("aura", "Aura", (AS:GetPaladinAura()), registryIcon("AURA_DEVOTION"), false, false)
	end
	if s.rfSpecs[spec] and PK.SpellRegistry:IsKnown("RIGHTEOUS_FURY") then
		add("rf", "Righteous Fury", AS:GetByKey("RIGHTEOUS_FURY"), registryIcon("RIGHTEOUS_FURY"), true, false)
	end
	if s.checkBlessing and knowsAny("blessing") then
		add("blessing", "Blessing", AS:GetBlessing(), registryIcon("BLESSING_MIGHT"), true, false)
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
		if s.showAll or r.status == "missing" or r.status == "expiring" then
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
		elseif r.status == "unknown" then
			icon:SetState("unusable")
		else
			icon:SetState("ready")
		end
		icon:SetText(r.status == "expiring" and formatTime(r.remaining) or "")
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
		elseif r.status == "unknown" then
			text = "|cff909090can't see in combat|r"
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
