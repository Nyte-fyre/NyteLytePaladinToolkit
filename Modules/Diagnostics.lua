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
local NAMESPACE_PATTERNS = { "Talent", "Spec", "Trait", "Cooldown", "Aura", "Secret", "Duration", "Restrict", "Swing",
	"CombatLog", "EncounterEvents" }

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
		lines[i] = string.format("%s | id=%s | %s%s%s | %s%s", tostring(item.name), tostring(item.spellID),
			tostring(item.itemType or "?"), item.isPassive and " passive" or "", item.isOffSpec and " offspec" or "",
			tostring(item.skillLine), item.flyout and (" | in flyout " .. tostring(item.flyout)) or "")
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

-- Describes exactly what an API returned: nil, a secret, a secret table, a
-- readable table, or an error. Used to see WHY combat aura reads come back empty.
local function rawKind(ok, v)
	if not ok then
		return "error: " .. tostring(v)
	end
	if Compat.IsSecret(v) then
		return "<secret value>"
	end
	if type(v) == "table" then
		local st = Compat.Resolve("issecrettable")
		if st then
			local ok2, r = pcall(st, v)
			if ok2 and r then
				return "<secret table>"
			end
		end
		return describeFields(v)
	end
	return Describe(v)
end

-- Every other way to read the player's buffs, to learn which ones work in combat.
local function probeAuraPaths()
	local U = C_UnitAuras
	if not U then
		return "no C_UnitAuras"
	end
	local out = {}
	out.byIndex1 = rawKind(pcall(U.GetAuraDataByIndex, "player", 1, "HELPFUL"))
	if U.GetBuffDataByIndex then
		out.buffByIndex1 = rawKind(pcall(U.GetBuffDataByIndex, "player", 1))
	end
	if U.GetAuraDataBySpellName then
		out.bySpellName = rawKind(pcall(U.GetAuraDataBySpellName, "player", "Devotion Aura", "HELPFUL"))
	end
	if U.GetUnitAuraBySpellID then
		out.unitAuraBySpellID = rawKind(pcall(U.GetUnitAuraBySpellID, "player", 465))
	end
	if U.GetUnitAuraInstanceIDs then
		local ok, ids = pcall(U.GetUnitAuraInstanceIDs, "player", "HELPFUL")
		out.instanceIDs = rawKind(ok, ids)
		if ok and type(ids) == "table" and not Compat.IsSecret(ids) then
			out.perInstance = {}
			for i, id in ipairs(ids) do
				if i > 6 then
					break
				end
				local row = {}
				if Compat.IsSecret(id) then
					row.id = "<secret>"
				else
					row.id = id
					row.data = rawKind(pcall(U.GetAuraDataByAuraInstanceID, "player", id))
					if U.GetAuraDuration then
						local okD, d = pcall(U.GetAuraDuration, "player", id)
						row.duration = okD and Describe(d) or ("error: " .. tostring(d))
					end
					if U.DoesAuraHaveExpirationTime then
						row.hasExpiration = rawKind(pcall(U.DoesAuraHaveExpirationTime, "player", id))
					end
				end
				out.perInstance[#out.perInstance + 1] = row
			end
		end
	end
	return out
end

-- Asks C_Secrets directly what it considers secret right now.
local function probeSecrecy(resolved)
	local S = C_Secrets
	if not S then
		return "no C_Secrets"
	end
	local out = {
		HasSecretRestrictions = tryCall(S.HasSecretRestrictions),
		ShouldAurasBeSecret = tryCall(S.ShouldAurasBeSecret),
		ShouldCooldownsBeSecret = tryCall(S.ShouldCooldownsBeSecret),
		ShouldUnitHealthMaxBeSecret = tryCall(S.ShouldUnitHealthMaxBeSecret, "player"),
		ShouldUnitPowerBeSecret = tryCall(S.ShouldUnitPowerBeSecret, "player"),
		ShouldUnitPowerMaxBeSecret = tryCall(S.ShouldUnitPowerMaxBeSecret, "player"),
		spells = {},
	}
	for _, entry in ipairs(PK.Spells.list) do
		local r = resolved and resolved[entry.key]
		if r and r.known and r.spellID then
			local id = r.spellID
			out.spells[r.name or entry.names[1]] = {
				auraSecrecy = tryCall(S.GetSpellAuraSecrecy, id),
				cooldownSecrecy = tryCall(S.GetSpellCooldownSecrecy, id),
				auraSecret = tryCall(S.ShouldSpellAuraBeSecret, id),
				cooldownSecret = tryCall(S.ShouldSpellCooldownBeSecret, id),
			}
		end
	end
	return out
end

-- Addon restriction state and any Enum names describing secrecy or restrictions.
local function probeRestrictions()
	local out = {
		addonChatRestricted = tryPath("C_ChatInfo.AreOutgoingAddonChatMessagesRestricted"),
		restrictionActive = {},
		enums = {},
	}
	-- One call per restriction type (Combat, Encounter, ChallengeMode, PvPMatch, Map, Chat).
	local types = Enum and Enum.AddOnRestrictionType
	if type(types) == "table" then
		for name, value in pairs(types) do
			out.restrictionActive[name] = tryPath("C_RestrictedActions.IsAddOnRestrictionActive", value)
		end
	end
	if type(Enum) == "table" then
		for name, values in pairs(Enum) do
			if type(name) == "string" and type(values) == "table"
				and (name:find("^Secre") or name:find("^AddOnRestriction")) and not name:find("Meta$") then
				local parts = {}
				for k, v in pairs(values) do
					parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
				end
				table.sort(parts)
				out.enums[name] = table.concat(parts, ", ")
			end
		end
	end
	return out
end

-- Talent trees through C_Traits: one line per node with position, rank and spell.
local function probeTraits()
	local T, CT = C_Traits, C_ClassTalents
	if not (T and CT and CT.GetActiveConfigID) then
		return "no C_Traits / C_ClassTalents"
	end
	local okC, configID = pcall(CT.GetActiveConfigID)
	if not okC or type(configID) ~= "number" then
		return "no active config: " .. tostring(configID)
	end
	local out = { configID = configID, trees = {} }
	local okI, info = pcall(T.GetConfigInfo, configID)
	if not okI or type(info) ~= "table" or type(info.treeIDs) ~= "table" then
		return out
	end
	for _, treeID in ipairs(info.treeIDs) do
		local tree = {}
		out.trees["tree" .. tostring(treeID)] = tree
		tree.info = rawKind(pcall(T.GetTreeInfo, configID, treeID))
		local okCur, currencies = pcall(T.GetTreeCurrencyInfo, configID, treeID, false)
		if okCur and type(currencies) == "table" then
			tree.currencies = {}
			for i, c in ipairs(currencies) do
				tree.currencies[i] = describeFields(c)
			end
		end
		local okN, nodes = pcall(T.GetTreeNodes, treeID)
		if okN and type(nodes) == "table" then
			tree.nodeCount = #nodes
			tree.nodes = {}
			for i, nodeID in ipairs(nodes) do
				if i > 120 then
					break
				end
				local okNode, node = pcall(T.GetNodeInfo, configID, nodeID)
				if okNode and type(node) == "table" then
					local spellName, spellID = "?", nil
					local entryID = (node.activeEntry and node.activeEntry.entryID) or (node.entryIDs and node.entryIDs[1])
					if entryID then
						local okE, entry = pcall(T.GetEntryInfo, configID, entryID)
						if okE and type(entry) == "table" and entry.definitionID then
							local okD, def = pcall(T.GetDefinitionInfo, entry.definitionID)
							if okD and type(def) == "table" then
								spellID = def.spellID or def.overriddenSpellID
								spellName = def.overrideName or (spellID and Compat.GetSpellName(spellID)) or "?"
							end
						end
					end
					tree.nodes[#tree.nodes + 1] = string.format("%s | x=%s y=%s | rank %s/%s | %s (%s)%s",
						tostring(nodeID), tostring(node.posX), tostring(node.posY), tostring(node.ranksPurchased),
						tostring(node.maxRanks), tostring(spellName), tostring(spellID),
						node.subTreeID and (" | subTree " .. tostring(node.subTreeID)) or "")
				end
			end
		else
			tree.nodes = okN and Describe(nodes) or ("error: " .. tostring(nodes))
		end
	end
	return out
end

-- Duration objects are userdata with a protected metatable, so methods can't
-- be listed; look up likely names directly instead.
local DURATION_METHODS = {
	"GetRemainingDuration", "GetElapsedDuration", "GetTotalDuration", "GetStartTime", "GetEndTime",
	"GetModRate", "GetRemainingPercent", "GetElapsedPercent", "EvaluateRemainingPercent",
	"EvaluateElapsedPercent", "EvaluateRemainingDuration", "IsZero", "IsActive", "IsPaused",
	"HasSecretValues", "IsSecret", "GetDuration", "GetExpirationTime",
}

local function durationMethodsByName(dur)
	local found = {}
	for _, name in ipairs(DURATION_METHODS) do
		local ok, fn = pcall(function()
			return dur[name]
		end)
		if ok and type(fn) == "function" then
			found[#found + 1] = name
		end
	end
	return found
end

local function sampleDurationGetters(dur)
	local out = {}
	for _, name in ipairs(durationMethodsByName(dur)) do
		if name:find("^Get") or name:find("^Is") or name:find("^Has") then
			local r = tryCall(dur[name], dur)
			if type(r) == "table" then
				out[name] = r[1] == nil and "nil" or r[1]
			else
				out[name] = r
			end
		end
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
				out.durationMethods = durationMethodsByName(dur)
			end
			if withGetters and type(dur) ~= "nil" and sampled < 4 then
				sampled = sampled + 1
				row.durationGetters = sampleDurationGetters(dur)
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
		{ "auraPaths", probeAuraPaths },
		{ "restrictions", probeRestrictions },
		{ "traits", probeTraits },
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
		p.secrecy = probeSecrecy(resolved)
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
		{ "auraPaths", probeAuraPaths },
		{ "restrictions", probeRestrictions },
		{ "secrecy", function()
			return probeSecrecy(lastResolved or {})
		end },
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

-- Logs the player's own casts and aura updates while armed, to learn what
-- event payloads stay readable in combat. A few casts also trigger a sample
-- half a second later, to catch cooldowns while they are running.
local MAX_EVENTS = 40
local castSamples = 0

local function describeAuraUpdate(info)
	if Compat.IsSecret(info) or type(info) ~= "table" then
		return Describe(info)
	end
	local out = describeFields(info)
	if type(out) ~= "table" then
		return out
	end
	local added = info.addedAuras
	if type(added) == "table" and not Compat.IsSecret(added) then
		out.addedAuras = {}
		for i = 1, math.min(#added, 3) do
			out.addedAuras[i] = describeFields(added[i])
		end
	end
	for _, key in ipairs({ "removedAuraInstanceIDs", "updatedAuraInstanceIDs" }) do
		local ids = info[key]
		if type(ids) == "table" and not Compat.IsSecret(ids) then
			local parts = {}
			for i = 1, math.min(#ids, 6) do
				parts[i] = tostring(Describe(ids[i]))
			end
			out[key] = table.concat(parts, ",")
		end
	end
	return out
end

local function logCombatEvent(_, event, unit, a, b)
	local cap = PK.db.probeCombat
	if not cap or #cap.events >= MAX_EVENTS then
		return
	end
	-- Out of combat everything is readable already; keep the slots for combat.
	if not Compat.InCombat() or Compat.IsSecret(unit) or unit ~= "player" then
		return
	end
	local row = { t = GetTime(), event = event, inCombat = Compat.InCombat() }
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		row.castGUID = Describe(a)
		row.spellID = Describe(b)
		if row.inCombat and castSamples < 3 then
			castSamples = castSamples + 1
			local label = "0.5s after cast " .. castSamples .. " (spellID " .. tostring(row.spellID) .. ")"
			C_Timer.After(0.5, function()
				combatSample(label)
			end)
		end
	else
		row.updateInfo = describeAuraUpdate(a)
	end
	cap.events[#cap.events + 1] = row
end

local function disarm()
	PK:UnregisterEvent("PLAYER_REGEN_DISABLED", combatWatcher)
	PK:UnregisterEvent("PLAYER_REGEN_ENABLED", combatWatcher)
	PK:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED", combatWatcher)
	PK:UnregisterEvent("UNIT_AURA", combatWatcher)
end

local function arm()
	if Compat.InCombat() then
		PK:Print("leave combat first, then run /ptk probe combat again.")
		return
	end
	lastResolved = buildResolved()
	PK.db.probeCombat = { armedAt = time(), samples = {}, events = {} }
	castSamples = 0
	combatSample("baseline (out of combat)")
	PK:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", combatWatcher, logCombatEvent)
	PK:RegisterEvent("UNIT_AURA", combatWatcher, logCombatEvent)
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
	PK:Print("combat probe armed. Fight a target dummy for about 15 seconds: cast your Seal, Judgement and Holy Strike, then leave combat.")
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
