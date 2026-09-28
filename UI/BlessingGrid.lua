local _, PK = ...

-- Blessing assignment grid (PallyPower-style): one row per paladin, one
-- column per class plus an Aura column. Left-click a cell for the next
-- Blessing that paladin knows, Ctrl-click for the previous one, Shift-click
-- to clear. Right-click a class cell for per-player exceptions (e.g. Kings
-- instead of Salvation on the tank, or None); cells with exceptions show a
-- small gold mark. Below the rows: who in the group is missing a Blessing
-- from any paladin. Two paladins on the same Aura are highlighted red.
-- Rows you can't edit (other paladins, unless you're leader or assistant)
-- are dimmed. Opened with /ptk bless or the small icon next to the buff button.

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
local coverageText
local popup, popupRows = nil, {}
local COVERAGE_HEIGHT = 34

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

-- Ordered options for a paladin's cell: the Blessings (or Auras) they know,
-- or every one if the addon doesn't know their spells (they may know more
-- than we can tell, e.g. a higher-level paladin not running the addon).
local function options(paladin, isAura)
	local blessings, auras = manager():KnownFor(paladin)
	local out = {}
	local list = isAura and B.AURA_PRIORITY or B.ASSIGNABLE
	local known = isAura and auras or blessings
	for _, key in ipairs(list) do
		if not known or known[key] then
			out[#out + 1] = key
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

local Grid_OpenExceptions -- defined below

local function onCellClick(cell, mouseButton)
	local paladin = cell.row.paladin
	if not paladin then
		return
	end
	if mouseButton == "RightButton" and cell.class then
		Grid_OpenExceptions(paladin, cell.class, cell)
		return
	end
	local eff = manager():Effective()[paladin] or { classes = {} }
	local current = cell.class and eff.classes and eff.classes[cell.class] or (not cell.class and eff.aura) or nil
	local nextKey
	if IsShiftKeyDown and IsShiftKeyDown() then
		nextKey = nil
	else
		local back = mouseButton == "RightButton" or (IsControlKeyDown and IsControlKeyDown())
		nextKey = cycle(options(paladin, cell.class == nil), current, back and -1 or 1)
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
	-- Gold corner mark: this class has per-player exceptions on this row.
	cell.mark = cell:CreateTexture(nil, "OVERLAY")
	cell.mark:SetSize(7, 7)
	cell.mark:SetPoint("TOPRIGHT", -1, -1)
	cell.mark:SetColorTexture(1, 0.82, 0.25, 1)
	cell.mark:Hide()
	-- Red edge: this Aura is also assigned to another paladin.
	cell.conflict = Theme.Edge(cell, 1, 0.25, 0.2, 1, 2, "OVERLAY")
	cell.conflict:Hide()
	cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	cell:SetScript("OnClick", onCellClick)
	cell:SetScript("OnEnter", function(self)
		if not GameTooltip then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(Theme.Color("gold", (self.row.paladin and manager():NameOf(self.row.paladin) or "?") .. " → "
			.. (self.class and CLASS_NAMES[self.class] or "Aura")))
		GameTooltip:AddLine(spellName(self.key), 1, 1, 1)
		for _, line in ipairs(self.exceptions or {}) do
			GameTooltip:AddLine(line, 1, 0.82, 0.25)
		end
		if self.isConflict then
			GameTooltip:AddLine("Another paladin is assigned this Aura too.", 1, 0.3, 0.2, true)
		end
		if self.row.editable then
			GameTooltip:AddLine("Click: next, Ctrl-click: previous, Shift-click: clear"
				.. (self.class and ", right-click: player exceptions." or "."), 0.7, 0.7, 0.7, true)
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
		row.name:SetWordWrap(false) -- "Nyte Fyre (no addon)" truncates instead of wrapping
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

	coverageText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	coverageText:SetPoint("BOTTOMLEFT", 16, 46)
	coverageText:SetPoint("BOTTOMRIGHT", -16, 46)
	coverageText:SetJustifyH("LEFT")
	coverageText:SetJustifyV("BOTTOM")
	coverageText:SetHeight(COVERAGE_HEIGHT - 4)

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
	local myId = paladins[1] -- Paladins() always lists you first
	local withAddon = 0
	for r = 1, MAX_ROWS do
		local row = rows[r]
		local paladin = paladins[r]
		row.paladin = paladin
		row.editable = paladin ~= nil and m:CanEdit(paladin)
		if paladin then
			local mine = paladin == myId
			local hasAddon = mine or m.peers[paladin] ~= nil
			if hasAddon and not mine then
				withAddon = withAddon + 1
			end
			local name = m:NameOf(paladin)
			row.name:SetText((row.editable and Theme.Color("light", name) or Theme.Color("dim", name))
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
			-- Exceptions for players of this class on this row.
			cell.exceptions = {}
			if cell.class and data and data.overrides then
				for _, member in ipairs(PK.Roster.members) do
					local o = member.guid and data.overrides[member.guid]
					if member.class == cell.class and o then
						cell.exceptions[#cell.exceptions + 1] = member.name .. ": "
							.. (o == B.NONE and "none" or spellName(o))
					end
				end
			end
			cell.mark:SetShown(#cell.exceptions > 0)
			-- Aura column: the same Aura on two rows is wasted (they don't stack).
			cell.isConflict = false
			if not cell.class and key then
				for _, other in ipairs(paladins) do
					if other ~= paladin and eff[other] and eff[other].aura == key then
						cell.isConflict = true
					end
				end
			end
			if cell.isConflict then
				cell.conflict:Show()
			else
				cell.conflict:Hide()
			end
		end
	end
	-- Who in the group is missing a Blessing from any paladin (out of combat).
	local gaps, uncovered = "", ""
	if IsInGroup and IsInGroup() and not PK.Compat.InCombat() then
		gaps, uncovered = m:CoverageText()
	end
	local lines = {}
	if gaps ~= "" then
		lines[#lines + 1] = Theme.Color("gold", "Missing: ") .. gaps
	end
	if uncovered ~= "" then
		lines[#lines + 1] = Theme.Color("alarm", "Nobody assigned for: ") .. uncovered
	end
	coverageText:SetText(table.concat(lines, "\n"))
	local shownRows = math.max(1, math.min(#paladins, MAX_ROWS))
	window:SetHeight(-TOP + shownRows * (CELL + GAP) + 64 + (#lines > 0 and COVERAGE_HEIGHT or 0))
	local extra = #paladins > MAX_ROWS and (" (showing " .. MAX_ROWS .. " of " .. #paladins .. ")") or ""
	statusText:SetText(withAddon .. " other paladin(s) syncing" .. extra
		.. (PK.Comm:Pending() > 0 and " - sending after combat" or ""))
end

-- Per-player exceptions popup ----------------------------------------------------------

local POPUP_ROWS = 10

local function exceptionOptions(paladin)
	local list = options(paladin, false)
	list[#list + 1] = B.NONE
	return list
end

local function refreshPopup()
	if not popup or not popup:IsShown() then
		return
	end
	local m = manager()
	local row = m:Effective()[popup.paladin] or {}
	local overrides = row.overrides or {}
	local classKey = row.classes and row.classes[popup.class]
	local players = {}
	for _, member in ipairs(PK.Roster.members) do
		if member.class == popup.class and member.guid then
			players[#players + 1] = member
		end
	end
	local editable = m:CanEdit(popup.paladin)
	for i = 1, POPUP_ROWS do
		local r = popupRows[i]
		local member = players[i]
		r.member = member
		if member then
			local o = overrides[member.guid]
			r.name:SetText(member.name)
			r.cell.key = o
			if o == B.NONE then
				r.cell.icon:SetTexture(nil)
				r.label:SetText(Theme.Color("dim", "none"))
			elseif o then
				r.cell.icon:SetTexture(spellIcon(o))
				r.label:SetText(Theme.Color("gold", spellName(o)))
			else
				r.cell.icon:SetTexture(classKey and spellIcon(classKey) or nil)
				r.label:SetText(Theme.Color("dim", "class default" .. (classKey and (" (" .. spellName(classKey) .. ")") or "")))
			end
			r.cell:SetAlpha(editable and 1 or 0.6)
			r.frame:Show()
		else
			r.frame:Hide()
		end
	end
	popup.empty:SetShown(#players == 0)
	popup:SetHeight(60 + math.max(1, math.min(#players, POPUP_ROWS)) * 28 + 10)
end

local function buildPopup()
	popup = Theme.CreateWindow("NyteLytePaladinToolkitExceptions", "Exceptions", 320, 200, Theme.ICON_GRID)
	popup:SetFrameStrata("FULLSCREEN_DIALOG")
	popup.empty = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	popup.empty:SetPoint("TOPLEFT", 16, -56)
	popup.empty:SetText("Nobody of this class is in your group.")
	for i = 1, POPUP_ROWS do
		local f = CreateFrame("Frame", nil, popup)
		f:SetSize(290, 26)
		f:SetPoint("TOPLEFT", 16, -52 - (i - 1) * 28)
		local r = { frame = f }
		r.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		r.name:SetPoint("LEFT", 0, 0)
		r.name:SetWidth(120)
		r.name:SetJustifyH("LEFT")
		r.name:SetWordWrap(false)
		r.cell = CreateFrame("Button", nil, f)
		r.cell:SetSize(24, 24)
		r.cell:SetPoint("LEFT", 124, 0)
		local bg = r.cell:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.45)
		r.cell.icon = r.cell:CreateTexture(nil, "ARTWORK")
		r.cell.icon:SetPoint("TOPLEFT", 2, -2)
		r.cell.icon:SetPoint("BOTTOMRIGHT", -2, 2)
		r.cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		r.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		r.label:SetPoint("LEFT", r.cell, "RIGHT", 6, 0)
		r.cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		r.cell:SetScript("OnClick", function(_, mouseButton)
			local member = r.member
			if not member then
				return
			end
			local key
			if not (IsShiftKeyDown and IsShiftKeyDown()) then
				-- Order: class default -> each Blessing they know -> none -> default.
				local list = exceptionOptions(popup.paladin)
				local back = mouseButton == "RightButton" or (IsControlKeyDown and IsControlKeyDown())
				if r.cell.key == nil then
					key = back and list[#list] or list[1]
				else
					local index = 0
					for i2, k in ipairs(list) do
						if k == r.cell.key then
							index = i2
						end
					end
					index = index + (back and -1 or 1)
					key = list[index] -- past either end: back to class default
				end
			end
			manager():SetOverride(popup.paladin, member.guid, key)
		end)
		r.cell:SetScript("OnEnter", function(self)
			if GameTooltip then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(Theme.Color("gold", "Exception for " .. (r.member and r.member.name or "?")))
				GameTooltip:AddLine("Click: next, Ctrl/right-click: previous, Shift-click: back to the class default.",
					0.8, 0.8, 0.8, true)
				GameTooltip:Show()
			end
		end)
		r.cell:SetScript("OnLeave", function()
			if GameTooltip then
				GameTooltip:Hide()
			end
		end)
		popupRows[i] = r
	end
end

function Grid_OpenExceptions(paladin, class, anchorCell)
	if not popup then
		buildPopup()
	end
	popup.paladin, popup.class = paladin, class
	popup.titleText:SetText((manager():NameOf(paladin)) .. " → " .. (CLASS_NAMES[class] or class))
	popup:ClearAllPoints()
	if anchorCell then
		popup:SetPoint("TOPLEFT", anchorCell, "BOTTOMLEFT", 0, -4)
	else
		popup:SetPoint("CENTER")
	end
	popup:Show()
	refreshPopup()
end
Grid.OpenExceptions = Grid_OpenExceptions
Grid.popupRows = popupRows -- for tests and debugging

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
	if popup then
		popup:Hide()
	end
end

local function refresh()
	Grid:Refresh()
	refreshPopup()
end
PK:On("PK_BLESSINGS_CHANGED", Grid, refresh)
PK:On("PK_ROSTER_UPDATED", Grid, refresh)
PK:On("PK_PROFILE_CHANGED", Grid, refresh)
