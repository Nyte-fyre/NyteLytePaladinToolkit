local _, PK = ...

-- /ptk probe: records what this client actually supports into
-- NyteLytePaladinToolkitDB.probe (on disk after /reload) and shows it in a copy window.
-- /ptk probe combat: arms a capture that samples the player's own auras,
-- cooldowns and unit values during the next combat, to learn which of them
-- are secret. Nothing here compares or does math on API values without
-- going through Compat.Describe / Compat.IsSecret first.

local Compat = PK.Compat
local Describe = Compat.Describe
local D = PK:RegisterModule("Diagnostics", { alwaysOn = true })

-- Helpers ---------------------------------------------------------------------

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		local ta, tb = type(a), type(b)
		if ta ~= tb then
			return ta == "number"
		end
		return a < b
	end)
	return keys
end

local function pack(...)
	return select("#", ...), { ... }
end

-- Calls fn(...) and returns every return value described (never secret).
local function tryCall(fn, ...)
	if type(fn) ~= "function" then
		return "missing"
	end
	local n, r = pack(pcall(fn, ...))
	if not r[1] then
		return "error: " .. tostring(r[2])
	end
	local out = {}
	for i = 2, n do
		out[i - 1] = Describe(r[i])
	end
	return out
end

local function tryPath(path, ...)
	local fn = Compat.Resolve(path)
	if fn == nil then
		return "missing"
	end
	return tryCall(fn, ...)
end

-- Describes every field of a table returned by an API (one level deep).
local function describeFields(t)
	if Compat.IsSecret(t) then
		return "<secret table>"
	end
	if type(t) ~= "table" then
		return Describe(t)
	end
	local out = {}
	local ok, err = pcall(function()
		for k, v in pairs(t) do
			local tk = type(k)
			if tk == "string" or tk == "number" then
				out[k] = Describe(v)
			end
		end
	end)
	if not ok then
		return "error reading fields: " .. tostring(err)
	end
	return out
end

-- Lists method names of an object (a table mixin or a userdata with a
-- metatable). Returns a sorted list or a string explaining why not.
local function listMethods(obj)
	if Compat.IsSecret(obj) then
		return "<secret>"
	end
	local names = {}
	local function collect(t)
		if type(t) ~= "table" then
			return
		end
		for k, v in pairs(t) do
			if type(k) == "string" and type(v) == "function" then
				names[k] = true
			end
		end
	end
	if type(obj) == "table" then
		collect(obj)
	end
	local ok, mt = pcall(getmetatable, obj)
	if ok and type(mt) == "table" then
		collect(mt.__index)
	elseif ok and mt ~= nil then
		names["<metatable: " .. tostring(Describe(mt)) .. ">"] = true
	end
	return sortedKeys(names)
end

-- Calls every no-argument getter on obj (Get*/Is*/Has*) and describes the
-- results. Used on cooldown duration objects to see what they expose.
local function sampleGetters(obj, methods)
	if type(methods) ~= "table" then
		return nil
	end
	local out = {}
	for _, name in ipairs(methods) do
		if name:find("^Get") or name:find("^Is") or name:find("^Has") then
			local ok, fn = pcall(function()
				return obj[name]
			end)
			if ok and type(fn) == "function" then
				local r = tryCall(fn, obj)
				if type(r) == "table" then
					out[name] = r[1] == nil and "nil" or r[1]
				else
					out[name] = r
				end
			end
		end
	end
	return out
end

-- Serializes a probe table as indented text for the copy window.
local function dump(value, indent, lines, depth)
	indent = indent or ""
	lines = lines or {}
	depth = depth or 0
	if type(value) ~= "table" then
		lines[#lines + 1] = indent .. tostring(value)
		return lines
	end
	for _, k in ipairs(sortedKeys(value)) do
		local v = value[k]
		local label = indent .. tostring(k) .. " = "
		if type(v) == "table" then
			if depth >= 8 then
				lines[#lines + 1] = label .. "{...}"
			elseif next(v) == nil then
				lines[#lines + 1] = label .. "{}"
			else
				-- Short flat lists of plain values go on one line.
				local flat, n = true, 0
				for kk, vv in pairs(v) do
					n = n + 1
					if type(kk) ~= "number" or type(vv) == "table" then
						flat = false
					end
				end
				if flat and n <= 12 then
					local parts = {}
					for i = 1, n do
						parts[i] = tostring(v[i])
					end
					lines[#lines + 1] = label .. "[" .. table.concat(parts, ", ") .. "]"
				else
					lines[#lines + 1] = label .. "{"
					dump(v, indent .. "  ", lines, depth + 1)
					lines[#lines + 1] = indent .. "}"
				end
			end
		else
			lines[#lines + 1] = label .. tostring(v)
		end
	end
	return lines
end

-- What to check ---------------------------------------------------------------

local API_PATHS = {
	-- secret values
	"issecretvalue", "canaccessvalue", "canaccesstable", "canaccessallvalues", "issecrettable",
	"scrubsecretvalues", "C_Secrets", "C_CurveUtil", "C_DurationUtil", "C_StringUtil",
	-- auras
	"C_UnitAuras", "C_UnitAuras.GetAuraDataByIndex", "C_UnitAuras.GetPlayerAuraBySpellID",
	"C_UnitAuras.GetAuraDataBySpellName", "C_UnitAuras.GetUnitAuras", "C_UnitAuras.GetAuraDuration",
	"C_UnitAuras.GetAuraDataByAuraInstanceID", "C_UnitAuras.GetBuffDataByIndex",
	-- spells and cooldowns
	"C_Spell", "C_Spell.GetSpellInfo", "C_Spell.GetSpellName", "C_Spell.GetSpellTexture",
	"C_Spell.GetSpellCooldown", "C_Spell.GetSpellCooldownDuration", "C_Spell.GetSpellCharges",
	"C_Spell.GetSpellChargeDuration", "C_Spell.IsSpellUsable", "C_Spell.IsSpellInRange",
	"C_SpellBook", "C_SpellBook.GetSpellBookItemInfo", "C_SpellBook.IsSpellKnown",
	"C_SpellBook.GetNumSpellBookSkillLines", "C_SpellBook.FindSpellBookSlotForSpell",
	"IsPlayerSpell", "C_CooldownViewer",
	-- talents / spec
	"C_ClassTalents", "C_Traits", "C_SpecializationInfo", "C_Talent", "C_TalentUI",
	"GetSpecialization", "GetPrimaryTalentTree", "GetActiveTalentGroup", "GetUnspentTalentPoints",
	"UnitCharacterPoints",
	-- shapeshift (paladin auras sit on the stance bar in some versions)
	"GetShapeshiftForm", "GetShapeshiftFormInfo", "GetNumShapeshiftForms",
	-- units
	"UnitGetTotalAbsorbs", "UnitHealthPercent", "UnitHealth", "UnitPower",
	-- comms and group
	"C_ChatInfo", "C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.SendAddonMessage",
	"C_ChatInfo.IsAddonMessagePrefixRegistered", "C_ChatInfo.InChatMessagingLockdown",
	"GetNumGroupMembers", "IsInRaid", "UnitIsGroupLeader", "UnitIsGroupAssistant", "GetReadyCheckStatus",
	-- UI
	"Settings", "Settings.RegisterCanvasLayoutCategory", "Settings.RegisterVerticalLayoutCategory",
	"Settings.RegisterAddOnCategory", "Settings.OpenToCategory", "InterfaceOptions_AddCategory",
	"C_Timer.After", "C_Timer.NewTicker", "C_AddOns.GetAddOnMetadata", "PlaySound", "SOUNDKIT",
	"C_DamageMeter", "C_EncounterJournal",
}

-- Reported as removed in Forever beta; true here means still present.
local LEGACY_GLOBALS = {
	"GetItemInfo", "GetSpellInfo", "GetSpellBookItemName", "GetSpellBookItemInfo", "GetNumSpellTabs",
	"GetSpellTabInfo", "GetNumTalentTabs", "GetTalentTabInfo", "GetTalentInfo", "GetNumTalents",
	"GetSpellCooldown", "GetSpellTexture", "GetSpellLink", "IsSpellKnown", "UnitAura", "UnitBuff",
	"UnitDebuff", "GetAddOnMetadata", "SendAddonMessage", "RegisterAddonMessagePrefix",
	"InterfaceOptions_AddCategory", "CombatLogGetCurrentEventInfo",
}

-- Namespaces whose function lists are always recorded, plus any C_* whose
-- name matches one of the patterns below.
local NAMESPACES = {
	"C_Spell", "C_SpellBook", "C_UnitAuras", "C_Secrets", "C_CurveUtil", "C_DurationUtil",
	"C_ChatInfo", "C_ClassTalents", "C_Traits", "C_SpecializationInfo", "C_Talent", "Settings",
}
local NAMESPACE_PATTERNS = { "Talent", "Spec", "Trait", "Cooldown", "Aura", "Secret", "Duration", "Restrict" }

local EVENTS = {
	"PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED",
	"PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
	"LEARNED_SPELL_IN_SKILL_LINE", "UNIT_AURA", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE",
	"SPELL_UPDATE_CHARGES", "ACTIONBAR_UPDATE_COOLDOWN", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS",
	"UNIT_ABSORB_AMOUNT_CHANGED", "READY_CHECK", "ENCOUNTER_START", "ENCOUNTER_END", "CHAT_MSG_ADDON",
	"GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_SPELLCAST_SUCCEEDED",
	"ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_LEVEL_UP",
}

local TEMPLATES = {
	{ "Frame", "BasicFrameTemplateWithInset" }, { "Frame", "BackdropTemplate" },
	{ "Frame", "SettingsListTemplate" }, { "ScrollFrame", "UIPanelScrollFrameTemplate" },
	{ "Button", "UIPanelButtonTemplate" }, { "Button", "SecureActionButtonTemplate" },
	{ "Cooldown", "CooldownFrameTemplate" }, { "CheckButton", "UICheckButtonTemplate" },
	{ "Slider", "OptionsSliderTemplate" }, { "Slider", "MinimalSliderTemplate" },
	{ "Frame", "UIDropDownMenuTemplate" }, { "DropdownButton", "WowStyle1DropdownTemplate" },
}

-- Widget methods we plan to rely on.
local WIDGET_METHODS = {
	Cooldown = { "SetCooldown", "SetCooldownFromDurationObject", "SetCooldownDuration", "SetDrawEdge",
		"SetHideCountdownNumbers", "SetUseAuraDisplayTime", "Clear", "SetSwipeColor" },
	StatusBar = { "SetMinMaxValues", "SetValue", "SetTimerDuration", "SetStatusBarTexture" },
	Texture = { "SetDesaturated", "SetTexture", "SetVertexColor" },
}

-- Probe sections ----------------------------------------------------------------

local function probeClient()
	local version, build, date, interface = GetBuildInfo()
	local c = { version = version, build = build, date = date, interface = interface }
	c.projectIds = {}
	for k, v in pairs(_G) do
		if type(k) == "string" and k:find("^WOW_PROJECT_") then
			c.projectIds[k] = Describe(v)
		end
	end
	c.locale = GetLocale and GetLocale()
	c.addonVersion = PK.version
	c.addonFolder = PK.name
	c.expectedBetaPath = "World of Warcraft\\_classic_beta_\\Interface\\AddOns\\" .. PK.name
	local _, class = UnitClass("player")
	c.class = class
	c.level = UnitLevel("player")
	c.race = select(2, UnitRace("player"))
	c.inGroup = IsInGroup and IsInGroup() or false
	c.inRaid = IsInRaid and IsInRaid() or false
	return c
end

local function probeApi()
	local out = {}
	for _, path in ipairs(API_PATHS) do
		out[path] = type(Compat.Resolve(path))
	end
	return out
end

local function probeLegacy()
	local present = {}
	for _, name in ipairs(LEGACY_GLOBALS) do
		present[name] = _G[name] ~= nil
	end
	return present
end

local function probeNamespaces()
	local all, detail = {}, {}
	local wanted = {}
	for _, n in ipairs(NAMESPACES) do
		wanted[n] = true
	end
	for k, v in pairs(_G) do
		if type(k) == "string" and k:find("^C_") and type(v) == "table" then
			all[#all + 1] = k
			for _, p in ipairs(NAMESPACE_PATTERNS) do
				if k:find(p) then
					wanted[k] = true
				end
			end
		end
	end
	table.sort(all)
	for name in pairs(wanted) do
		local ns = _G[name]
		if type(ns) == "table" then
			local fns = {}
			for fk, fv in pairs(ns) do
				if type(fk) == "string" and type(fv) == "function" then
					fns[#fns + 1] = fk
				end
			end
			table.sort(fns)
			detail[name] = table.concat(fns, ", ")
		else
			detail[name] = "missing"
		end
	end
	return { all = table.concat(all, ", "), functions = detail }
end

local function probeEvents()
	local f = CreateFrame("Frame")
	local out = {}
	for _, ev in ipairs(EVENTS) do
		local ok, err = pcall(f.RegisterEvent, f, ev)
		out[ev] = ok and "ok" or ("unknown: " .. tostring(err))
	end
	f:UnregisterAllEvents()
	return out
end

local templateFrames = {}
local function probeWidgets()
	local out = { templates = {}, methods = {} }
	for _, t in ipairs(TEMPLATES) do
		local key = t[1] .. ":" .. t[2]
		local ok, res = pcall(CreateFrame, t[1], nil, UIParent, t[2])
		out.templates[key] = ok and "ok" or tostring(res)
		if ok and res then
			res:Hide()
			templateFrames[key] = res
		end
	end
	for widgetType, methods in pairs(WIDGET_METHODS) do
		local ok, w
		if widgetType == "Texture" then
			ok, w = pcall(UIParent.CreateTexture, UIParent)
		else
			ok, w = pcall(CreateFrame, widgetType, nil, UIParent)
		end
		local found = {}
		for _, m in ipairs(methods) do
			found[m] = ok and w and type(w[m]) == "function" or false
		end
		if ok and w and w.Hide then
			w:Hide()
		end
		out.methods[widgetType] = ok and found or ("cannot create: " .. tostring(w))
	end
	return out
end

local function probeSpellbook()
	local book, method, err = Compat.ScanSpellbook()
	local lines = {}
	for i, item in ipairs(book) do
		lines[i] = string.format("%s | id=%s | %s%s%s | %s", tostring(item.name), tostring(item.spellID),
			tostring(item.itemType or "?"), item.isPassive and " passive" or "", item.isOffSpec and " offspec" or "",
			tostring(item.skillLine))
	end
	return { method = method, error = err, count = #book, entries = lines }, book
end

local function probeRegistry(bookIndex)
	local out, unresolved = {}, {}
	local resolved = {}
	for _, entry in ipairs(PK.Spells.list) do
		local r = PK.Spells.Resolve(entry, bookIndex)
		resolved[entry.key] = r
		out[entry.key] = string.format("%s | id=%s | known=%s | via %s%s", tostring(r.name or entry.names[1]),
			tostring(r.spellID), tostring(r.known), tostring(r.method), entry.verify and " | (verify)" or "")
		if not r.method then
			unresolved[#unresolved + 1] = entry.names[1]
		end
	end
	table.sort(unresolved)
	return { entries = out, unresolved = unresolved }, resolved
end

local TREE_NAMES = { "holy", "prot", "ret" }

local function specFromName(name)
	if type(name) ~= "string" then
		return nil
	end
	local l = name:lower()
	if l:find("holy") then
		return "holy"
	elseif l:find("prot") then
		return "prot"
	elseif l:find("retri") then
		return "ret"
	end
	return nil
end

local function probeSpec(resolved)
	local s = { strategies = {} }
	local points = {}

	-- Legacy talent tabs, if the client still has them.
	local numTabs = tryPath("GetNumTalentTabs")
	s.strategies.legacyTabs = { numTabs = numTabs }
	if type(numTabs) == "table" and type(numTabs[1]) == "number" then
		for i = 1, numTabs[1] do
			local r = tryPath("GetTalentTabInfo", i)
			s.strategies.legacyTabs["tab" .. i] = r
			if type(r) == "table" then
				-- Classic order: name, icon, pointsSpent; later clients: id, name, desc, icon, pointsSpent.
				local name, spent
				if type(r[2]) == "string" then
					name, spent = r[2], r[5]
				else
					name, spent = r[1], r[3]
				end
				local spec = specFromName(name) or TREE_NAMES[i]
				if spec and type(spent) == "number" then
					points[spec] = spent
				end
			end
		end
	end

	-- Retail-style spec / trait APIs.
	s.strategies.calls = {
		GetSpecialization = tryPath("GetSpecialization"),
		GetPrimaryTalentTree = tryPath("GetPrimaryTalentTree"),
		GetActiveTalentGroup = tryPath("GetActiveTalentGroup"),
		GetUnspentTalentPoints = tryPath("GetUnspentTalentPoints"),
		UnitCharacterPoints = tryPath("UnitCharacterPoints", "player"),
		["C_SpecializationInfo.GetSpecialization"] = tryPath("C_SpecializationInfo.GetSpecialization"),
		["C_SpecializationInfo.GetActiveSpecGroup"] = tryPath("C_SpecializationInfo.GetActiveSpecGroup"),
		["C_SpecializationInfo.GetNumSpecializationsForClassID"] = tryPath("C_SpecializationInfo.GetNumSpecializationsForClassID", 2),
		["C_ClassTalents.GetActiveConfigID"] = tryPath("C_ClassTalents.GetActiveConfigID"),
		["C_Talent.GetNumTalentTabs"] = tryPath("C_Talent.GetNumTalentTabs"),
	}
	local specIndex = s.strategies.calls.GetSpecialization
	if type(specIndex) == "table" and type(specIndex[1]) == "number" then
		s.strategies.calls.GetSpecializationInfo = tryPath("GetSpecializationInfo", specIndex[1])
	end
	local configID = s.strategies.calls["C_ClassTalents.GetActiveConfigID"]
	if type(configID) == "table" and type(configID[1]) == "number" then
		local ok, info = pcall(C_Traits.GetConfigInfo, configID[1])
		s.strategies.traitConfig = ok and describeFields(info) or tostring(info)
	end

	-- Heuristic: known spells that belong to one tree.
	local counts = { holy = 0, prot = 0, ret = 0 }
	local hits = {}
	for _, entry in ipairs(PK.Spells.list) do
		local r = resolved[entry.key]
		if entry.spec and r and r.known then
			counts[entry.spec] = counts[entry.spec] + 1
			hits[#hits + 1] = entry.names[1] .. "->" .. entry.spec
		end
	end
	s.strategies.heuristic = { counts = counts, hits = hits }

	-- Provisional decision (the real SpecProfile arrives in M1).
	local best, bestVal, method = nil, 0, nil
	for _, spec in ipairs(TREE_NAMES) do
		if points[spec] and points[spec] > bestVal then
			best, bestVal, method = spec, points[spec], "talentPoints"
		end
	end
	if not best then
		for _, spec in ipairs(TREE_NAMES) do
			if counts[spec] > bestVal then
				best, bestVal, method = spec, counts[spec], "knownSpells"
			end
		end
	end
	s.talentPoints = points
	s.decision = best and { spec = best, method = method } or { spec = "holy", method = "fallback (could not detect)" }
	return s
end

local function probeShapeshift()
	local out = { current = tryPath("GetShapeshiftForm") }
	local n = tryPath("GetNumShapeshiftForms")
	out.num = n
	if type(n) == "table" and type(n[1]) == "number" then
		for i = 1, n[1] do
			out["form" .. i] = tryPath("GetShapeshiftFormInfo", i)
		end
	end
	return out
end

local function probeAuras()
	local list, method = Compat.GetAuras("player", "HELPFUL")
	local out = { method = method, count = #list }
	for i, aura in ipairs(list) do
		out[i] = describeFields(aura)
	end
	return out
end

-- Addon message prefix + a whisper to ourselves. The reply arrives
-- asynchronously and is written into probe.comm.received.
local PREFIX = "NLPT"
local function probeComm()
	local out = {}
	out.register = tryPath("C_ChatInfo.RegisterAddonMessagePrefix", PREFIX)
	out.isRegistered = tryPath("C_ChatInfo.IsAddonMessagePrefixRegistered", PREFIX)
	out.lockdown = tryPath("C_ChatInfo.InChatMessagingLockdown")
	out.received = {}
	if Compat.InCombat() then
		out.send = "skipped: in combat"
		return out
	end
	local me = UnitName("player")
	out.sendWhisper = tryPath("C_ChatInfo.SendAddonMessage", PREFIX, "PROBE|" .. time(), "WHISPER", me)
	if IsInGroup and IsInGroup() then
		out.sendGroup = tryPath("C_ChatInfo.SendAddonMessage", PREFIX, "PROBE|" .. time(), IsInRaid() and "RAID" or "PARTY")
	end
	return out
end

-- Units: value described plus whether arithmetic on it works.
local function probeUnits()
	local out = {}
	local checks = {
		{ "UnitHealth", "player" }, { "UnitHealthMax", "player" }, { "UnitPower", "player", 0 },
		{ "UnitPowerMax", "player", 0 }, { "UnitGetTotalAbsorbs", "player" },
		{ "UnitHealth", "target" }, { "UnitHealthMax", "target" },
	}
	for _, c in ipairs(checks) do
		local fn = _G[c[1]]
		local label = c[1] .. "(" .. c[2] .. ")"
		if type(fn) ~= "function" then
			out[label] = "missing"
		else
			local ok, v = pcall(fn, c[2], c[3])
			if ok then
				out[label] = { value = Describe(v), arithmetic = Compat.ArithmeticCheck(v) }
			else
				out[label] = "error: " .. tostring(v)
			end
		end
	end
	out.targetExists = tryPath("UnitExists", "target")
	return out
end

-- Cooldowns of known registry spells. withGetters samples duration-object
-- getters for the first few spells.
local function probeCooldowns(resolved, withGetters)
	local out = { spells = {} }
	local sampled = 0
	for _, entry in ipairs(PK.Spells.list) do
		local r = resolved[entry.key]
		local cat = entry.category
		if r and r.known and r.spellID and (cat == "ability" or cat == "talent" or cat == "seal") then
			local id = r.spellID
			local row = {
				cooldown = describeFields(Compat.GetSpellCooldown(id)),
				usable = tryPath("C_Spell.IsSpellUsable", id),
				charges = tryPath("C_Spell.GetSpellCharges", id),
			}
			local dur = Compat.GetSpellCooldownDuration(id)
			row.durationObject = Describe(dur)
			if type(dur) ~= "nil" and not out.durationMethods then
				out.durationMethods = listMethods(dur)
			end
			if withGetters and type(dur) ~= "nil" and sampled < 4 then
				sampled = sampled + 1
				row.durationGetters = sampleGetters(dur, listMethods(dur))
			end
			out.spells[r.name or entry.names[1]] = row
		end
	end
	return out
end

-- Self-buff lookups by spell ID for seals, auras, blessings, Righteous Fury.
local function probeAuraLookups(resolved)
	local fn = Compat.Resolve("C_UnitAuras.GetPlayerAuraBySpellID")
	if not fn then
		return "missing"
	end
	local out = {}
	for _, entry in ipairs(PK.Spells.list) do
		local r = resolved[entry.key]
		local cat = entry.category
		if r and r.known and r.spellID and (cat == "seal" or cat == "aura" or cat == "blessing"
			or cat == "selfBuff" or cat == "proc") then
			local ok, aura = pcall(fn, r.spellID)
			if not ok then
				out[entry.key] = "error: " .. tostring(aura)
			elseif Compat.IsSecret(aura) then
				out[entry.key] = "<secret>"
			elseif type(aura) ~= "nil" then
				out[entry.key] = describeFields(aura)
			end
		end
	end
	return out
end

-- State ------------------------------------------------------------------------

local lastResolved

local function buildResolved()
	local book = Compat.ScanSpellbook()
	local _, resolved = probeRegistry(PK.Spells.IndexSpellbook(book))
	return resolved
end

local function runProbe()
	local db = PK.db
	local p = { takenAt = date and date("%Y-%m-%d %H:%M:%S") or time() }
	local steps = {
		{ "client", probeClient },
		{ "api", probeApi },
		{ "legacyGlobalsPresent", probeLegacy },
		{ "namespaces", probeNamespaces },
		{ "events", probeEvents },
		{ "widgets", probeWidgets },
		{ "shapeshift", probeShapeshift },
		{ "playerAuras", probeAuras },
		{ "units", probeUnits },
		{ "comm", probeComm },
	}
	p.stepErrors = {}
	for _, step in ipairs(steps) do
		local ok, res = pcall(step[2])
		if ok then
			p[step[1]] = res
		else
			p.stepErrors[step[1]] = tostring(res)
		end
	end
	p.secretValues = {
		issecretvalue = Compat.HasSecretValues(),
		inCombat = Compat.InCombat(),
	}

	local ok, err = pcall(function()
		local bookOut, book = probeSpellbook()
		p.spellbook = bookOut
		local regOut, resolved = probeRegistry(PK.Spells.IndexSpellbook(book))
		p.registry = regOut
		lastResolved = resolved
		p.spec = probeSpec(resolved)
		p.cooldowns = probeCooldowns(resolved, true)
		p.auraLookups = probeAuraLookups(resolved)
	end)
	if not ok then
		p.stepErrors.spells = tostring(err)
	end

	p.savedVariables = PK.svState
	p.unknownEventsSeenByAddon = sortedKeys(PK.unknownEvents)
	p.errorsThisSession = #PK.errorList
	db.probe = p
	return p
end

-- Combat capture ----------------------------------------------------------------

local combatWatcher = {}

local function combatSample(label)
	local db = PK.db
	local cap = db.probeCombat
	if not cap then
		return
	end
	local s = { label = label, t = GetTime(), inCombat = Compat.InCombat() }
	local steps = {
		{ "playerAuras", probeAuras },
		{ "units", probeUnits },
		{ "shapeshift", probeShapeshift },
		{ "cooldowns", function()
			return probeCooldowns(lastResolved or {}, label ~= "after")
		end },
		{ "auraLookups", function()
			return probeAuraLookups(lastResolved or {})
		end },
	}
	for _, step in ipairs(steps) do
		local ok, res = pcall(step[2])
		s[step[1]] = ok and res or ("error: " .. tostring(res))
	end
	cap.samples[#cap.samples + 1] = s
end

local function disarm()
	PK:UnregisterEvent("PLAYER_REGEN_DISABLED", combatWatcher)
	PK:UnregisterEvent("PLAYER_REGEN_ENABLED", combatWatcher)
end

local function arm()
	if Compat.InCombat() then
		PK:Print("leave combat first, then run /ptk probe combat again.")
		return
	end
	lastResolved = buildResolved()
	PK.db.probeCombat = { armedAt = time(), samples = {} }
	combatSample("baseline (out of combat)")
	PK:RegisterEvent("PLAYER_REGEN_DISABLED", combatWatcher, function()
		combatSample("t+0")
		C_Timer.After(2, function()
			combatSample("t+2")
		end)
		C_Timer.After(8, function()
			combatSample("t+8")
		end)
	end)
	PK:RegisterEvent("PLAYER_REGEN_ENABLED", combatWatcher, function()
		combatSample("after")
		disarm()
		PK.db.probeCombat.finishedAt = time()
		PK:Print("combat probe captured " .. #PK.db.probeCombat.samples .. " samples. Type /reload to save it.")
	end)
	PK:Print("combat probe armed. Attack a target dummy for about 10 seconds, then leave combat.")
end

-- Output --------------------------------------------------------------------------

local function probeText()
	local db = PK.db
	local parts = {}
	if db.probe then
		parts[#parts + 1] = "=== " .. PK.displayName .. " probe ==="
		parts[#parts + 1] = table.concat(dump(db.probe), "\n")
	end
	if db.probeCombat then
		parts[#parts + 1] = "\n=== " .. PK.displayName .. " combat probe ==="
		parts[#parts + 1] = table.concat(dump(db.probeCombat), "\n")
	end
	if #PK.errorList > 0 then
		parts[#parts + 1] = "\n=== errors ==="
		parts[#parts + 1] = table.concat(dump(PK.errorList), "\n")
	end
	return table.concat(parts, "\n")
end
D.ProbeText = probeText

-- Async loopback results from the comm test.
local commWatcher = {}
function D:OnEnable()
	PK:RegisterEvent("CHAT_MSG_ADDON", commWatcher, function(_, _, prefix, text, channel, sender)
		if prefix ~= PREFIX or type(text) ~= "string" or not text:find("^PROBE|") then
			return
		end
		local probe = PK.db and PK.db.probe
		if probe and probe.comm then
			local r = probe.comm.received
			if #r < 10 then
				r[#r + 1] = { channel = Describe(channel), sender = Describe(sender), text = text, at = time() }
			end
		end
	end)
end

function D:OnDisable()
	PK:UnregisterEvent("CHAT_MSG_ADDON", commWatcher)
	disarm()
end

-- Commands ---------------------------------------------------------------------------

PK:RegisterCommand("probe", function(args)
	if args[1] == "combat" then
		arm()
		return
	end
	if Compat.InCombat() then
		PK:Print("run /ptk probe out of combat (use /ptk probe combat for in-combat data).")
		return
	end
	local p = runProbe()
	local nErr = 0
	for _ in pairs(p.stepErrors) do
		nErr = nErr + 1
	end
	PK:Print(string.format("probe done: interface %s, %d spells in spellbook, %d registry names unresolved, %d step errors.",
		tostring(p.client and p.client.interface), p.spellbook and p.spellbook.count or 0,
		p.registry and #p.registry.unresolved or 0, nErr))
	PK:Print("type /reload to save it to disk (wait a second first so the addon-message test can arrive).")
	PK.CopyWindow:Show(PK.displayName .. " - probe", probeText())
end, "run the compatibility probe (\"/ptk probe combat\" to capture during combat)")

PK:RegisterCommand("show", function()
	PK.CopyWindow:Show(PK.displayName .. " - probe", probeText())
end, "show the last probe results")

PK:RegisterCommand("debug", function(args)
	local sub = args[1]
	if sub == "on" or sub == "off" then
		PK.db.debug = sub == "on"
		PK:Print("debug logging " .. sub)
	elseif sub == "clear" then
		for i = #PK.debugLog, 1, -1 do
			PK.debugLog[i] = nil
		end
		PK:Print("debug log cleared")
	else
		PK.CopyWindow:Show(PK.displayName .. " - debug log", table.concat(PK.debugLog, "\n"))
	end
end, "on | off | show | clear - verbose logging")
