local _, PK = ...

-- Proc tracker, first test build: stacks and timers of your own procs
-- (Ret: Vengeance, Echo / Unsealed Wrath; Holy: Infusion of Light; Prot:
-- Holy Shield charges). Forever hides your buffs from addons in combat, so
-- this tries every route and logs which one works, to
-- NyteLytePaladinToolkitDB.procLog:
--  * out of combat: every buff you gain is logged once (name, spell ID,
--    stacks, duration), to learn the real names and IDs;
--  * in combat: what UNIT_AURA hands over (aura instance IDs, which fields
--    are secret), and whether the game will draw a hidden stack count or
--    timer for us (C_UnitAuras.GetAuraApplicationDisplayCount /
--    GetAuraDuration, passed straight to the icon without reading them).
-- Shows up to 4 small icons to the right of the Seal Tracker while a
-- watched proc is up.

local Compat = PK.Compat
local Describe = Compat.Describe
local W = { tracked = {}, known = {} }
PK.ProcWatch = W

local LOG_MAX = 120
local ICON_SIZE = 28
local WATCH = { "vengeance", "unsealed", "wrath", "echo", "infusion", "holy shield", "twist" }
local logged = {}
local icons = {}
local combatTicker

local function log(event, fields, onceKey)
	local db = PK.db
	if not db or (onceKey and logged[onceKey]) then
		return
	end
	if onceKey then
		logged[onceKey] = true
	end
	db.procLog = db.procLog or {}
	local row = { t = time(), event = event, inCombat = Compat.InCombat() or nil }
	for k, v in pairs(fields or {}) do
		row[k] = v
	end
	table.insert(db.procLog, row)
	while #db.procLog > LOG_MAX do
		table.remove(db.procLog, 1)
	end
end
W.Log = log

local function plainString(v)
	return type(v) == "string" and not Compat.IsSecret(v) and v or nil
end

local function plainNumber(v)
	return type(v) == "number" and not Compat.IsSecret(v) and v or nil
end

local function isWatchedName(name)
	local l = plainString(name) and name:lower()
	if not l then
		return false
	end
	for _, w in ipairs(WATCH) do
		if l:find(w, 1, true) then
			return true
		end
	end
	return false
end

local function call(path, ...)
	local fn = Compat.Resolve(path)
	if not fn then
		return "missing"
	end
	local ok, a, b = pcall(fn, ...)
	if not ok then
		return "error: " .. tostring(a), nil
	end
	return a, b
end

-- Display ----------------------------------------------------------------------------------

local function anchor()
	return PK.Frames:GetAnchor("SealTracker")
end

local function layout()
	local i = 0
	for _, t in pairs(W.tracked) do
		i = i + 1
		local icon = icons[t.auraInstanceID]
		if icon then
			icon:ClearAllPoints()
			icon:SetPoint("LEFT", anchor(), "RIGHT", 6 + (i - 1) * (ICON_SIZE + 3), 0)
		end
	end
end

-- Draws a tracked aura: icon from what we know, stacks and timer through
-- the game's display-only paths (values stay hidden from the addon).
local function draw(t)
	local icon = icons[t.auraInstanceID]
	if not icon then
		if not PK.Frames.AcquireIcon then
			return
		end
		icon = PK.Frames:AcquireIcon(anchor(), ICON_SIZE)
		icons[t.auraInstanceID] = icon
	end
	icon.icon:SetTexture(t.icon or 134400)
	local count = call("C_UnitAuras.GetAuraApplicationDisplayCount", "player", t.auraInstanceID, 2, 99)
	local okText = pcall(icon.text.SetText, icon.text, count ~= "missing" and count or "")
	local duration = call("C_UnitAuras.GetAuraDuration", "player", t.auraInstanceID)
	local okCd = duration ~= "missing" and type(duration) ~= "string" and icon:SetCooldownFromDuration(duration)
	log("draw", {
		name = t.name, count = Describe(count), countShown = okText, duration = Describe(duration),
		timerShown = okCd and true or false,
	}, "draw:" .. tostring(t.name) .. ":" .. tostring(Compat.InCombat()))
	-- In combat: does the count for a known aura instance still come back,
	-- and does it change (stacks gained mid-fight)? Logged each time it
	-- changes, a few times per fight.
	if Compat.InCombat() then
		local shown = Compat.IsSecret(count) and "<secret>" or tostring(count)
		if t.lastShown ~= shown then
			t.lastShown = shown
			t.combatChanges = (t.combatChanges or 0) + 1
			if t.combatChanges <= 6 then
				log("combatCount", { name = t.name, count = Describe(count), duration = Describe(duration),
					countShown = okText, timerShown = okCd and true or false })
			end
		end
	end
	icon:Show()
	layout()
end

local function drop(id)
	local icon = icons[id]
	if icon then
		icon:Hide()
		icons[id] = nil
		if PK.Frames.ReleaseIcon then
			PK.Frames:ReleaseIcon(icon)
		end
	end
	W.tracked[id] = nil
	layout()
end

-- Aura events ------------------------------------------------------------------------------

-- A whole aura table from UNIT_AURA or a lookup: remember it if it's a
-- watched proc we can identify (name or a spell ID seen earlier).
local function consider(aura, source)
	if type(aura) ~= "table" or Compat.IsSecret(aura) then
		return
	end
	local id = plainNumber(aura.auraInstanceID)
	local name = plainString(aura.name)
	local spellId = plainNumber(aura.spellId)
	local watched = isWatchedName(name) or (spellId and W.known[spellId])
	if not Compat.InCombat() and Compat.IsSecret(aura.isHelpful) == false and aura.isHelpful ~= false and name then
		log("seen", {
			name = name, spellId = spellId, stacks = Describe(aura.applications),
			duration = Describe(aura.duration), watched = watched or nil, via = source,
		}, "seen:" .. name)
		if watched and spellId then
			W.known[spellId] = name
		end
	end
	if watched and id then
		W.tracked[id] = { auraInstanceID = id, name = name or W.known[spellId], icon = plainNumber(aura.icon) }
		draw(W.tracked[id])
	end
end

local function onAura(_, _, unit, info)
	if unit ~= "player" then
		return
	end
	local inCombat = Compat.InCombat()
	if type(info) ~= "table" or Compat.IsSecret(info) then
		log("auraEvent", { info = Describe(info) }, "info:" .. tostring(inCombat))
		return
	end
	-- In combat Forever hands these over as secret tables (seen 2026-11-26:
	-- addedAuras and isFullUpdate secret): they can't even be indexed.
	local function plainTable(v)
		return type(v) == "table" and not Compat.IsSecret(v) and v or nil
	end
	local added = plainTable(info.addedAuras)
	local updated = plainTable(info.updatedAuraInstanceIDs)
	local removed = plainTable(info.removedAuraInstanceIDs)
	log("auraEventShape", {
		addedSecret = Compat.IsSecret(info.addedAuras) or nil,
		updatedSecret = Compat.IsSecret(info.updatedAuraInstanceIDs) or nil,
		removedSecret = Compat.IsSecret(info.removedAuraInstanceIDs) or nil,
		hasAdded = info.addedAuras ~= nil, hasUpdated = info.updatedAuraInstanceIDs ~= nil,
		hasRemoved = info.removedAuraInstanceIDs ~= nil,
	}, "shape:" .. tostring(inCombat) .. ":" .. tostring(info.addedAuras ~= nil) .. tostring(info.updatedAuraInstanceIDs ~= nil)
		.. tostring(info.removedAuraInstanceIDs ~= nil))
	-- What the event carries, once per combat state.
	local first = added and added[1]
	log("auraEvent", {
		isFullUpdate = Describe(info.isFullUpdate),
		added = type(added) == "table" and #added or Describe(added),
		updated = type(updated) == "table" and #updated or Describe(updated),
		removed = type(removed) == "table" and #removed or Describe(removed),
		firstName = first and Describe(first.name), firstSpellId = first and Describe(first.spellId),
		firstStacks = first and Describe(first.applications), firstInstance = first and Describe(first.auraInstanceID),
	}, "event:" .. tostring(inCombat) .. ":" .. tostring(first ~= nil))
	if type(added) == "table" then
		for _, aura in ipairs(added) do
			consider(aura, "added")
		end
	end
	if type(updated) == "table" then
		for _, id in ipairs(updated) do
			id = plainNumber(id)
			if id and W.tracked[id] then
				draw(W.tracked[id])
			elseif id then
				-- Can we look an updated aura up in combat?
				local data = call("C_UnitAuras.GetAuraDataByAuraInstanceID", "player", id)
				log("lookup", { result = Describe(data),
					name = type(data) == "table" and not Compat.IsSecret(data) and Describe(data.name) or nil },
					"lookup:" .. tostring(inCombat))
				consider(data, "lookup")
			end
		end
	end
	if type(removed) == "table" then
		for _, id in ipairs(removed) do
			id = plainNumber(id)
			if id and W.tracked[id] then
				drop(id)
			end
		end
	end
end

-- Out of combat: a full scan, so watched procs already up are tracked and
-- their names and IDs are learned before the pull.
local function scan()
	if Compat.InCombat() then
		return
	end
	local list = Compat.GetAuras("player", "HELPFUL")
	local present = {}
	for _, aura in ipairs(list) do
		local id = plainNumber(aura.auraInstanceID)
		if id then
			present[id] = true
		end
		consider(aura, "scan")
	end
	for id in pairs(W.tracked) do
		if not present[id] then
			drop(id)
		end
	end
end

-- In combat, by spell ID: does a direct lookup of a known proc work?
local function probeKnown()
	for spellId, name in pairs(W.known) do
		local data = call("C_UnitAuras.GetPlayerAuraBySpellID", spellId)
		log("bySpellID", { name = name, result = Describe(data),
			stacks = type(data) == "table" and not Compat.IsSecret(data) and Describe(data.applications) or nil },
			"byid:" .. spellId)
	end
end

PK:RegisterEvent("UNIT_AURA", W, onAura)
PK:RegisterEvent("PLAYER_REGEN_ENABLED", W, function()
	if combatTicker then
		combatTicker:Cancel()
		combatTicker = nil
	end
	-- Log the next fight again (buffs already seen stay logged once).
	for k in pairs(logged) do
		if k:sub(1, 5) ~= "seen:" then
			logged[k] = nil
		end
	end
	scan()
end)
PK:RegisterEvent("PLAYER_REGEN_DISABLED", W, function()
	log("combatStart", { aurasSecret = Describe(Compat.AurasAreSecret()) })
	C_Timer.After(3, probeKnown)
	-- Is there any way to list your buffs' instance IDs in combat?
	C_Timer.After(4, function()
		local ids = call("C_UnitAuras.GetUnitAuraInstanceIDs", "player", "HELPFUL")
		log("instanceIDs", { result = Describe(ids),
			count = type(ids) == "table" and not Compat.IsSecret(ids) and #ids or nil }, "ids")
	end)
	-- Redraw known procs during the fight (display-only reads).
	for _, t in pairs(W.tracked) do
		t.lastShown, t.combatChanges = nil, 0
	end
	if C_Timer.NewTicker then
		combatTicker = C_Timer.NewTicker(0.5, function()
			for _, t in pairs(W.tracked) do
				draw(t)
			end
		end)
	end
end)

PK:On("PK_READY", W, function()
	C_Timer.After(2, scan)
end)
