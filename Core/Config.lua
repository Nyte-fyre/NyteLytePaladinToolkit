local _, PK = ...

-- SavedVariables layout, per-character profiles, defaults, migration and
-- profile export/import.
--
-- NyteLytePaladinToolkitDB = {
--   version = 3,
--   profileKeys = { ["Char-Realm"] = "Default" },
--   profiles = { Default = { specMode, locked, modules, layout, cooldownLists, alerts, blessing } },
--   meta, probe, probeCombat, errors, debugLog, debug  -- diagnostics, not part of profiles
-- }
--
-- Messages fired: PK_PROFILE_CHANGED (profile swapped, reset or imported),
-- PK_MODULES_CHANGED (a module toggle changed), PK_LAYOUT_CHANGED.

local Presets = PK.Presets
local Config = {}
PK.Config = Config

local DB_VERSION = 3
Config.DB_VERSION = DB_VERSION

-- Table helpers ----------------------------------------------------------------------

local function isArray(t)
	return type(t) == "table" and t[1] ~= nil
end

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, val in pairs(v) do
		out[k] = deepCopy(val)
	end
	return out
end
Config.DeepCopy = deepCopy

-- Adds any keys missing from target, never overwriting what's there. Lists
-- (like cooldown lists) are treated as one value so removed entries stay removed.
local function fillDefaults(target, defaults)
	for k, v in pairs(defaults) do
		if target[k] == nil then
			target[k] = deepCopy(v)
		elseif type(v) == "table" and type(target[k]) == "table" and not isArray(v) then
			fillDefaults(target[k], v)
		end
	end
	return target
end
Config.FillDefaults = fillDefaults

-- Keeps only keys that exist in defaults with a matching type. An empty
-- defaults table or a list means "free-form": the imported table is kept whole.
local function sanitize(imported, defaults)
	local out = {}
	for k, v in pairs(imported) do
		local d = defaults[k]
		if d ~= nil and type(v) == type(d) then
			if type(v) == "table" and next(d) ~= nil and not isArray(d) then
				out[k] = sanitize(v, d)
			else
				out[k] = deepCopy(v)
			end
		end
	end
	return out
end

-- Defaults ------------------------------------------------------------------------------

function Config.BuildDefaults()
	local layout = {}
	for _, spec in ipairs({ "holy", "prot", "ret" }) do
		layout[spec] = Presets.LayoutFor(spec)
	end
	return {
		specMode = "auto",
		locked = true,
		modules = deepCopy(Presets.modules),
		layout = layout,
		cooldownLists = deepCopy(Presets.cooldownLists),
		alerts = { sound = true, expiringThresholdSec = 120 },
		moduleSettings = deepCopy(Presets.moduleSettings),
		-- assignments: { [paladin] = row } (see Logic/Blessings.lua)
		blessing = { assignments = {}, autoSuggest = true, refreshMinutes = 5 },
	}
end

-- Migration --------------------------------------------------------------------------------

-- Upgrades an older saved-variables table in place. Add a step per version bump.
function Config.Migrate(db)
	local v = tonumber(db.version) or 0
	if v < 1 then
		db.profileKeys = db.profileKeys or {}
		db.profiles = db.profiles or {}
		v = 1
	end
	if v < 2 then
		-- Holy default list changed (HoJ added, Cleanse/Purify group-only):
		-- upgrade profiles still using an old default, leave edited ones alone.
		for _, profile in pairs(db.profiles) do
			Config.UpgradeDefaultLists(profile)
		end
		v = 2
	end
	if v < 3 then
		-- Prot/Ret default lists changed (Tank Kit took over Prot's rotation).
		for _, profile in pairs(db.profiles) do
			Config.UpgradeDefaultLists(profile)
		end
		v = 3
	end
	db.version = v
	return db
end

local function sameList(a, b)
	if type(a) ~= "table" or #a ~= #b then
		return false
	end
	for i = 1, #b do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

-- Replaces a spec's cooldown list with the current default if it exactly
-- matches an earlier default (i.e. the player never edited it).
function Config.UpgradeDefaultLists(profile)
	local lists = type(profile) == "table" and profile.cooldownLists
	if type(lists) ~= "table" then
		return
	end
	for spec, olds in pairs(Presets.previousCooldownLists) do
		for _, old in ipairs(olds) do
			if sameList(lists[spec], old) then
				lists[spec] = deepCopy(Presets.cooldownLists[spec])
			end
		end
	end
end

-- Setup -------------------------------------------------------------------------------------

local function characterKey()
	local ok, name = pcall(UnitName, "player")
	local okR, realm = pcall(GetRealmName)
	return (ok and name or "Unknown") .. "-" .. (okR and realm or "Unknown")
end

function Config:Init(db)
	self.db = Config.Migrate(db)
	self.charKey = characterKey()
	local name = db.profileKeys[self.charKey] or "Default"
	self:SetProfile(name, true)
end

-- Switches this character to profile `name`, creating it from defaults if new.
function Config:SetProfile(name, silent)
	local db = self.db
	db.profileKeys[self.charKey] = name
	db.profiles[name] = fillDefaults(db.profiles[name] or {}, Config.BuildDefaults())
	self.profileName = name
	PK.profile = db.profiles[name]
	if not silent then
		PK:Fire("PK_PROFILE_CHANGED")
	end
end

function Config:GetProfileName()
	return self.profileName
end

function Config:ListProfiles()
	local names = {}
	for name in pairs(self.db.profiles) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

function Config:ResetProfile()
	self.db.profiles[self.profileName] = Config.BuildDefaults()
	PK.profile = self.db.profiles[self.profileName]
	PK:Fire("PK_PROFILE_CHANGED")
end

-- Modules -----------------------------------------------------------------------------------

function Config:IsModuleEnabled(module, spec)
	local m = PK.profile and PK.profile.modules[spec]
	return m and m[module] == true or false
end

function Config:SetModuleEnabled(module, spec, enabled)
	local m = PK.profile.modules[spec]
	if m then
		m[module] = enabled and true or false
		PK:Fire("PK_MODULES_CHANGED", module, spec)
	end
end

-- Layout --------------------------------------------------------------------------------------

function Config:GetLayout(spec, module)
	local l = PK.profile.layout[spec]
	if not l then
		return nil
	end
	if not l[module] then
		l[module] = Presets.LayoutFor(spec)[module] or { point = "CENTER", x = 0, y = 0, scale = 1 }
	end
	return l[module]
end

function Config:SetLayout(spec, module, point, x, y)
	local l = self:GetLayout(spec, module)
	if l then
		l.point, l.x, l.y = point, x, y
		PK:Fire("PK_LAYOUT_CHANGED", module, spec)
	end
end

function Config:ResetLayout(spec)
	PK.profile.layout[spec] = Presets.LayoutFor(spec)
	PK:Fire("PK_LAYOUT_CHANGED", nil, spec)
end

-- Module options ------------------------------------------------------------------------------

function Config:GetModuleSettings(module)
	return PK.profile.moduleSettings[module]
end

-- Export / import ------------------------------------------------------------------------------

function Config:ExportProfile()
	return PK.Serializer.Encode(PK.profile)
end

-- Replaces the current profile with an imported string.
-- Returns true, or false and a user-readable reason.
function Config:ImportProfile(str)
	local tbl, err = PK.Serializer.Decode(str)
	if not tbl then
		return false, err
	end
	local defaults = Config.BuildDefaults()
	local clean = sanitize(tbl, defaults)
	if next(clean) == nil then
		return false, "the string didn't contain any Paladin Toolkit settings"
	end
	if not PK.SpecDecision.IsSpec(clean.specMode) and clean.specMode ~= "auto" then
		clean.specMode = nil
	end
	self.db.profiles[self.profileName] = fillDefaults(clean, defaults)
	PK.profile = self.db.profiles[self.profileName]
	PK:Fire("PK_PROFILE_CHANGED")
	return true
end

PK:On("PK_DB_READY", Config, function(_, _, db)
	Config:Init(db)
end)
