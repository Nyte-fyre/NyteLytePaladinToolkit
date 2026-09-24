local _, PK = ...

-- The addon's "Holy" look: classic WoW gold-bordered dialogs, warm gold and
-- parchment-light text, and holy spell icons. Only Blizzard's own built-in
-- textures are used, so there's nothing to ship. Every window and header
-- goes through here so the look stays consistent and is changed in one place.

local Theme = {}
PK.Theme = Theme

Theme.ICON = "Interface\\Icons\\Spell_Holy_HolyBolt"
Theme.ICON_BLESSING = "Interface\\Icons\\Spell_Holy_FistOfJustice"
Theme.ICON_SEAL = "Interface\\Icons\\Spell_Holy_RighteousnessAura"
Theme.ICON_GRID = "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings"
Theme.WHITE = "Interface\\Buttons\\WHITE8X8"

-- r, g, b[, a]
Theme.colors = {
	gold = { 1, 0.82, 0.25 },
	light = { 1, 0.95, 0.75 }, -- parchment / holy light
	text = { 0.96, 0.92, 0.82 },
	dim = { 0.62, 0.56, 0.44 },
	alarm = { 1, 0.27, 0.2 },
	bg = { 0.07, 0.05, 0.02, 0.94 },
	mover = { 1, 0.82, 0.25, 0.35 },
}
Theme.hex = {
	gold = "ffffd140",
	light = "fffff2bf",
	dim = "ff9e8f70",
	alarm = "ffff4533",
	ok = "ff9be070",
}

function Theme.Color(name, text)
	return "|c" .. (Theme.hex[name] or Theme.hex.light) .. text .. "|r"
end

-- Inline icon for chat and font strings.
function Theme.InlineIcon(path, size)
	return "|T" .. (path or Theme.ICON) .. ":" .. (size or 14) .. ":" .. (size or 14) .. "|t"
end

Theme.BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
	tile = true,
	tileSize = 32,
	edgeSize = 24,
	insets = { left = 6, right = 6, top = 6, bottom = 6 },
}

Theme.BACKDROP_THIN = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = false,
	edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Gold-bordered dark background on a BackdropTemplate frame.
function Theme.ApplyBackdrop(frame, thin)
	if not frame.SetBackdrop then
		return
	end
	frame:SetBackdrop(thin and Theme.BACKDROP_THIN or Theme.BACKDROP)
	local bg = Theme.colors.bg
	if thin then
		frame:SetBackdropColor(bg[1], bg[2], bg[3], 0.85)
	else
		frame:SetBackdropColor(1, 1, 1, 1)
	end
	local g = Theme.colors.gold
	frame:SetBackdropBorderColor(g[1], g[2], g[3], 1)
end

-- A soft vertical wash of gold light at the top of a frame.
function Theme.AddGlow(frame, height)
	local tex = frame:CreateTexture(nil, "BORDER")
	tex:SetTexture(Theme.WHITE)
	tex:SetPoint("TOPLEFT", 7, -7)
	tex:SetPoint("TOPRIGHT", -7, -7)
	tex:SetHeight(height or 60)
	local ok = pcall(function()
		tex:SetGradient("VERTICAL", CreateColor(1, 0.85, 0.4, 0), CreateColor(1, 0.85, 0.4, 0.18))
	end)
	if not ok then
		tex:SetVertexColor(1, 0.85, 0.4, 0.08)
	end
	return tex
end

-- Section header: gold text with a thin gold rule under it.
function Theme.Header(parent, text, x, y, width)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	local g = Theme.colors.gold
	fs:SetTextColor(g[1], g[2], g[3])
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetTexture(Theme.WHITE)
	rule:SetVertexColor(g[1], g[2], g[3], 0.35)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
	rule:SetWidth(width or 260)
	return fs, rule
end

-- Title row: holy icon + large gold title.
function Theme.Title(parent, text, x, y, icon)
	local tex = parent:CreateTexture(nil, "ARTWORK")
	tex:SetSize(28, 28)
	tex:SetPoint("TOPLEFT", x, y)
	tex:SetTexture(icon or Theme.ICON)
	tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	fs:SetPoint("LEFT", tex, "RIGHT", 8, 0)
	fs:SetText(text)
	local g = Theme.colors.gold
	fs:SetTextColor(g[1], g[2], g[3])
	return fs, tex
end

-- A movable, Esc-closable window in the Holy style, with a close button.
-- `name` must be a unique global frame name (needed for Esc to close it).
function Theme.CreateWindow(name, title, width, height, icon)
	local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "BackdropTemplate")
	if not ok then
		f = CreateFrame("Frame", name, UIParent)
	end
	f:SetSize(width, height)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	Theme.ApplyBackdrop(f)
	Theme.AddGlow(f, 70)
	f.titleText, f.titleIcon = Theme.Title(f, title or PK.displayName, 16, -14, icon)
	local okClose, close = pcall(CreateFrame, "Button", nil, f, "UIPanelCloseButton")
	if okClose and close then
		close:SetPoint("TOPRIGHT", -4, -4)
		f.closeButton = close
	end
	if name then
		tinsert(UISpecialFrames, name)
	end
	f:Hide()
	return f
end

-- A crisp 1px (or `size`) edge around a frame, drawn with four textures.
-- Returns a small object with SetVertexColor/Show/Hide so it can stand in
-- for a border texture. (Blizzard's action-button border is a big glow
-- ring; squeezed onto an icon it shows as a box inside the icon.)
function Theme.Edge(frame, r, g, b, a, size, layer)
	size = size or 1
	local edge = { lines = {} }
	local spec = {
		{ "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
	}
	for _, s in ipairs(spec) do
		local t = frame:CreateTexture(nil, layer or "OVERLAY")
		t:SetTexture(Theme.WHITE)
		t:SetPoint(s[1])
		t:SetPoint(s[2])
		if s[3] then
			t:SetHeight(size)
		else
			t:SetWidth(size)
		end
		edge.lines[#edge.lines + 1] = t
	end
	function edge:SetVertexColor(cr, cg, cb, ca)
		for _, t in ipairs(self.lines) do
			t:SetVertexColor(cr, cg, cb, ca or 1)
		end
	end
	function edge:Show()
		for _, t in ipairs(self.lines) do
			t:Show()
		end
	end
	function edge:Hide()
		for _, t in ipairs(self.lines) do
			t:Hide()
		end
	end
	edge:SetVertexColor(r or 1, g or 0.82, b or 0.25, a or 1)
	return edge
end

-- Gold-tinted panel button.
function Theme.Button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 24)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end
