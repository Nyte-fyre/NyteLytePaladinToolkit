local _, PK = ...

-- Shared UI building blocks:
--  * Anchors: one movable frame per module that the module's widgets attach
--    to. Positions are saved per spec. Unlocking shows a labeled green box
--    on each enabled module's anchor, plus an alignment grid.
--  * Icons: a pooled spell icon with cooldown swipe, border and text, used by
--    the cooldown/buff modules. Cooldowns are fed either a duration object
--    (display-only, works with secret values) or plain numbers already
--    checked to be non-secret.

local Compat = PK.Compat
local Secrets = PK.Secrets
local Presets = PK.Presets
local Frames = { anchors = {} }
PK.Frames = Frames

local GRID_SIZE = 32

-- Anchors ---------------------------------------------------------------------------------

local function currentSpec()
	return PK.SpecProfile:GetSpec()
end

-- Saves the anchor's center as an offset from the screen center, in
-- UIParent units. Dragging re-anchors frames to a corner, so GetPoint
-- would not round-trip; the center offset always does.
local function saveAnchor(anchor)
	local ax, ay = anchor:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if not (ax and ux) then
		return
	end
	local scale = anchor:GetScale() or 1
	local x = math.floor(ax * scale - ux + 0.5)
	local y = math.floor(ay * scale - uy + 0.5)
	PK.Config:SetLayout(currentSpec(), anchor.module, "CENTER", x, y)
end

function Frames:GetAnchor(module)
	local anchor = self.anchors[module]
	if anchor then
		return anchor
	end
	anchor = CreateFrame("Frame", nil, UIParent)
	anchor.module = module
	anchor:SetSize(160, 36)
	anchor:SetClampedToScreen(true)
	anchor:SetMovable(true)
	anchor:RegisterForDrag("LeftButton")
	anchor:SetScript("OnDragStart", function(self)
		if not PK.profile.locked then
			self:StartMoving()
		end
	end)
	anchor:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		saveAnchor(self)
	end)

	local mover = CreateFrame("Frame", nil, anchor)
	mover:SetAllPoints()
	mover:SetFrameStrata("HIGH")
	local bg = mover:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.1, 0.7, 0.2, 0.45)
	local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER")
	label:SetText(Presets.MODULE_LABELS[module] or module)
	mover:Hide()
	anchor.mover = mover

	self.anchors[module] = anchor
	self:ApplyLayout(module)
	return anchor
end

function Frames:ApplyLayout(module)
	local anchor = self.anchors[module]
	local l = PK.Config:GetLayout(currentSpec(), module)
	if not anchor or not l then
		return
	end
	local scale = l.scale or 1
	anchor:SetScale(scale)
	anchor:ClearAllPoints()
	-- Offsets are stored in UIParent units; SetPoint uses the frame's own scale.
	anchor:SetPoint(l.point or "CENTER", UIParent, l.point or "CENTER", (l.x or 0) / scale, (l.y or 0) / scale)
end

-- Shows movers (when unlocked) only for modules enabled in the current spec.
function Frames:Refresh()
	local spec = currentSpec()
	local unlocked = PK.profile and not PK.profile.locked
	for _, module in ipairs(Presets.MODULES) do
		local enabled = PK.Config:IsModuleEnabled(module, spec)
		if enabled and unlocked then
			self:GetAnchor(module)
		end
		local anchor = self.anchors[module]
		if anchor then
			self:ApplyLayout(module)
			anchor:EnableMouse(unlocked and enabled or false)
			if unlocked and enabled then
				anchor.mover:Show()
			else
				anchor.mover:Hide()
			end
		end
	end
	self:ShowGrid(unlocked)
end

function Frames:SetLocked(locked)
	PK.profile.locked = locked and true or false
	self:Refresh()
	PK:Fire("PK_LOCK_CHANGED", PK.profile.locked)
	PK:Print(locked and "frames locked." or "frames unlocked: drag the green boxes, then /ptk lock.")
end

function Frames:ToggleLock()
	self:SetLocked(not PK.profile.locked)
end

function Frames:ResetPositions()
	PK.Config:ResetLayout(currentSpec())
	self:Refresh()
	PK:Print("frame positions reset for " .. PK.SpecProfile.LABELS[currentSpec()] .. ".")
end

-- Alignment grid ----------------------------------------------------------------------------

local grid
function Frames:ShowGrid(show)
	if not show then
		if grid then
			grid:Hide()
		end
		return
	end
	if not grid then
		grid = CreateFrame("Frame", nil, UIParent)
		grid:SetAllPoints(UIParent)
		grid:SetFrameStrata("BACKGROUND")
		local w, h = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
		local function line(horizontal, offset, center)
			local t = grid:CreateTexture(nil, "BACKGROUND")
			if center then
				t:SetColorTexture(1, 0.3, 0.3, 0.5)
			else
				t:SetColorTexture(1, 1, 1, 0.12)
			end
			if horizontal then
				t:SetPoint("LEFT", grid, "LEFT", 0, offset)
				t:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
				t:SetHeight(1)
			else
				t:SetPoint("TOP", grid, "TOP", offset, 0)
				t:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
				t:SetWidth(1)
			end
		end
		for x = 0, w / 2, GRID_SIZE do
			line(false, x, x == 0)
			if x > 0 then
				line(false, -x)
			end
		end
		for y = 0, h / 2, GRID_SIZE do
			line(true, y, y == 0)
			if y > 0 then
				line(true, -y)
			end
		end
	end
	grid:Show()
end

-- Icons -----------------------------------------------------------------------------------------

local IconMixin = {}

-- state: "ready" | "cooldown" | "missing" | "unusable"
function IconMixin:SetState(state)
	self.state = state
	local desat = state == "missing" or state == "unusable"
	self.icon:SetDesaturated(desat)
	self.icon:SetAlpha(state == "unusable" and 0.5 or 1)
	if state == "missing" then
		self.border:SetVertexColor(1, 0.1, 0.1, 1)
		self.border:Show()
	else
		self.border:Hide()
	end
end

function IconMixin:SetSpell(spellID)
	self.spellID = spellID
	self.icon:SetTexture(Compat.GetSpellTexture(spellID) or 134400) -- question mark
end

-- Display-only cooldown from a duration object (works with secret values).
function IconMixin:SetCooldownFromDuration(duration)
	local cd = self.cooldown
	if type(duration) == "nil" or not cd.SetCooldownFromDurationObject then
		cd:Clear()
		return false
	end
	local ok = pcall(cd.SetCooldownFromDurationObject, cd, duration)
	if not ok then
		cd:Clear()
	end
	return ok
end

-- Numeric cooldown; ignored unless both numbers are readable.
function IconMixin:SetCooldownNumbers(start, duration)
	local s, d = Secrets.SafeNumber(start), Secrets.SafeNumber(duration)
	if s and d and d > 0 then
		self.cooldown:SetCooldown(s, d)
	else
		self.cooldown:Clear()
	end
end

local GCD_MAX = 1.6

-- Reads this icon's spell cooldown and draws it. Combat-safe: isActive and
-- isOnGCD stay readable in combat on Forever, numbers are used only when
-- readable, and otherwise the client draws the swipe from a duration
-- object. Sets state ready/cooldown/unusable and returns it.
function IconMixin:RefreshCooldown(dimUnusable)
	local id = self.spellID
	if not id then
		return self.state
	end
	local info = Compat.GetSpellCooldown(id)
	local activeState, isActive = Secrets.Field(info, "isActive")
	local gcdState, isOnGCD = Secrets.Field(info, "isOnGCD")
	local start = Secrets.SafeNumber(select(2, Secrets.Field(info, "startTime")))
	local duration = Secrets.SafeNumber(select(2, Secrets.Field(info, "duration")))
	local onCooldown
	if activeState == Secrets.VALUE then
		onCooldown = isActive == true and not (gcdState == Secrets.VALUE and isOnGCD == true)
	elseif start and duration then
		onCooldown = duration > GCD_MAX
	end
	if onCooldown == false then
		self.cooldown:Clear()
	elseif start and duration then
		self:SetCooldownNumbers(start, duration)
	else
		local drawn = self:SetCooldownFromDuration(Compat.GetSpellCooldownDuration(id, true))
		if onCooldown == nil then
			onCooldown = drawn
		end
	end
	local usable = Compat.IsSpellUsable(id)
	if onCooldown then
		self:SetState("cooldown")
	elseif usable == false and dimUnusable then
		self:SetState("unusable")
	else
		self:SetState("ready")
	end
	return self.state
end

function IconMixin:SetText(text)
	self.text:SetText(text or "")
end

local pool = {}

function Frames:AcquireIcon(parent, size)
	local f = table.remove(pool)
	if not f then
		f = CreateFrame("Frame", nil, parent)
		f.icon = f:CreateTexture(nil, "ARTWORK")
		f.icon:SetAllPoints()
		f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
		f.cooldown:SetAllPoints()
		f.cooldown:SetDrawEdge(false)
		f.border = f:CreateTexture(nil, "OVERLAY")
		f.border:SetPoint("TOPLEFT", -2, 2)
		f.border:SetPoint("BOTTOMRIGHT", 2, -2)
		f.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		f.border:SetBlendMode("ADD")
		f.border:Hide()
		f.text = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		f.text:SetPoint("BOTTOMRIGHT", -1, 1)
		for k, fn in pairs(IconMixin) do
			f[k] = fn
		end
	end
	f:SetParent(parent)
	f:SetSize(size or 36, size or 36)
	f:SetState("ready")
	f:Show()
	return f
end

function Frames:ReleaseIcon(f)
	f:Hide()
	f:ClearAllPoints()
	f.cooldown:Clear()
	f.spellID = nil
	f:SetText("")
	pool[#pool + 1] = f
end

-- Events and commands ----------------------------------------------------------------------------

local function refresh()
	Frames:Refresh()
end
PK:On("PK_SPEC_CHANGED", Frames, refresh)
PK:On("PK_PROFILE_CHANGED", Frames, refresh)
PK:On("PK_MODULES_CHANGED", Frames, refresh)
PK:On("PK_READY", Frames, refresh)
PK:On("PK_LAYOUT_CHANGED", Frames, function(_, _, module)
	if module then
		Frames:ApplyLayout(module)
	else
		Frames:Refresh()
	end
end)

PK:RegisterCommand("unlock", function()
	Frames:SetLocked(false)
end, "unlock frames so you can drag them")
PK:RegisterCommand("lock", function()
	Frames:SetLocked(true)
end, "lock frames in place")
PK:RegisterCommand("reset", function()
	Frames:ResetPositions()
end, "reset frame positions for the current spec")
