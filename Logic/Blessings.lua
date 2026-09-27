local _, PK = ...

-- Blessing Manager logic, pure Lua (no WoW APIs) so it can be unit tested:
-- class/blessing/aura codes, the auto-suggest layout, the sync message
-- format, conflict resolution, and "who is missing my blessing".
--
-- An assignment row (one per paladin):
--   { classes = { WARRIOR = "BLESSING_KINGS", ... }, aura = "AURA_DEVOTION",
--     seq = 3, ts = 1790235093, by = "Nytelyte" }
-- Keys are Data/Spells.lua registry keys.

local B = {}
PK.Blessings = B

-- Classic classes (WoW Forever is Classic+).
B.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local CLASS_CODE = {
	WARRIOR = "WA", PALADIN = "PA", HUNTER = "HU", ROGUE = "RO", PRIEST = "PR",
	SHAMAN = "SH", MAGE = "MA", WARLOCK = "WL", DRUID = "DR",
}
local BLESSING_CODE = {
	BLESSING_MIGHT = "MI", BLESSING_WISDOM = "WI", BLESSING_KINGS = "KI", BLESSING_LIGHT = "LI",
	BLESSING_SALVATION = "SA", BLESSING_FREEDOM = "FR", BLESSING_PROTECTION = "PR", BLESSING_SACRIFICE = "SC",
}
local AURA_CODE = {
	AURA_DEVOTION = "DE", AURA_RETRIBUTION = "RE", AURA_CONCENTRATION = "CO", AURA_FIRE = "FI",
	AURA_FROST = "FO", AURA_SHADOW = "SD", AURA_CRUSADER = "CR", AURA_SANCTITY = "SN",
}

local function invert(t)
	local out = {}
	for k, v in pairs(t) do
		out[v] = k
	end
	return out
end
local CODE_CLASS, CODE_BLESSING, CODE_AURA = invert(CLASS_CODE), invert(BLESSING_CODE), invert(AURA_CODE)

B.CLASS_CODE, B.BLESSING_CODE, B.AURA_CODE = CLASS_CODE, BLESSING_CODE, AURA_CODE

-- Per-player exceptions ("overrides") on a paladin's row. The value is a
-- blessing key, or B.NONE for "don't buff this player". Keyed by player
-- GUID. Capped so a row still fits in one addon message.
B.NONE = "NONE"
B.MAX_OVERRIDES = 8
local NONE_CODE = "NO"

local function validOverride(key)
	return key == B.NONE or BLESSING_CODE[key] ~= nil
end

-- Class-wide blessings a paladin can assign (Freedom/Protection/Sacrifice
-- are short single-target spells, not assignments).
B.ASSIGNABLE = { "BLESSING_KINGS", "BLESSING_MIGHT", "BLESSING_WISDOM", "BLESSING_SALVATION", "BLESSING_LIGHT" }

-- "Greater Blessing of Might" counts as "Blessing of Might".
B.GREATER = {
	GREATER_MIGHT = "BLESSING_MIGHT", GREATER_WISDOM = "BLESSING_WISDOM", GREATER_KINGS = "BLESSING_KINGS",
	GREATER_LIGHT = "BLESSING_LIGHT", GREATER_SALVATION = "BLESSING_SALVATION",
}

-- Preferred order per class. No Salvation for warriors (they may be tanking).
local CASTER = { "BLESSING_WISDOM", "BLESSING_KINGS", "BLESSING_SALVATION", "BLESSING_LIGHT" }
local HYBRID = { "BLESSING_KINGS", "BLESSING_WISDOM", "BLESSING_MIGHT", "BLESSING_SALVATION", "BLESSING_LIGHT" }
B.PRIORITY = {
	WARRIOR = { "BLESSING_KINGS", "BLESSING_MIGHT", "BLESSING_LIGHT" },
	ROGUE = { "BLESSING_MIGHT", "BLESSING_KINGS", "BLESSING_SALVATION", "BLESSING_LIGHT" },
	HUNTER = { "BLESSING_MIGHT", "BLESSING_KINGS", "BLESSING_WISDOM", "BLESSING_SALVATION", "BLESSING_LIGHT" },
	PALADIN = HYBRID,
	SHAMAN = HYBRID,
	DRUID = HYBRID,
	PRIEST = CASTER,
	MAGE = CASTER,
	WARLOCK = CASTER,
}
B.AURA_PRIORITY = { "AURA_DEVOTION", "AURA_RETRIBUTION", "AURA_CONCENTRATION", "AURA_SANCTITY",
	"AURA_CRUSADER", "AURA_FIRE", "AURA_FROST", "AURA_SHADOW" }

-- What we assume a paladin knows when they don't run the addon.
B.ASSUMED_BLESSINGS = { BLESSING_MIGHT = true, BLESSING_WISDOM = true }
B.ASSUMED_AURAS = { AURA_DEVOTION = true }

-- Auto-suggest -----------------------------------------------------------------------------

-- paladins: list of { name, blessings = set|nil, auras = set|nil }
-- opts.tanks: optional list of { guid, class } for players in the tank role.
-- Returns { [name] = { classes = {...}, aura = key|nil, overrides = {...} } }.
-- Each paladin gives at most one blessing per class, no blessing is doubled
-- up on a class, and classes only get blessings from their priority list.
-- Tanks never keep Salvation (it lowers threat): the paladin giving their
-- class Salvation gets an exception with the next best Blessing for them.
function B.Suggest(paladins, opts)
	local list = {}
	for _, p in ipairs(paladins) do
		list[#list + 1] = p
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	local out = {}
	for _, p in ipairs(list) do
		out[p.name] = { classes = {}, overrides = {} }
	end
	for _, class in ipairs(B.CLASSES) do
		local given = {} -- blessing -> true for this class
		local assigned = {} -- paladin name -> true for this class
		local function tryAssign(key)
			if given[key] then
				return
			end
			for _, p in ipairs(list) do
				local known = p.blessings or B.ASSUMED_BLESSINGS
				if not assigned[p.name] and known[key] then
					out[p.name].classes[class] = key
					assigned[p.name] = true
					given[key] = true
					return
				end
			end
		end
		-- Only blessings that help this class; a cell stays empty rather than
		-- getting something useless (e.g. Might on a Mage).
		for _, key in ipairs(B.PRIORITY[class]) do
			tryAssign(key)
		end
	end
	for _, tank in ipairs((opts and opts.tanks) or {}) do
		local class = tank.class
		for _, p in ipairs(list) do
			local row = out[p.name]
			if tank.guid and row.classes[class] == "BLESSING_SALVATION" then
				local given = {}
				for _, other in ipairs(list) do
					local k = out[other.name].classes[class]
					if k then
						given[k] = true
					end
				end
				local known = p.blessings or B.ASSUMED_BLESSINGS
				local alt = B.NONE
				for _, key in ipairs(B.PRIORITY[class] or {}) do
					if key ~= "BLESSING_SALVATION" and known[key] and not given[key] then
						alt = key
						break
					end
				end
				row.overrides = row.overrides or {}
				row.overrides[tank.guid] = alt
			end
		end
	end
	local auraTaken = {}
	for _, p in ipairs(list) do
		local known = p.auras or B.ASSUMED_AURAS
		for _, key in ipairs(B.AURA_PRIORITY) do
			if known[key] and not auraTaken[key] then
				out[p.name].aura = key
				auraTaken[key] = true
				break
			end
		end
	end
	return out
end

-- Conflict resolution --------------------------------------------------------------------------

-- Applies a row update for `paladin`. meta = { sender, senderIsLeader }.
-- Paladins edit their own row; leader/assistants may edit any row.
-- Newest seq wins, then newest ts, then leader/assist, then the
-- alphabetically first sender (deterministic on every client).
-- Returns true, or false and a reason.
function B.ApplyRow(assignments, paladin, row, meta)
	if type(paladin) ~= "string" or paladin == "" or type(row) ~= "table" then
		return false, "invalid"
	end
	meta = meta or {}
	if meta.sender ~= paladin and not meta.senderIsLeader then
		return false, "no permission"
	end
	local seq, ts = tonumber(row.seq) or 0, tonumber(row.ts) or 0
	local cur = assignments[paladin]
	if cur then
		local cseq, cts = tonumber(cur.seq) or 0, tonumber(cur.ts) or 0
		local newer
		if seq ~= cseq then
			newer = seq > cseq
		elseif ts ~= cts then
			newer = ts > cts
		elseif (meta.senderIsLeader and true or false) ~= (cur.byLeader and true or false) then
			newer = meta.senderIsLeader and true or false
		else
			newer = tostring(meta.sender) < tostring(cur.by)
		end
		if not newer then
			return false, "stale"
		end
	end
	local classes = {}
	for class, key in pairs(row.classes or {}) do
		if CLASS_CODE[class] and BLESSING_CODE[key] then
			classes[class] = key
		end
	end
	local overrides, count = {}, 0
	for target, key in pairs(row.overrides or {}) do
		if B.IsGUID(target) and validOverride(key) and count < B.MAX_OVERRIDES then
			overrides[target] = key
			count = count + 1
		end
	end
	assignments[paladin] = {
		classes = classes,
		overrides = overrides,
		aura = AURA_CODE[row.aura or ""] and row.aura or nil,
		seq = seq,
		ts = ts,
		by = meta.sender,
		byLeader = meta.senderIsLeader and true or nil,
	}
	return true
end

-- Messages ---------------------------------------------------------------------------------------
-- HELLO|<version>|<blessing codes>|<aura codes>|<GUID>|<name>
--                                   who I am (GUID = identity) and what I know
-- ROW|<seq>|<ts>|<paladin GUID>|<aura code>|WA=KI,PA=MI  one paladin's full row
-- REQ                               please introduce yourself and send your rows
-- Players are identified by GUID, never by name: Forever names have two
-- parts and different APIs return different parts. A HELLO without a GUID
-- comes from 0.6.0 or older.
-- All messages stay far below the 255-byte addon message limit.

local MAX_NAME = 48

local function validName(name)
	return type(name) == "string" and #name > 0 and #name <= MAX_NAME and not name:find("[|,=]")
end

local function codes(set, map)
	local out = {}
	for key in pairs(set or {}) do
		if map[key] then
			out[#out + 1] = map[key]
		end
	end
	table.sort(out)
	return table.concat(out, ",")
end

local function decodeSet(text, map)
	local set = {}
	for code in (text or ""):gmatch("[^,]+") do
		if map[code] then
			set[map[code]] = true
		end
	end
	return set
end

-- "Player-4621-0ABCDEF1"
function B.IsGUID(s)
	return type(s) == "string" and #s <= 40 and s:match("^Player%-[%w%-]+$") ~= nil
end

local function cleanName(name)
	if type(name) ~= "string" then
		return ""
	end
	return (name:gsub("[|,=]", ""):sub(1, MAX_NAME))
end

function B.EncodeHello(version, blessings, auras, guid, name)
	return "HELLO|" .. tostring(version):sub(1, 20):gsub("|", "") .. "|" .. codes(blessings, BLESSING_CODE)
		.. "|" .. codes(auras, AURA_CODE) .. "|" .. (B.IsGUID(guid) and guid or "") .. "|" .. cleanName(name)
end

function B.EncodeRow(paladin, row)
	local parts = {}
	for _, class in ipairs(B.CLASSES) do
		local key = row.classes and row.classes[class]
		if key and BLESSING_CODE[key] then
			parts[#parts + 1] = CLASS_CODE[class] .. "=" .. BLESSING_CODE[key]
		end
	end
	local ovr = {}
	for target, key in pairs(row.overrides or {}) do
		if B.IsGUID(target) and validOverride(key) and #ovr < B.MAX_OVERRIDES then
			ovr[#ovr + 1] = target:sub(8) .. "=" .. (key == B.NONE and NONE_CODE or BLESSING_CODE[key])
		end
	end
	table.sort(ovr)
	return string.format("ROW|%d|%d|%s|%s|%s|%s", tonumber(row.seq) or 0, tonumber(row.ts) or 0, paladin,
		AURA_CODE[row.aura or ""] or "", table.concat(parts, ","), table.concat(ovr, ","))
end

function B.EncodeRequest()
	return "REQ"
end

-- Returns a message table or nil for anything malformed.
function B.Decode(text)
	if type(text) ~= "string" or #text > 255 then
		return nil
	end
	local fields = {}
	for f in (text .. "|"):gmatch("([^|]*)|") do
		fields[#fields + 1] = f
	end
	local kind = fields[1]
	if kind == "HELLO" then
		local name = fields[6]
		return {
			type = "HELLO",
			version = fields[2] or "?",
			blessings = decodeSet(fields[3], CODE_BLESSING),
			auras = decodeSet(fields[4], CODE_AURA),
			guid = B.IsGUID(fields[5]) and fields[5] or nil, -- nil: sent by 0.6.0 or older
			name = (validName(name) or (type(name) == "string" and #name > 0 and #name <= MAX_NAME
				and not name:find("[|,=]"))) and name or nil,
		}
	elseif kind == "ROW" then
		local seq, ts, paladin = tonumber(fields[2]), tonumber(fields[3]), fields[4]
		if not seq or not ts or not validName(paladin) then
			return nil
		end
		local classes = {}
		for pair in (fields[6] or ""):gmatch("[^,]+") do
			local c, b = pair:match("^(%u%u)=(%u%u)$")
			if c and CODE_CLASS[c] and CODE_BLESSING[b] then
				classes[CODE_CLASS[c]] = CODE_BLESSING[b]
			end
		end
		-- Field 7 (0.7.0+): per-player exceptions, GUID without "Player-".
		local overrides = {}
		for pair in (fields[7] or ""):gmatch("[^,]+") do
			local id, code = pair:match("^([%w%-]+)=(%u%u)$")
			local target = id and ("Player-" .. id)
			if target and B.IsGUID(target) then
				local key = code == NONE_CODE and B.NONE or CODE_BLESSING[code]
				if key then
					overrides[target] = key
				end
			end
		end
		return { type = "ROW", seq = seq, ts = ts, paladin = paladin, aura = CODE_AURA[fields[5] or ""],
			classes = classes, overrides = overrides }
	elseif kind == "REQ" then
		return { type = "REQ" }
	end
	return nil
end

-- Buffing ----------------------------------------------------------------------------------------

-- The blessing `paladin` should give a player of `class` (with GUID `target`,
-- optional), or nil. A per-player exception wins over the class assignment;
-- B.NONE means "don't buff them".
function B.AssignedFor(assignments, paladin, class, target)
	local row = assignments[paladin]
	if not row then
		return nil
	end
	local o = target and row.overrides and row.overrides[target]
	if o == B.NONE then
		return nil
	elseif o then
		return o
	end
	return row.classes and row.classes[class] or nil
end

-- members: ordered list of { unit, name, class, usable = bool, buffs = map|nil }
-- buffs maps blessing key -> expirationTime (0 = no expiry); nil = unreadable.

-- Seconds left on a member's blessing: nil if missing, math.huge if permanent.
function B.Remaining(member, key, now)
	local exp = member.buffs and member.buffs[key]
	if exp == nil then
		return nil
	end
	if exp == 0 then
		return math.huge
	end
	local left = exp - now
	return left > 0 and left or nil
end

-- Who the buff button should target next. Returns member, key, remaining,
-- reason, where reason is:
--   "missing"  someone has no copy of your assigned blessing (first in order)
--   "expiring" under refreshSec left (the lowest first)
--   "lowest"   nobody needs it, but refreshLowest is on: the lowest timer,
--              so each press refreshes the oldest blessing
-- Unreadable members (buffs = nil) and unusable ones (dead, offline, out of
-- range) are skipped.
function B.PickTarget(assignments, me, members, now, refreshSec, refreshLowest)
	local lowest, lowestKey, lowestLeft
	for _, m in ipairs(members) do
		local key = B.AssignedFor(assignments, me, m.class, m.guid)
		if key and m.usable and m.buffs then
			local left = B.Remaining(m, key, now)
			if left == nil then
				return m, key, nil, "missing"
			end
			if left ~= math.huge and (lowestLeft == nil or left < lowestLeft) then
				lowest, lowestKey, lowestLeft = m, key, left
			end
		end
	end
	if lowest and lowestLeft < refreshSec then
		return lowest, lowestKey, lowestLeft, "expiring"
	end
	if lowest and refreshLowest then
		return lowest, lowestKey, lowestLeft, "lowest"
	end
	return nil
end

-- Pre-pull report: who is missing your assigned Blessing, and whose copy
-- runs out within `withinSec`. Returns missing (names, group order) and
-- expiring ({ name, left }, soonest first). Unreadable members are skipped.
function B.Report(assignments, me, members, now, withinSec)
	local missing, expiring = {}, {}
	for _, m in ipairs(members) do
		local key = B.AssignedFor(assignments, me, m.class, m.guid)
		if key and m.buffs then
			local left = B.Remaining(m, key, now)
			if left == nil then
				missing[#missing + 1] = m.name
			elseif left ~= math.huge and left < withinSec then
				expiring[#expiring + 1] = { name = m.name, left = left }
			end
		end
	end
	table.sort(expiring, function(a, b)
		return a.left < b.left
	end)
	return missing, expiring
end

-- Whole-group coverage from every paladin's assignments (not just yours):
-- which Blessings each readable member should have but doesn't, and which
-- classes in the group no paladin gives anything to.
-- paladins: list of paladin ids (rows in `assignments`).
-- Returns gaps = { { name, class, missing = { keys... } }, ... } and
-- uncovered = { class = true }.
function B.Coverage(assignments, paladins, members, now)
	local gaps, uncovered = {}, {}
	for _, m in ipairs(members) do
		local expected, any = {}, false
		for _, p in ipairs(paladins) do
			local key = B.AssignedFor(assignments, p, m.class, m.guid)
			if key then
				expected[key] = true
				any = true
			end
		end
		if not any then
			uncovered[m.class] = true
		elseif m.buffs then
			local missing = {}
			for _, key in ipairs(B.ASSIGNABLE) do
				if expected[key] and B.Remaining(m, key, now) == nil then
					missing[#missing + 1] = key
				end
			end
			if #missing > 0 then
				gaps[#gaps + 1] = { name = m.name, class = m.class, missing = missing }
			end
		end
	end
	return gaps, uncovered
end

-- Members missing your assigned blessing or under refreshSec left
-- (readable ones only, including those out of range).
function B.CountNeeding(assignments, me, members, now, refreshSec)
	local n, names = 0, {}
	for _, m in ipairs(members) do
		local key = B.AssignedFor(assignments, me, m.class, m.guid)
		if key and m.buffs then
			local left = B.Remaining(m, key, now)
			if left == nil or left < refreshSec then
				n = n + 1
				names[#names + 1] = m.name
			end
		end
	end
	return n, names
end
