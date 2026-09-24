local ADDON_NAME, PK = ...

-- Namespace, error capture, event bus, module registry, slash commands.
-- Loads first. Everything here must work before SavedVariables are loaded
-- (they arrive with ADDON_LOADED), so early state lives in locals and is
-- attached to NyteLytePaladinToolkitDB once it exists.

_G.NyteLytePaladinToolkit = PK
PK.name = ADDON_NAME
PK.displayName = "Nyte Lyte's Paladin Toolkit"
PK.chatName = "Paladin Toolkit"
PK.version = "dev"
PK.modules = {}
PK.moduleOrder = {}
PK.unknownEvents = {}

local COLOR = "|cfff58cba"
local MAX_ERRORS = 30
local MAX_DEBUG = 300

-- Error capture ------------------------------------------------------------
-- Lua errors mentioning this addon are kept (deduplicated) and saved to
-- NyteLytePaladinToolkitDB.errors so they can be read from disk after /reload.
local earlyErrors = {}
PK.errorList = earlyErrors

local function recordError(msg)
	if type(msg) ~= "string" or not msg:find(ADDON_NAME, 1, true) then
		return
	end
	local list = PK.errorList
	for _, e in ipairs(list) do
		if e.msg == msg then
			e.count = e.count + 1
			e.last = time()
			return
		end
	end
	if #list >= MAX_ERRORS then
		table.remove(list, 1)
	end
	local stack = debugstack and debugstack(3, 8, 0) or nil
	list[#list + 1] = { msg = msg, count = 1, first = time(), last = time(), stack = stack }
end

pcall(function()
	local prev = geterrorhandler()
	seterrorhandler(function(msg, ...)
		pcall(recordError, msg)
		if prev then
			return prev(msg, ...)
		end
	end)
end)

local function callErrorHandler(err)
	local h = geterrorhandler()
	if h then
		return h(err)
	end
end

-- Calls fn without letting one failing handler break the others. (Plain Lua
-- 5.1 xpcall takes no extra arguments, so they go through a closure.)
function PK.SafeCall(fn, ...)
	local n, args = select("#", ...), { ... }
	return xpcall(function()
		return fn(unpack(args, 1, n))
	end, callErrorHandler)
end

-- Printing and debug log ---------------------------------------------------
function PK:Print(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	print(COLOR .. PK.chatName .. "|r: " .. table.concat(parts, " "))
end

local debugLog = {}
PK.debugLog = debugLog

-- Only pass values already known to be safe (never raw API values in combat).
function PK:Debug(fmt, ...)
	if not (self.db and self.db.debug) then
		return
	end
	local ok, line = pcall(string.format, fmt, ...)
	if not ok then
		line = tostring(fmt) .. " <format error>"
	end
	line = string.format("%.1f %s", GetTime(), line)
	if #debugLog >= MAX_DEBUG then
		table.remove(debugLog, 1)
	end
	debugLog[#debugLog + 1] = line
end

-- Event bus ------------------------------------------------------------------
-- WoW events: PK:RegisterEvent(event, owner, fn). fn(owner, event, ...).
-- Returns false (and records the name) if the client doesn't know the event.
local eventFrame = CreateFrame("Frame")
local handlers = {}

local function snapshot(t)
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = v
	end
	return copy
end

function PK:RegisterEvent(event, owner, fn)
	if not handlers[event] then
		local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
		if not ok then
			PK.unknownEvents[event] = true
			return false
		end
		handlers[event] = {}
	end
	handlers[event][owner] = fn
	return true
end

function PK:UnregisterEvent(event, owner)
	local h = handlers[event]
	if not h then
		return
	end
	h[owner] = nil
	if next(h) == nil then
		handlers[event] = nil
		pcall(eventFrame.UnregisterEvent, eventFrame, event)
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local h = handlers[event]
	if not h then
		return
	end
	for owner, fn in pairs(snapshot(h)) do
		PK.SafeCall(fn, owner, event, ...)
	end
end)

-- Internal messages: PK:On("PK_SPEC_CHANGED", owner, fn), PK:Fire(msg, ...).
local listeners = {}

function PK:On(msg, owner, fn)
	listeners[msg] = listeners[msg] or {}
	listeners[msg][owner] = fn
end

function PK:Off(msg, owner)
	if listeners[msg] then
		listeners[msg][owner] = nil
	end
end

function PK:Fire(msg, ...)
	local l = listeners[msg]
	if not l then
		return
	end
	for owner, fn in pairs(snapshot(l)) do
		PK.SafeCall(fn, owner, msg, ...)
	end
end

-- Runs fn once, `delay` seconds after the last call with the same key.
-- Collapses bursts of events (e.g. several SPELLS_CHANGED in a row).
local debounceGen = {}
function PK:Debounce(key, delay, fn)
	local gen = (debounceGen[key] or 0) + 1
	debounceGen[key] = gen
	C_Timer.After(delay, function()
		if debounceGen[key] == gen then
			PK.SafeCall(fn)
		end
	end)
end

-- Modules --------------------------------------------------------------------
-- PK:RegisterModule(name, { OnEnable, OnDisable, OnSpecChanged, defaults,
-- alwaysOn }). M0 only enables alwaysOn modules; the per-spec matrix
-- arrives with SpecProfile in M1.
function PK:RegisterModule(name, def)
	def.name = name
	def.enabled = false
	self.modules[name] = def
	self.moduleOrder[#self.moduleOrder + 1] = name
	return def
end

function PK:EnableModule(name)
	local m = self.modules[name]
	if not m or m.enabled then
		return
	end
	m.enabled = true
	if m.OnEnable then
		PK.SafeCall(m.OnEnable, m)
	end
end

function PK:DisableModule(name)
	local m = self.modules[name]
	if not m or not m.enabled then
		return
	end
	m.enabled = false
	if m.OnDisable then
		PK.SafeCall(m.OnDisable, m)
	end
end

-- Slash commands -------------------------------------------------------------
local commands, commandOrder = {}, {}

-- fn(args, rawArgs): the words after the command, lowercased and as typed.
function PK:RegisterCommand(word, fn, help)
	commands[word] = { fn = fn, help = help }
	commandOrder[#commandOrder + 1] = word
end

local function printHelp()
	PK:Print("commands (version " .. PK.version .. "):")
	for _, word in ipairs(commandOrder) do
		local c = commands[word]
		if c.help then
			print("  /ptk " .. word .. " - " .. c.help)
		end
	end
end

SLASH_NYTELYTEPALADINTOOLKIT1 = "/ptk"
SLASH_NYTELYTEPALADINTOOLKIT2 = "/paladintoolkit"
SlashCmdList.NYTELYTEPALADINTOOLKIT = function(msg)
	local words, raw = {}, {}
	for w in (msg or ""):gmatch("%S+") do
		raw[#raw + 1] = w
		words[#words + 1] = w:lower()
	end
	if not words[1] and PK.Settings then
		PK.Settings:Open()
		return
	end
	local c = commands[words[1]]
	if not c then
		printHelp()
		return
	end
	table.remove(words, 1)
	table.remove(raw, 1)
	PK.SafeCall(c.fn, words, raw)
end

PK:RegisterCommand("help", printHelp, "list commands")
PK:RegisterCommand("errors", function()
	PK:Print("to see Lua errors as popups, type: /console scriptErrors 1")
	PK:Print(#PK.errorList .. " error(s) captured this session and saved on /reload.")
	if #PK.errorList > 0 and PK.CopyWindow then
		local lines = {}
		for _, e in ipairs(PK.errorList) do
			lines[#lines + 1] = string.format("[x%d] %s\n%s", e.count, e.msg, e.stack or "")
		end
		PK.CopyWindow:Show(PK.displayName .. " - errors", table.concat(lines, "\n\n"))
	end
end, "show captured Lua errors")

-- Lifecycle ------------------------------------------------------------------
local lifecycle = {}

PK:RegisterEvent("ADDON_LOADED", lifecycle, function(_, _, name)
	if name ~= ADDON_NAME then
		return
	end
	PK:UnregisterEvent("ADDON_LOADED", lifecycle)

	local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
	if meta then
		local ok, v = pcall(meta, ADDON_NAME, "Version")
		if ok and v then
			PK.version = v
		end
	end

	-- Record whether SavedVariables actually came back (Forever beta has a
	-- reported bug where they are written but not loaded on a fresh start).
	local existed = type(NyteLytePaladinToolkitDB) == "table"
	if not existed then
		NyteLytePaladinToolkitDB = {}
	end
	local db = NyteLytePaladinToolkitDB
	db.meta = db.meta or {}
	local m = db.meta
	PK.svState = {
		existedAtLoad = existed,
		previousSession = m.session,
		previousLoginAt = m.loginAt,
		previousLogoutAt = m.logoutAt,
		loads = (m.loads or 0) + 1,
	}
	m.loads = PK.svState.loads
	m.session = string.format("%d-%04d", time(), math.random(0, 9999))
	m.loginAt = time()
	m.version = PK.version

	-- Keep errors from this session only, including any raised during load.
	db.errors = earlyErrors
	db.debugLog = debugLog
	PK.db = db
	PK:Fire("PK_DB_READY", db)
end)

PK:RegisterEvent("PLAYER_LOGIN", lifecycle, function()
	local _, class = UnitClass("player")
	PK.playerClass = class
	PK.isPaladin = class == "PALADIN"
	for _, name in ipairs(PK.moduleOrder) do
		if PK.modules[name].alwaysOn then
			PK:EnableModule(name)
		end
	end
	PK:Fire("PK_READY")
end)

PK:RegisterEvent("PLAYER_LOGOUT", lifecycle, function()
	if PK.db then
		PK.db.meta.logoutAt = time()
	end
end)
