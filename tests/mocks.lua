-- Minimal mocked WoW API, shaped like what WoW Forever's beta client showed
-- in the first /ptk probe (build 1.60.1.69977, 2026-09-24): player health,
-- power and absorbs are secret even out of combat; in combat, cooldown
-- start/duration/modRate are secret but isActive/isEnabled are not, and the
-- player's own aura queries return nothing. It checks our logic and our secret-value
-- discipline, not the real client. Secret values are proxies that error on
-- comparison, arithmetic and concatenation, like Midnight-style secrets.

MOCK = { combat = false, timers = {}, printed = {}, errorsRaised = {}, sent = {}, level = 20 }

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
function UnitClass()
	return "Paladin", "PALADIN", 2
end
function UnitRace()
	return "Human", "Human"
end
function UnitLevel()
	return MOCK.level
end
function UnitName()
	return "Tester"
end
function UnitExists()
	return true
end
function IsInGroup()
	return false
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

C_Timer = {
	After = function(delay, fn)
		MOCK.timers[#MOCK.timers + 1] = { delay = delay, fn = fn }
	end,
}
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
	"UNIT_SPELLCAST_SUCCEEDED",
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
function frameMethods:CreateFontString()
	return MOCK.newFrame("FontString")
end
function frameMethods:CreateTexture()
	return MOCK.newFrame("Texture")
end
local noop = function() end
local frameMT = {
	__index = function(_, k)
		return frameMethods[k] or noop
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
	{ name = "Devotion Aura", spellID = 465, itemType = 1 },
	{ name = "Blessing of Might", spellID = 19740, itemType = 1 },
	{ name = "Judgement", spellID = 20271, itemType = 1 },
	{ name = "Holy Strike", spellID = 900001, itemType = 1 },
	{ name = "Righteous Fury", spellID = 25780, itemType = 1 },
	{ name = "Holy Shock", spellID = 20473, itemType = 1 },
	{ name = "Blessing of Kings", spellID = 20217, itemType = 2 },
	{ name = "Blessings", actionID = 264, itemType = 4 },
	{ name = "Flash of Light", spellID = 19750, itemType = 1 },
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
	GetSpellCooldown = function()
		return {
			startTime = MOCK.maybeSecret(990), duration = MOCK.maybeSecret(10),
			isEnabled = true, modRate = 1, isActive = true,
		}
	end,
	GetSpellCooldownDuration = function()
		return setmetatable({}, durationMT)
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
		GetAuraDataByIndex = function(_, i)
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
	GetSpellAuraSecrecy = function()
		return 1
	end,
}
C_RestrictedActions = {
	IsAddOnRestrictionActive = function()
		return false
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
	GetNodeInfo = function(_, nodeID)
		return { ID = nodeID, posX = nodeID * 100, posY = 0, ranksPurchased = 0, maxRanks = 5, entryIDs = { nodeID + 10 } }
	end,
	GetEntryInfo = function(_, entryID)
		return { definitionID = entryID + 10 }
	end,
	GetDefinitionInfo = function()
		return { spellID = 20473 }
	end,
}
