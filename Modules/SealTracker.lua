local _, PK = ...

-- Seal Tracker: your active Seal with a draining time bar. Durations come
-- from the aura itself (never hardcoded). In combat it shows the Seal
-- predicted from your own cast (marked with *) while buffs can't be read.
-- Judgement no longer consumes Seals in Forever, so there is no
-- "consumed" state. Holy defaults to a smaller frame (layout scale 0.8).

local AS = PK.AuraService
local Frames = PK.Frames
local M = PK:RegisterModule("SealTracker", {})

local BAR_WIDTH = 130
local container, icon, bar, nameText, timeText
local current

local function settings()
	return PK.Config:GetModuleSettings("SealTracker")
end

local function knowsSeal()
	for _, r in pairs(PK.SpellRegistry.byKey) do
		if r.category == "seal" and r.known then
			return true
		end
	end
	return false
end

local function formatTime(sec)
	if not sec or sec == math.huge then
		return ""
	elseif sec >= 60 then
		return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60))
	end
	return string.format("%.0f", sec)
end

local function build()
	local anchor = Frames:GetAnchor("SealTracker")
	container = CreateFrame("Frame", nil, anchor)
	container:SetAllPoints(anchor)
	icon = Frames:AcquireIcon(container, settings().iconSize)
	icon:SetPoint("LEFT", container, "LEFT", 0, 0)

	bar = CreateFrame("StatusBar", nil, container)
	bar:SetPoint("LEFT", icon, "RIGHT", 4, 0)
	bar:SetSize(BAR_WIDTH, 14)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(0.95, 0.75, 0.25)
	bar:SetMinMaxValues(0, 1)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.5)

	nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	nameText:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 2)
	timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	timeText:SetPoint("RIGHT", bar, "RIGHT", -3, 0)

	-- Redraw the bar ~10 times a second from the known expiration time.
	local elapsed = 0
	container:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.1 then
			return
		end
		elapsed = 0
		M:UpdateTimer()
	end)
end

function M:UpdateTimer()
	if not current then
		return
	end
	local remaining = AS:Remaining(current)
	if not remaining then
		self:Render() -- expired
		return
	end
	if remaining == math.huge or (current.duration or 0) <= 0 then
		bar:SetValue(1)
		timeText:SetText("")
	else
		bar:SetValue(remaining / current.duration)
		timeText:SetText(formatTime(remaining))
	end
end

function M:Render()
	if not self.enabled then
		return
	end
	if not container then
		build()
	end
	local s = settings()
	local anchor = Frames:GetAnchor("SealTracker")
	local size = s.iconSize or 30
	icon:SetSize(size, size)
	if s.showBar then
		bar:Show()
	else
		bar:Hide()
	end
	anchor:SetSize(size + (s.showBar and (BAR_WIDTH + 4) or 0), size)

	if not knowsSeal() then
		container:Hide()
		return
	end
	container:Show()

	local seal, source = AS:GetSeal()
	current = seal
	if seal then
		icon.icon:SetTexture(seal.icon or 134400)
		icon:SetState("ready")
		nameText:SetText(seal.name .. (source == "predicted" and " |cff909090*|r" or ""))
		self:UpdateTimer()
	else
		local r = PK.SpellRegistry:Get("SEAL_RIGHTEOUSNESS")
		icon.icon:SetTexture(r and r.icon or 134400)
		if AS.frozen then
			icon:SetState("unusable")
			nameText:SetText("|cff909090Seal: can't see in combat|r")
		else
			icon:SetState("missing")
			nameText:SetText("|cffff4040No Seal|r")
		end
		bar:SetValue(0)
		timeText:SetText("")
	end
end

function M:OnEnable()
	local function render()
		M:Render()
	end
	PK:On("PK_AURAS_UPDATED", self, render)
	PK:On("PK_SPELLS_UPDATED", self, render)
	PK:On("PK_PROFILE_CHANGED", self, render)
	PK:On("PK_SETTINGS_CHANGED", self, render)
	self:Render()
end

function M:OnDisable()
	PK:Off("PK_AURAS_UPDATED", self)
	PK:Off("PK_SPELLS_UPDATED", self)
	PK:Off("PK_PROFILE_CHANGED", self)
	PK:Off("PK_SETTINGS_CHANGED", self)
	current = nil
	if container then
		container:Hide()
	end
end

function M:OnSpecChanged()
	self:Render()
end
