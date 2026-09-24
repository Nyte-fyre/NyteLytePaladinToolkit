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
	for _, entry in ipairs(currentList()) do
		local spell = resolveEntry(entry)
		local _, groupOnly = splitEntry(entry)
		if spell and spell.spellID and (spell.known or s.showUnknown) and (grouped or not groupOnly) then
			local icon = Frames:AcquireIcon(anchor, s.iconSize)
			icon:SetSpell(spell.spellID)
			icon.known = spell.known
			icon.cooldown:SetHideCountdownNumbers(false)
			icons[#icons + 1] = icon
			layoutIcon(#icons, icon, s)
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
	self:Rebuild()
end

function M:IconCount()
	return #icons
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
	elseif sub == "reset" then
		PK.profile.cooldownLists[spec] = PK.Config.DeepCopy(PK.Presets.cooldownLists[spec])
		PK:Print("cooldown list reset for " .. PK.SpecProfile.LABELS[spec] .. ".")
	else
		local names = {}
		for _, e in ipairs(list) do
			local spell = resolveEntry(e)
			names[#names + 1] = entryLabel(e) .. ((spell and spell.known) and "" or " |cff808080(not learned)|r")
		end
		PK:Print(PK.SpecProfile.LABELS[spec] .. " cooldowns: " .. (#names > 0 and table.concat(names, ", ") or "none"))
		PK:Print("change with /ptk cd add <spell>, remove <spell>, group <spell> (toggle group-only), reset")
		return
	end
	PK:Fire("PK_SETTINGS_CHANGED")
end, "list | add <spell> | remove <spell> | group <spell> | reset - edit this spec's cooldown bar")
