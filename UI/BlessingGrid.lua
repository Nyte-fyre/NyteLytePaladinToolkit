local _, PK = ...

-- Blessing assignment grid (PallyPower-style): one row per paladin, one
-- column per class plus an Aura column. Left-click a cell for the next
-- Blessing that paladin knows, right-click for the previous one, Shift-click
-- to clear. Rows you can't edit (other paladins, unless you're leader or
-- assistant) are dimmed. Opened with /ptk bless or the small icon next to
-- the buff button.

local B = PK.Blessings
local Theme = PK.Theme
local Grid = {}
PK.BlessingGrid = Grid

local CELL = 30
local GAP = 4
local NAME_WIDTH = 120
local MAX_ROWS = 8
local LEFT, TOP = 16, -80

local window, rows, statusText, headers = nil, {}, nil, {}

local function manager()
	return PK.modules.BlessingManager
end

local CLASS_NAMES = {
	WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

local function spellIcon(key)
	local r = PK.SpellRegistry:Get(key)
	if r and r.icon then
		return r.icon
	end
	local info = key and PK.Spells.byKey[key] and PK.Compat.GetSpellInfo(PK.Spells.byKey[key].names[1])
	return info and info.iconID or nil
end

local function spellName(key)
	local e = key and PK.Spells.byKey[key]
	return e and e.names[1] or "none"
end

-- Ordered options for a paladin's cell: Blessings (or Auras) they know.
local function options(paladin, isAura)
	local blessings, auras = manager():KnownFor(paladin)
	local out = {}
	if isAura then
		auras = auras or B.ASSUMED_AURAS
		for _, key in ipairs(B.AURA_PRIORITY) do
			if auras[key] then
				out[#out + 1] = key
			end
		end
	else
		blessings = blessings or B.ASSUMED_BLESSINGS
		for _, key in ipairs(B.ASSIGNABLE) do
			if blessings[key] then
				out[#out + 1] = key
			end
		end
	end
	return out
end

local function cycle(list, current, step)
	if #list == 0 then
		return nil
	end
	local index = 0
	for i, key in ipairs(list) do
		if key == current then
			index = i
		end
	end
	index = index + step
	if index > #list then
		index = 1
	elseif index < 1 then
		index = #list
	end
	return list[index]
end

local function onCellClick(cell, mouseButton)
	local paladin = cell.row.paladin
	if not paladin then
		return
	end
	local eff = manager():Effective()[paladin] or { classes = {} }
	local current = cell.class and eff.classes and eff.classes[cell.class] or (not cell.class and eff.aura) or nil
	local nextKey
	if IsShiftKeyDown and IsShiftKeyDown() then
		nextKey = nil
	else
		nextKey = cycle(options(paladin, cell.class == nil), current, mouseButton == "RightButton" and -1 or 1)
	end
	if cell.class then
		manager():SetAssignment(paladin, cell.class, nextKey)
	else
		manager():SetAssignment(paladin, nil, nil, nextKey)
	end
end

local function makeCell(parent, row, class)
	local cell = CreateFrame("Button", nil, parent)
	cell:SetSize(CELL, CELL)
	cell.row, cell.class = row, class
	local bg = cell:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.45)
	cell.icon = cell:CreateTexture(nil, "ARTWORK")
	cell.icon:SetPoint("TOPLEFT", 2, -2)
	cell.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local hl = cell:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.85, 0.4, 0.25)
	cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	cell:SetScript("OnClick", onCellClick)
	cell:SetScript("OnEnter", function(self)
		if not GameTooltip then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(Theme.Color("gold", (self.row.paladin or "?") .. " → "
			.. (self.class and CLASS_NAMES[self.class] or "Aura")))
		GameTooltip:AddLine(spellName(self.key), 1, 1, 1)
		if self.row.editable then
			GameTooltip:AddLine("Left/right-click to change, Shift-click to clear.", 0.7, 0.7, 0.7, true)
		else
			GameTooltip:AddLine("Only this paladin or the group leader/assistants can change it.", 0.7, 0.7, 0.7, true)
		end
		GameTooltip:Show()
	end)
	cell:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	return cell
end

local function build()
	local width = LEFT * 2 + NAME_WIDTH + (#B.CLASSES + 1) * (CELL + GAP) + 10
	local height = -TOP + MAX_ROWS * (CELL + GAP) + 70
	window = Theme.CreateWindow("NyteLytePaladinToolkitBlessingGrid", "Blessing Assignments", width, height,
		Theme.ICON_BLESSING)

	-- Column headers: class icons (text fallback) and the Aura column.
	local coords = _G.CLASS_ICON_TCOORDS
	for i, class in ipairs(B.CLASSES) do
		local x = LEFT + NAME_WIDTH + (i - 1) * (CELL + GAP)
		local h
		if coords and coords[class] then
			h = window:CreateTexture(nil, "ARTWORK")
			h:SetSize(CELL - 6, CELL - 6)
			h:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
			h:SetTexCoord(unpack(coords[class]))
			h:SetPoint("TOPLEFT", x + 3, TOP + CELL)
		else
			h = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			h:SetPoint("TOPLEFT", x, TOP + CELL - 8)
			h:SetText(CLASS_NAMES[class]:sub(1, 3))
		end
		headers[#headers + 1] = h
	end
	local auraHeader = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	auraHeader:SetPoint("TOPLEFT", LEFT + NAME_WIDTH + #B.CLASSES * (CELL + GAP) + 4, TOP + CELL - 8)
	auraHeader:SetText("Aura")

	for r = 1, MAX_ROWS do
		local y = TOP - (r - 1) * (CELL + GAP)
		local row = { cells = {} }
		row.name = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.name:SetPoint("TOPLEFT", LEFT, y - 8)
		row.name:SetWidth(NAME_WIDTH - 6)
		row.name:SetJustifyH("LEFT")
		for i, class in ipairs(B.CLASSES) do
			local cell = makeCell(window, row, class)
			cell:SetPoint("TOPLEFT", LEFT + NAME_WIDTH + (i - 1) * (CELL + GAP), y)
			row.cells[#row.cells + 1] = cell
		end
		local auraCell = makeCell(window, row, nil)
		auraCell:SetPoint("TOPLEFT", LEFT + NAME_WIDTH + #B.CLASSES * (CELL + GAP) + 6, y)
		row.cells[#row.cells + 1] = auraCell
		rows[r] = row
	end

	local suggest = Theme.Button(window, "Auto-suggest", 120, function()
		local n = manager():ApplySuggestion()
		PK:Print("suggested layout applied to " .. n .. " row(s). Change any cell by clicking it.")
	end)
	suggest:SetPoint("BOTTOMLEFT", 16, 16)
	local announce = Theme.Button(window, "Announce", 100, function()
		manager():Announce()
	end)
	announce:SetPoint("LEFT", suggest, "RIGHT", 8, 0)
	statusText = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	statusText:SetPoint("LEFT", announce, "RIGHT", 12, 0)
	statusText:SetPoint("RIGHT", window, "RIGHT", -16, 0)
	statusText:SetJustifyH("LEFT")

	window:SetScript("OnShow", function()
		Grid:Refresh()
	end)
end

function Grid:Refresh()
	if not window or not window:IsShown() then
		return
	end
	local m = manager()
	local eff = m:Effective()
	local paladins = m:Paladins()
	local withAddon = 0
	for r = 1, MAX_ROWS do
		local row = rows[r]
		local paladin = paladins[r]
		row.paladin = paladin
		row.editable = paladin ~= nil and m:CanEdit(paladin)
		if paladin then
			local hasAddon = paladin == UnitName("player") or m.peers[paladin] ~= nil
			if hasAddon and paladin ~= UnitName("player") then
				withAddon = withAddon + 1
			end
			row.name:SetText((row.editable and Theme.Color("light", paladin) or Theme.Color("dim", paladin))
				.. (hasAddon and "" or Theme.Color("dim", " (no addon)")))
		else
			row.name:SetText("")
		end
		local data = paladin and eff[paladin]
		for _, cell in ipairs(row.cells) do
			cell:SetShown(paladin ~= nil)
			local key
			if data then
				key = cell.class and data.classes and data.classes[cell.class] or (not cell.class and data.aura) or nil
			end
			cell.key = key
			cell.icon:SetTexture(key and spellIcon(key) or nil)
			cell.icon:SetDesaturated(not row.editable)
			cell:SetAlpha(row.editable and 1 or 0.6)
		end
	end
	local extra = #paladins > MAX_ROWS and (" (showing " .. MAX_ROWS .. " of " .. #paladins .. ")") or ""
	statusText:SetText(withAddon .. " other paladin(s) syncing" .. extra
		.. (PK.Comm:Pending() > 0 and " - sending after combat" or ""))
end

function Grid:Toggle()
	if not window then
		build()
	end
	if window:IsShown() then
		window:Hide()
	else
		window:Show()
		self:Refresh()
	end
end

function Grid:Hide()
	if window then
		window:Hide()
	end
end

local function refresh()
	Grid:Refresh()
end
PK:On("PK_BLESSINGS_CHANGED", Grid, refresh)
PK:On("PK_ROSTER_UPDATED", Grid, refresh)
PK:On("PK_PROFILE_CHANGED", Grid, refresh)
