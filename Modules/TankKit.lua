local _, PK = ...

-- Tank Kit (Protection preset, can be turned on for any spec):
--  * A big, flashing Righteous Fury warning while it's missing, plus a sound
--    on zone-in and ready checks.
--  * Large cooldown icons for the tanking core: Judgement (labelled TAUNT
--    while Seal of Fury is active, since Judgement taunts then), Consecration,
--    Holy Strike, Hammer of Justice, Templar's Bulwark. State display only.
--  * Iron Creed (Holy Strike with Righteous Fury: damage reduction) with time
--    left, from the buff out of combat or predicted from your cast in combat.
-- No threat display: threat is restricted on Forever.

local AS = PK.AuraService
local Frames = PK.Frames
local M = PK:RegisterModule("TankKit", {})

local icons = {}
local warning, ironCreedIcon, ticker

local function settings()
	return PK.Config:GetModuleSettings("TankKit")
end

local function rfMissing()
	return PK.SpellRegistry:IsKnown("RIGHTEOUS_FURY") and AS:GetByKey("RIGHTEOUS_FURY") == nil
end

local function sealOfFuryActive()
	local seal = AS:GetSeal()
	local sof = PK.SpellRegistry:Get("SEAL_FURY")
	return seal ~= nil and sof ~= nil and (seal.spellID == sof.spellID or seal.name == sof.name)
end

local function buildWarning(anchor)
	warning = CreateFrame("Frame", nil, anchor)
	warning:SetSize(360, 40)
	warning:SetPoint("BOTTOM", anchor, "TOP", 0, 10)
	local icon = warning:CreateTexture(nil, "ARTWORK")
	icon:SetSize(36, 36)
	icon:SetPoint("LEFT")
	warning.icon = icon
	local text = warning:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	text:SetTextColor(1, 0.2, 0.2)
	text:SetText("RIGHTEOUS FURY MISSING")
	if warning.CreateAnimationGroup then
		local ag = warning:CreateAnimationGroup()
		if ag then
			ag:SetLooping("BOUNCE")
			local a = ag:CreateAnimation("Alpha")
			a:SetFromAlpha(1)
			a:SetToAlpha(0.3)
			a:SetDuration(0.5)
			warning.flash = ag
		end
	end
	warning:Hide()
end

local function tauntLabel(icon)
	if not icon.label then
		icon.label = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		icon.label:SetPoint("BOTTOM", icon, "TOP", 0, 2)
		icon.label:SetTextColor(1, 0.82, 0)
	end
	return icon.label
end

function M:Rebuild()
	if not self.enabled then
		return
	end
	local s = settings()
	local anchor = Frames:GetAnchor("TankKit")
	if not warning then
		buildWarning(anchor)
	end
	for _, icon in ipairs(icons) do
		if icon.label then
			icon.label:SetText("")
		end
		Frames:ReleaseIcon(icon)
	end
	icons = {}
	local size = s.iconSize or 44
	for _, key in ipairs(s.spells) do
		local r = PK.SpellRegistry:Get(key)
		if r and r.known and r.spellID then
			local icon = Frames:AcquireIcon(anchor, size)
			icon:SetSpell(r.spellID)
			icon.key = key
			icon.cooldown:SetHideCountdownNumbers(false)
			icon:SetPoint("LEFT", anchor, "LEFT", #icons * (size + 6), 0)
			icons[#icons + 1] = icon
		end
	end
	if not ironCreedIcon then
		ironCreedIcon = Frames:AcquireIcon(anchor, size)
	end
	ironCreedIcon:SetSize(size, size)
	ironCreedIcon:ClearAllPoints()
	ironCreedIcon:SetPoint("LEFT", anchor, "LEFT", #icons * (size + 6) + 10, 0)
	anchor:SetSize(math.max(160, (#icons + 1) * (size + 6) + 10), size)
	self:Update()
end

function M:Update()
	if not self.enabled then
		return
	end
	local s = settings()
	local taunt = sealOfFuryActive()
	for _, icon in ipairs(icons) do
		icon:RefreshCooldown(true)
		if icon.key == "JUDGEMENT" then
			tauntLabel(icon):SetText(taunt and "TAUNT" or "")
		end
	end
	self:UpdateAuras(s)
end

function M:UpdateAuras(s)
	s = s or settings()
	-- Righteous Fury warning
	if warning then
		if s.rfWarning and rfMissing() then
			local rf = PK.SpellRegistry:Get("RIGHTEOUS_FURY")
			warning.icon:SetTexture(rf and rf.icon or 134400)
			warning:Show()
			if warning.flash and not warning.flash:IsPlaying() then
				warning.flash:Play()
			end
		else
			if warning.flash then
				warning.flash:Stop()
			end
			warning:Hide()
		end
	end
	-- Iron Creed
	if ironCreedIcon then
		local ic, source = AS:GetIronCreed()
		if s.showIronCreed and ic then
			ironCreedIcon.icon:SetTexture(ic.icon or 134400)
			ironCreedIcon:SetState("ready")
			local left = AS:Remaining(ic)
			local text = (left and left ~= math.huge) and string.format("%.0f", left) or ""
			ironCreedIcon:SetText(text .. (source == "predicted" and "*" or ""))
			ironCreedIcon:Show()
		else
			ironCreedIcon:Hide()
		end
	end
end

local function rfReminder(reason)
	if not (M.enabled and settings().rfSound and rfMissing()) then
		return
	end
	PK:Print(reason .. ": |cffff4040Righteous Fury is not active.|r")
	PK.Compat.PlaySound("RAID_WARNING", 8959)
end

function M:OnEnable()
	local function rebuild()
		M:Rebuild()
	end
	local function update()
		M:Update()
	end
	PK:On("PK_SPELLS_UPDATED", self, rebuild)
	PK:On("PK_PROFILE_CHANGED", self, rebuild)
	PK:On("PK_SETTINGS_CHANGED", self, rebuild)
	PK:On("PK_AURAS_UPDATED", self, update)
	for _, ev in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "PLAYER_REGEN_ENABLED",
		"PLAYER_REGEN_DISABLED" }) do
		PK:RegisterEvent(ev, self, update)
	end
	PK:RegisterEvent("READY_CHECK", self, function()
		rfReminder("Ready check")
	end)
	PK:RegisterEvent("PLAYER_ENTERING_WORLD", self, function()
		-- Give auras a moment to load after a zone change.
		C_Timer.After(3, function()
			rfReminder("Zoned in")
		end)
	end)
	if C_Timer.NewTicker then
		ticker = C_Timer.NewTicker(0.25, function()
			M:UpdateAuras()
		end)
	end
	self:Rebuild()
end

function M:OnDisable()
	PK:Off("PK_SPELLS_UPDATED", self)
	PK:Off("PK_PROFILE_CHANGED", self)
	PK:Off("PK_SETTINGS_CHANGED", self)
	PK:Off("PK_AURAS_UPDATED", self)
	for _, ev in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "PLAYER_REGEN_ENABLED",
		"PLAYER_REGEN_DISABLED", "READY_CHECK", "PLAYER_ENTERING_WORLD" }) do
		PK:UnregisterEvent(ev, self)
	end
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	for _, icon in ipairs(icons) do
		if icon.label then
			icon.label:SetText("")
		end
		Frames:ReleaseIcon(icon)
	end
	icons = {}
	if ironCreedIcon then
		Frames:ReleaseIcon(ironCreedIcon)
		ironCreedIcon = nil
	end
	if warning then
		if warning.flash then
			warning.flash:Stop()
		end
		warning:Hide()
	end
end

function M:OnSpecChanged()
	self:Rebuild()
end

-- For tests and debugging.
function M:State()
	return {
		icons = #icons,
		warningShown = warning ~= nil and warning:IsShown() == true,
		taunt = sealOfFuryActive(),
		ironCreed = ironCreedIcon ~= nil and ironCreedIcon:IsShown() == true,
	}
end
