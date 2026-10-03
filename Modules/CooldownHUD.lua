local _, PK = ...

-- Cooldown HUD: a row of icons for your own spells, from the per-spec list
-- (Data/Presets.lua defaults, editable with /ptk cd). Replaces the
-- WeakAuras cooldown rows.
--
-- Combat-safe by design: probe #1 showed cooldown start/duration are secret
-- in combat but isActive stays readable, so the swipe is always drawn from
-- the client's duration object (display-only) and numbers are only used when
-- they're readable. Probe #2 showed isActive and isOnGCD stay readable in
-- combat, so "on cooldown" = isActive and not just the global cooldown.
-- Spells you haven't learned are hidden unless "showUnknown" is on.
-- Entries are registry keys (e.g. "HOLY_SHOCK") or "name:<Spell Name>" for
-- spells outside the registry; a "@group" suffix shows the spell only while
-- you're in a party or raid (e.g. Cleanse, useless when solo leveling).

local Compat = PK.Compat
local Frames = PK.Frames
local M = PK:RegisterModule("CooldownHUD", {})

local icons = {}

local function settings()
	return PK.Config:GetModuleSettings("CooldownHUD")
end

local function currentList()
	return PK.profile.cooldownLists[PK.SpecProfile:GetSpec()] or {}
end

-- "PURIFY@group" -> "PURIFY", true
local function splitEntry(entry)
	local base, flag = entry:match("^(.-)@(%a+)$")
	if base then
		return base, flag == "group"
	end
	return entry, false
end

local function inGroup()
	return (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) or false
end

-- Resolves a list entry to { spellID, name, icon, known } or nil.
local function resolveEntry(entry)
	if type(entry) ~= "string" then
		return nil
	end
	entry = splitEntry(entry)
	local custom = entry:match("^name:(.+)$")
	if custom then
		local info = Compat.GetSpellInfo(custom)
		if not info or not info.spellID then
			return nil
		end
		return {
			spellID = info.spellID,
			name = info.name,
			icon = info.iconID,
			known = Compat.IsSpellKnown(info.spellID) == true,
		}
	end
	return PK.SpellRegistry:Get(entry)
end

local function layoutIcon(i, icon, s)
	local size, spacing, perRow = s.iconSize or 36, s.spacing or 4, math.max(1, s.perRow or 12)
	local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
	local step = size + spacing
	local dir = s.direction or "RIGHT"
	local x, y
	if dir == "LEFT" then
		x, y = -col * step, -row * step
	elseif dir == "DOWN" then
		x, y = row * step, -col * step
	elseif dir == "UP" then
		x, y = row * step, col * step
	else
		x, y = col * step, -row * step
	end
	icon:SetSize(size, size)
	icon:ClearAllPoints()
	icon:SetPoint(dir == "LEFT" and "TOPRIGHT" or "TOPLEFT", icon:GetParent(),
		dir == "LEFT" and "TOPRIGHT" or "TOPLEFT", x, y)
end

-- Reordering ------------------------------------------------------------------------------
-- While frames are unlocked: click an icon to pick it up, then click the
-- spot it should go (it takes that icon's place; the others shift over).
-- Right-click or clicking it again cancels. Dragging still moves the bar.

local picked -- list index of the picked-up icon

local function clearPick()
	picked = nil
	for _, icon in ipairs(icons) do
		if icon.pickGlow then
			icon.pickGlow:Hide()
		end
	end
end

-- Moves entry `from` of this spec's list to position `to`.
function M:MoveEntry(from, to)
	local list = currentList()
	if not list[from] or type(to) ~= "number" then
		return false
	end
	to = math.max(1, math.min(#list, math.floor(to)))
	if from ~= to then
		table.insert(list, to, table.remove(list, from))
		PK:Fire("PK_SETTINGS_CHANGED")
	end
	return true
end

local function onIconClick(icon, button)
	if PK.profile.locked then
		return
	end
	if button == "RightButton" or picked == icon.listIndex then
		clearPick()
	elseif not picked then
		picked = icon.listIndex
		icon.pickGlow:Show()
	else
		local from = picked
		clearPick()
		M:MoveEntry(from, icon.listIndex)
	end
end

local function forwardToBar(script)
	return function(self)
		self.dragged = true
		local bar = self:GetParent()
		local fn = bar and bar:GetScript(script)
		if fn then
			fn(bar)
		end
	end
end

local function makeArrangeable(icon)
	if not icon.pickGlow then
		icon.pickGlow = icon:CreateTexture(nil, "OVERLAY")
		icon.pickGlow:SetAllPoints()
		icon.pickGlow:SetColorTexture(1, 0.85, 0.3, 0.45)
		icon.pickGlow:SetBlendMode("ADD")
	end
	icon.pickGlow:SetShown(picked ~= nil and picked == icon.listIndex)
	icon:EnableMouse(not PK.profile.locked)
	icon:RegisterForDrag("LeftButton")
	icon:SetScript("OnMouseDown", function(self)
		self.dragged = false
	end)
	icon:SetScript("OnMouseUp", function(self, button)
		if not self.dragged then
			onIconClick(self, button)
		end
	end)
	icon:SetScript("OnDragStart", forwardToBar("OnDragStart"))
	icon:SetScript("OnDragStop", forwardToBar("OnDragStop"))
	icon:SetScript("OnEnter", function(self)
		if GameTooltip and not PK.profile.locked then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(PK.displayName)
			GameTooltip:AddLine(picked and "Click to put the picked-up icon here. Right-click cancels."
				or "Click to pick up this icon, then click where it should go.", 1, 1, 1, true)
			GameTooltip:AddLine("Drag to move the whole bar.", 0.7, 0.7, 0.7, true)
			GameTooltip:Show()
		end
	end)
	icon:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
end

-- Rebuilds the icon list (spec change, list edit, spells learned).
function M:Rebuild()
	if not self.enabled then
		return
	end
	local s = settings()
	local anchor = Frames:GetAnchor("CooldownHUD")
	for _, icon in ipairs(icons) do
		Frames:ReleaseIcon(icon)
	end
	icons = {}
	local grouped = inGroup()
	for index, entry in ipairs(currentList()) do
		local spell = resolveEntry(entry)
		local _, groupOnly = splitEntry(entry)
		if spell and spell.spellID and (spell.known or s.showUnknown) and (grouped or not groupOnly) then
			local icon = Frames:AcquireIcon(anchor, s.iconSize)
			icon:SetSpell(spell.spellID)
			icon.known = spell.known
			icon.listIndex = index
			icon.cooldown:SetHideCountdownNumbers(false)
			icons[#icons + 1] = icon
			layoutIcon(#icons, icon, s)
			makeArrangeable(icon)
		end
	end
	local size, spacing = s.iconSize or 36, s.spacing or 4
	local count = math.max(1, #icons)
	local perRow = math.max(1, s.perRow or 12)
	local cols, rows = math.min(count, perRow), math.ceil(count / perRow)
	local long, short = cols * (size + spacing), rows * (size + spacing)
	if s.direction == "DOWN" or s.direction == "UP" then
		anchor:SetSize(short, long)
	else
		anchor:SetSize(math.max(160, long), short)
	end
	self:Update()
end

-- Refreshes cooldown swipes and usability.
function M:Update()
	if not self.enabled then
		return
	end
	local s = settings()
	for _, icon in ipairs(icons) do
		if not icon.known then
			icon:SetState("unusable")
		else
			icon:RefreshCooldown(s.dimUnusable)
		end
	end
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
	PK:On("PK_LOCK_CHANGED", self, function()
		clearPick()
		rebuild()
	end)
	PK:RegisterEvent("SPELL_UPDATE_COOLDOWN", self, update)
	PK:RegisterEvent("SPELL_UPDATE_USABLE", self, update)
	PK:RegisterEvent("SPELL_UPDATE_CHARGES", self, update)
	PK:RegisterEvent("PLAYER_REGEN_ENABLED", self, update)
	PK:RegisterEvent("PLAYER_REGEN_DISABLED", self, update)
	PK:RegisterEvent("GROUP_ROSTER_UPDATE", self, function()
		PK:Debounce("CooldownHUD.group", 0.5, rebuild)
	end)
	self:Rebuild()
end

function M:OnDisable()
	PK:Off("PK_SPELLS_UPDATED", self)
	PK:Off("PK_PROFILE_CHANGED", self)
	PK:Off("PK_SETTINGS_CHANGED", self)
	PK:Off("PK_LOCK_CHANGED", self)
	clearPick()
	for _, ev in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "SPELL_UPDATE_CHARGES",
		"PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE" }) do
		PK:UnregisterEvent(ev, self)
	end
	for _, icon in ipairs(icons) do
		Frames:ReleaseIcon(icon)
	end
	icons = {}
end

function M:OnSpecChanged()
	clearPick()
	self:Rebuild()
end

function M:IconCount()
	return #icons
end

-- The bar's icons in display order (tests).
function M:GetIcons()
	return icons
end

-- spellID -> icon state, for tests and debugging.
function M:IconStates()
	local out = {}
	for _, icon in ipairs(icons) do
		out[icon.spellID] = icon.state
	end
	return out
end

-- /ptk cd list | add <spell name> | remove <spell name> | reset ----------------------------------

local function findRegistryKey(name)
	local lname = name:lower()
	for _, entry in ipairs(PK.Spells.list) do
		for _, n in ipairs(entry.names) do
			if n:lower() == lname then
				return entry.key
			end
		end
	end
	return nil
end

local function entryLabel(entry)
	local base, groupOnly = splitEntry(entry)
	local suffix = groupOnly and " |cff80c0ff(group only)|r" or ""
	local custom = base:match("^name:(.+)$")
	if custom then
		return custom .. suffix
	end
	local e = PK.Spells.byKey[base]
	return (e and e.names[1] or base) .. suffix
end

local function plainLabel(entry)
	return (entryLabel(entry):gsub(" |c.*$", ""))
end

PK:RegisterCommand("cd", function(args, raw)
	local spec = PK.SpecProfile:GetSpec()
	local list = PK.profile.cooldownLists[spec]
	local sub = args[1]
	local name = table.concat(raw, " ", 2) -- spell name as typed
	local lname = name:lower()
	if sub == "add" and name ~= "" then
		local key = findRegistryKey(name) or ("name:" .. name)
		for _, e in ipairs(list) do
			if splitEntry(e) == key then
				PK:Print(entryLabel(e) .. " is already on the list.")
				return
			end
		end
		list[#list + 1] = key
		PK:Print("added " .. entryLabel(key) .. " to the " .. PK.SpecProfile.LABELS[spec] .. " cooldowns.")
	elseif sub == "remove" and name ~= "" then
		local key = findRegistryKey(name) or ("name:" .. name)
		for i, e in ipairs(list) do
			if splitEntry(e) == key or plainLabel(e):lower() == lname then
				table.remove(list, i)
				PK:Print("removed " .. plainLabel(e) .. ".")
				PK:Fire("PK_SETTINGS_CHANGED")
				return
			end
		end
		PK:Print("not on the list: " .. name)
		return
	elseif sub == "group" and name ~= "" then
		local key = findRegistryKey(name) or ("name:" .. name)
		for i, e in ipairs(list) do
			local base, groupOnly = splitEntry(e)
			if base == key or plainLabel(e):lower() == lname then
				list[i] = groupOnly and base or (base .. "@group")
				PK:Print(plainLabel(e) .. (groupOnly and " now shows all the time." or " now shows only in a group."))
				PK:Fire("PK_SETTINGS_CHANGED")
				return
			end
		end
		PK:Print("not on the list: " .. name)
		return
	elseif sub == "move" and #raw >= 3 then
		-- /ptk cd move <spell name> <position | first | last>
		local where = args[#args]
		local spellName = table.concat(raw, " ", 2, #raw - 1)
		local to = where == "first" and 1 or where == "last" and #list or tonumber(where)
		local key = findRegistryKey(spellName) or ("name:" .. spellName)
		local from
		for i, e in ipairs(list) do
			if splitEntry(e) == key or plainLabel(e):lower() == spellName:lower() then
				from = i
				break
			end
		end
		if not from then
			PK:Print("not on the list: " .. spellName)
			return
		end
		if not to then
			PK:Print("usage: /ptk cd move <spell> <position, first or last>")
			return
		end
		to = math.max(1, math.min(#list, math.floor(to)))
		M:MoveEntry(from, to)
		PK:Print(string.format("%s is now #%d of %d.", plainLabel(list[to]), to, #list))
		return
	elseif sub == "reset" then
		PK.profile.cooldownLists[spec] = PK.Config.DeepCopy(PK.Presets.cooldownLists[spec])
		PK:Print("cooldown list reset for " .. PK.SpecProfile.LABELS[spec] .. ".")
	else
		local names = {}
		for i, e in ipairs(list) do
			local spell = resolveEntry(e)
			names[#names + 1] = i .. ". " .. entryLabel(e)
				.. ((spell and spell.known) and "" or " |cff808080(not learned)|r")
		end
		PK:Print(PK.SpecProfile.LABELS[spec] .. " cooldowns: " .. (#names > 0 and table.concat(names, ", ") or "none"))
		PK:Print("change with /ptk cd add <spell>, remove <spell>, move <spell> <position|first|last>, "
			.. "group <spell> (toggle group-only), reset")
		PK:Print("or /ptk unlock, click an icon on the bar, then click where it should go.")
		return
	end
	PK:Fire("PK_SETTINGS_CHANGED")
end, "list | add <spell> | remove <spell> | move <spell> <pos> | group <spell> | reset - edit this spec's cooldown bar")
