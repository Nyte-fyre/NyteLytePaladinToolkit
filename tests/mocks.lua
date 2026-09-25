-- Minimal mocked WoW API, shaped like what WoW Forever's beta client showed
-- in the first /ptk probe (build 1.60.1.69977, 2026-09-24): player health,
-- power and absorbs are secret even out of combat; in combat, cooldown
-- start/duration/modRate are secret but isActive/isEnabled are not, and the
-- player's own aura queries return nothing. It checks our logic and our secret-value
-- discipline, not the real client. Secret values are proxies that error on
-- comparison, arithmetic and concatenation, like Midnight-style secrets.

MOCK = { cooldowns = {}, combat = false, timers = {}, printed = {}, errorsRaised = {}, sent = {}, level = 20 }

-- Secret values ----------------------------------------------------------------
local secrets = setmetatable({}, { __mode = "k" })
local function boom()
	error("attempt to use a secret value", 2)
end
local secretMT = {
	__add = boom, __sub = boom, __mul = boom, __div = boom, __lt = boom, __le = boom,
	__eq = boom, __concat = boom, __unm = boom, __len = boom,
	__index = function()
		boom()
	end,
}
function MOCK.secret()
	local s = setmetatable({}, secretMT)
	secrets[s] = true
	return s
end
function MOCK.isSecret(v)
	return rawequal(v, nil) == false and type(v) == "table" and secrets[v] == true
end
function MOCK.maybeSecret(v)
	if MOCK.combat then
		return MOCK.secret()
	end
	return v
end
if not MOCK_NO_SECRETS then
	issecretvalue = function(v)
		return MOCK.isSecret(v)
	end
end

-- Basics -------------------------------------------------------------------------
local now = 1000
function time()
	return now
end
function GetTime()
	return now + 0.5
end
function MOCK.advance(sec)
	now = now + sec
end
function date()
	return "2026-09-23 12:00:00"
end
function print(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	MOCK.printed[#MOCK.printed + 1] = table.concat(parts, " ")
end
function debugstack()
	return "stack"
end
local errHandler = function(msg)
	MOCK.errorsRaised[#MOCK.errorsRaised + 1] = msg
end
function geterrorhandler()
	return errHandler
end
function seterrorhandler(fn)
	errHandler = fn
end
tinsert = table.insert
wipe = function(t)
	for k in pairs(t) do
		t[k] = nil
	end
	return t
end
function GetBuildInfo()
	return "1.60.1", "69977", "Sep 20 2026", 16001
end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 1, 2
function GetLocale()
	return "enUS"
end
-- Group members: MOCK.party = { { unit = "party1", name = "X", class = "ROGUE" }, ... }
MOCK.party = {}
MOCK.unitAuras = {}
local function partyMember(unit)
	for _, m in ipairs(MOCK.party) do
		if m.unit == unit then
			return m
		end
	end
	return nil
end
function UnitClass(unit)
	local m = partyMember(unit)
	if m then
		return m.class, m.class, 0
	end
	if MOCK_CLASS then
		return MOCK_CLASS:sub(1, 1) .. MOCK_CLASS:sub(2):lower(), MOCK_CLASS, 1
	end
	return "Paladin", "PALADIN", 2
end
function GetNumGroupMembers()
	return MOCK.inGroup and (#MOCK.party + 1) or 0
end
function UnitIsConnected()
	return true
end
function UnitIsDeadOrGhost()
	return false
end
function UnitIsVisible()
	return true
end
function UnitIsGroupLeader(unit)
	return MOCK.leader == unit
end
function UnitIsGroupAssistant()
	return false
end
function Ambiguate(name)
	return (name:match("^([^-]+)")) or name
end
function IsShiftKeyDown()
	return MOCK.shift == true
end
MOCK.chat = {}
function SendChatMessage(text, channel)
	MOCK.chat[#MOCK.chat + 1] = { text = text, channel = channel }
end
GameTooltip = setmetatable({}, { __index = function()
	return function() end
end })
function UnitRace()
	return "Human", "Human"
end
function UnitLevel()
	return MOCK.level
end
function UnitName(unit)
	local m = partyMember(unit)
	if m then
		return m.name
	end
	return "Tester"
end
function GetRealmName()
	return "Beta Realm"
end
function UnitExists(unit)
	if unit == nil or unit == "player" or unit == "target" then
		return true
	end
	return MOCK.inGroup and partyMember(unit) ~= nil
end
function IsInGroup()
	return MOCK.inGroup == true
end
function IsInRaid()
	return false
end
function InCombatLockdown()
	return MOCK.combat
end
function UnitHealth()
	return MOCK.secret()
end
function UnitHealthMax()
	return MOCK.maybeSecret(1000)
end
function UnitPower()
	return MOCK.secret()
end
function UnitPowerMax()
	return 600
end
function UnitGetTotalAbsorbs()
	return MOCK.secret()
end
function GetShapeshiftForm()
	return 1
end
function GetNumShapeshiftForms()
	return 1
end
function GetShapeshiftFormInfo()
	return 135893, true, true, 465
end

MOCK.tickers = {}
C_Timer = {
	After = function(delay, fn)
		MOCK.timers[#MOCK.timers + 1] = { delay = delay, fn = fn }
	end,
	NewTicker = function(interval, fn)
		local t = { fn = fn }
		function t:Cancel()
			self.cancelled = true
		end
		MOCK.tickers[#MOCK.tickers + 1] = t
		return t
	end,
}
-- Runs every live ticker `n` times.
function MOCK.tick(n)
	for _ = 1, n or 1 do
		for _, t in ipairs(MOCK.tickers) do
			if not t.cancelled then
				t.fn()
			end
		end
	end
end
function MOCK.runTimers()
	local list = MOCK.timers
	MOCK.timers = {}
	for _, t in ipairs(list) do
		t.fn()
	end
end

C_AddOns = {
	GetAddOnMetadata = function(_, field)
		return field == "Version" and "0.0.1" or nil
	end,
}

-- Frames: every unknown method is a no-op, events must be known ------------------
KNOWN_EVENTS = {}
for _, e in ipairs({
	"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"CHAT_MSG_ADDON", "UNIT_AURA", "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE",
	"CHARACTER_POINTS_CHANGED", "GROUP_ROSTER_UPDATE", "READY_CHECK", "ENCOUNTER_START", "ENCOUNTER_END",
	"UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_SENT", "LEARNED_SPELL_IN_SKILL_LINE", "ACTIVE_TALENT_GROUP_CHANGED", "TRAIT_CONFIG_UPDATED",
	"PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM", "ENCOUNTER_START", "ENCOUNTER_END", "SPELL_UPDATE_USABLE", "SPELL_UPDATE_CHARGES",
}) do
	KNOWN_EVENTS[e] = true
end

local allFrames = {}
local frameMethods = {}
function frameMethods:RegisterEvent(e)
	if not KNOWN_EVENTS[e] then
		error('Attempt to register unknown event "' .. e .. '"')
	end
	self._events[e] = true
end
function frameMethods:UnregisterEvent(e)
	self._events[e] = nil
end
function frameMethods:UnregisterAllEvents()
	self._events = {}
end
function frameMethods:SetScript(name, fn)
	self._scripts[name] = fn
end
function frameMethods:GetScript(name)
	return self._scripts[name]
end
function frameMethods:SetText(t)
	self._text = t
	if self._scripts.OnTextChanged then
		self._scripts.OnTextChanged(self, false)
	end
end
function frameMethods:GetText()
	return self._text
end
function frameMethods:Show()
	self._shown = true
end
function frameMethods:Hide()
	self._shown = false
end
function frameMethods:IsShown()
	return self._shown ~= false
end
function frameMethods:SetAttribute(k, v)
	self._attr = self._attr or {}
	self._attr[k] = v
end
function frameMethods:GetAttribute(k)
	return self._attr and self._attr[k]
end
function frameMethods:SetShown(v)
	self._shown = v and true or false
end
function frameMethods:SetChecked(v)
	self._checked = v and true or false
end
function frameMethods:GetChecked()
	return self._checked
end
function frameMethods:GetCenter()
	return 520, 400
end
function frameMethods:GetWidth()
	return 1024
end
function frameMethods:GetHeight()
	return 768
end
function frameMethods:CreateFontString()
	return MOCK.newFrame("FontString")
end
function frameMethods:CreateTexture()
	return MOCK.newFrame("Texture")
end
local noop = function() end
-- Unknown Capitalized keys are treated as widget methods (no-ops); other
-- keys are plain fields and read as nil, as on real frames.
local frameMT = {
	__index = function(_, k)
		if frameMethods[k] then
			return frameMethods[k]
		end
		if type(k) == "string" and k:find("^%u") then
			return noop
		end
		return nil
	end,
}
function MOCK.newFrame(kind)
	local f = setmetatable({ _events = {}, _scripts = {}, _kind = kind }, frameMT)
	allFrames[#allFrames + 1] = f
	return f
end
function CreateFrame(kind, name)
	local f = MOCK.newFrame(kind)
	if name then
		_G[name] = f
	end
	return f
end
function MOCK.fire(event, ...)
	for _, f in ipairs(allFrames) do
		if f._events[event] and f._scripts.OnEvent then
			f._scripts.OnEvent(f, event, ...)
		end
	end
end
UIParent = MOCK.newFrame("Frame")
StaticPopupDialogs = {}
function StaticPopup_Show(name)
	MOCK.popup = name
end
MOCK.settingsOpened = 0
Settings = {
	RegisterCanvasLayoutCategory = function(panel, name)
		return { ID = 42, name = name, GetID = function(self)
			return self.ID
		end }
	end,
	RegisterAddOnCategory = function() end,
	OpenToCategory = function()
		MOCK.settingsOpened = MOCK.settingsOpened + 1
	end,
}
UISpecialFrames = {}
ChatFontNormal = {}
SlashCmdList = {}

-- Spellbook ------------------------------------------------------------------------
Enum = {
	SpellBookSpellBank = { Player = 0, Pet = 1 },
	SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
}
MOCK.book = {
	{ name = "Seal of Righteousness", spellID = 21084, itemType = 1 },
	{ name = "Seal of Righteousness", spellID = 20287, itemType = 1 }, -- rank 2, listed after rank 1
	{ name = "Devotion Aura", spellID = 465, itemType = 1 },
	{ name = "Blessing of Might", spellID = 19740, itemType = 1 },
	{ name = "Judgement", spellID = 20271, itemType = 1 },
	{ name = "Holy Strike", spellID = 900001, itemType = 1 },
	{ name = "Righteous Fury", spellID = 25780, itemType = 1 },
	{ name = "Holy Shock", spellID = 20473, itemType = 1 },
	{ name = "Blessing of Kings", spellID = 20217, itemType = 2 },
	{ name = "Blessings", actionID = 264, itemType = 4 },
	{ name = "Flash of Light", spellID = 19750, itemType = 1 },
	{ name = "Purify", spellID = 1152, itemType = 1 },
}
if not MOCK_NO_SPELLBOOK then
	C_SpellBook = {
		GetNumSpellBookSkillLines = function()
			return 2
		end,
		GetSpellBookSkillLineInfo = function(i)
			if i == 1 then
				return { name = "General", itemIndexOffset = 0, numSpellBookItems = 0 }
			end
			return { name = "Paladin", itemIndexOffset = 0, numSpellBookItems = #MOCK.book }
		end,
		GetSpellBookItemInfo = function(i)
			local b = MOCK.book[i]
			return b and { name = b.name, spellID = b.spellID, actionID = b.actionID or b.spellID, itemType = b.itemType,
				isPassive = false, subName = "" }
		end,
	}
end
MOCK.flyouts = { [264] = { name = "Blessings", slots = {
	{ 19740, true, "Blessing of Might" }, { 19742, false, "Blessing of Wisdom" },
} } }
function GetFlyoutInfo(id)
	local f = MOCK.flyouts[id]
	return f.name, "", #f.slots, true
end
function GetFlyoutSlotInfo(id, slot)
	local s = MOCK.flyouts[id].slots[slot]
	return s[1], s[1], s[2], s[3]
end

function IsPlayerSpell(id)
	for _, b in ipairs(MOCK.book) do
		if b.spellID == id then
			return b.itemType == 1
		end
	end
	return false
end

-- Spells, cooldowns, duration objects -----------------------------------------------
local durationMT = { __metatable = false, __index = {
	GetRemainingDuration = function()
		return MOCK.maybeSecret(4)
	end,
	IsZero = function()
		return false
	end,
} }
C_Spell = {
	GetSpellInfo = function(spell)
		for _, b in ipairs(MOCK.book) do
			if b.name == spell or b.spellID == spell then
				return { name = b.name, spellID = b.spellID, iconID = 1 }
			end
		end
		return nil
	end,
	-- MOCK.cooldowns[spellID] = { active = bool, gcd = bool } (default: active, not GCD)
	GetSpellCooldown = function(id)
		local c = MOCK.cooldowns[id] or { active = true, gcd = false }
		return {
			startTime = MOCK.maybeSecret(990), duration = MOCK.maybeSecret(c.gcd and 1.5 or 10),
			isEnabled = true, modRate = 1, isActive = c.active, isOnGCD = c.gcd,
		}
	end,
	GetSpellCooldownDuration = function()
		return setmetatable({}, durationMT)
	end,
	GetSpellTexture = function()
		return 135920
	end,
	IsSpellUsable = function()
		return true, false
	end,
}

-- Auras -------------------------------------------------------------------------------
MOCK.auras = {
	{ name = "Devotion Aura", spellId = 465, duration = 0, expirationTime = 0 },
	{ name = "Seal of Righteousness", spellId = 21084, duration = 30, expirationTime = 1020 },
}
if not MOCK_NO_AURAS then
	C_UnitAuras = {
		GetAuraDataByIndex = function(unit, i)
			if unit ~= "player" then
				local list = MOCK.unitAuras[unit] or {}
				local a = list[i]
				if not a or MOCK.combat then
					return nil
				end
				return { name = a.name, spellId = a.spellId, duration = a.duration, expirationTime = a.expirationTime }
			end
			local a = MOCK.auras[i]
			if not a or MOCK.combat then
				return nil
			end
			return {
				name = MOCK.maybeSecret(a.name), spellId = MOCK.maybeSecret(a.spellId),
				duration = MOCK.maybeSecret(a.duration), expirationTime = MOCK.maybeSecret(a.expirationTime),
				auraInstanceID = i,
			}
		end,
		GetUnitAuraInstanceIDs = function()
			local ids = {}
			for i in ipairs(MOCK.auras) do
				ids[i] = i
			end
			return ids
		end,
		GetAuraDataByAuraInstanceID = function(_, id)
			return MOCK.combat and MOCK.secret() or MOCK.auras[id]
		end,
		GetAuraDuration = function()
			return setmetatable({}, durationMT)
		end,
		GetPlayerAuraBySpellID = function(id)
			if MOCK.combat then
				return nil
			end
			for _, a in ipairs(MOCK.auras) do
				if a.spellId == id then
					return { name = a.name, duration = MOCK.maybeSecret(a.duration) }
				end
			end
			return nil
		end,
	}
end

-- Addon messages -----------------------------------------------------------------------
C_ChatInfo = {
	-- The real client said true even out of combat while messages went
	-- through (party probe, 2026-09-24), so the addon must not rely on it.
	AreOutgoingAddonChatMessagesRestricted = function()
		return true
	end,
	RegisterAddonMessagePrefix = function()
		return 0
	end,
	IsAddonMessagePrefixRegistered = function()
		return true
	end,
	SendAddonMessage = function(prefix, text, channel, target)
		MOCK.sent[#MOCK.sent + 1] = { prefix = prefix, text = text, channel = channel, target = target }
		return 0
	end,
}

-- Secrets, restrictions, talents ---------------------------------------------------------
issecrettable = function()
	return false
end
C_Secrets = {
	HasSecretRestrictions = function()
		return true
	end,
	ShouldAurasBeSecret = function()
		return MOCK.combat
	end,
	ShouldCooldownsBeSecret = function()
		return MOCK.combat
	end,
	GetSpellAuraSecrecy = function()
		return 1
	end,
}
Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }
C_RestrictedActions = {
	-- Combat and Chat restrictions are active in combat.
	IsAddOnRestrictionActive = function(kind)
		return MOCK.combat and (kind == 0 or kind == 5)
	end,
}
Enum.SecretAspect = { Name = 1, Value = 2 }
C_ClassTalents = {
	GetActiveConfigID = function()
		return 7516683
	end,
}
C_Traits = {
	GetConfigInfo = function()
		return { ID = 7516683, name = "Paladin", treeIDs = { 900 } }
	end,
	GetTreeInfo = function()
		return { ID = 900 }
	end,
	GetTreeCurrencyInfo = function()
		return { { quantity = 0, maxQuantity = 0, spent = 0 } }
	end,
	GetTreeNodes = function()
		return { 1, 2 }
	end,
	-- MOCK.traitX / MOCK.traitRanks override a node's column and spent points.
	GetNodeInfo = function(_, nodeID)
		return { ID = nodeID, posX = (MOCK.traitX or {})[nodeID] or nodeID * 100, posY = 0,
			ranksPurchased = (MOCK.traitRanks or {})[nodeID] or 0, maxRanks = 5, entryIDs = { nodeID + 10 } }
	end,
	GetEntryInfo = function(_, entryID)
		return { definitionID = entryID + 10 }
	end,
	GetDefinitionInfo = function()
		return { spellID = 20473 }
	end,
}
