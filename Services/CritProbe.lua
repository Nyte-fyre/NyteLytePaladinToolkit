local _, PK = ...

-- Temporary probe (2026-11-26): can the addon see your critical hits in
-- combat? Vengeance (Ret) stacks on crits, and Forever blocks aura reads in
-- combat, so counting crits is the only way to follow it. This logs what
-- UNIT_COMBAT (the floating combat text event: "target was hit, CRITICAL,
-- 412") hands over, to NyteLytePaladinToolkitDB.critProbe. Not the combat log.

local Compat = PK.Compat
local Describe = Compat.Describe
local P = {}
local seen = {}
local LOG_MAX = 60

local function log(row)
	local db = PK.db
	if not db then
		return
	end
	db.critProbe = db.critProbe or {}
	row.t = time()
	row.inCombat = Compat.InCombat() or nil
	table.insert(db.critProbe, row)
	while #db.critProbe > LOG_MAX do
		table.remove(db.critProbe, 1)
	end
end

PK:RegisterEvent("UNIT_COMBAT", P, function(_, _, unit, action, descriptor, amount, school)
	local key = Describe(unit) .. ":" .. Describe(action) .. ":" .. Describe(descriptor)
	seen[key] = (seen[key] or 0) + 1
	-- Each distinct shape a few times, so the log shows variety, not spam.
	if seen[key] <= 3 then
		local isTarget
		if not Compat.IsSecret(unit) and type(unit) == "string" then
			local ok, same = pcall(UnitIsUnit, unit, "target")
			isTarget = ok and not Compat.IsSecret(same) and same or nil
		end
		log({
			unit = Describe(unit), action = Describe(action), descriptor = Describe(descriptor),
			amount = Describe(amount), school = Describe(school), isTarget = isTarget,
		})
	end
end)

-- After each fight: how many of each kind came through.
PK:RegisterEvent("PLAYER_REGEN_ENABLED", P, function()
	local counts = {}
	for k, n in pairs(seen) do
		counts[#counts + 1] = k .. "=" .. n
	end
	table.sort(counts)
	log({ summary = table.concat(counts, ", ") })
	seen = {}
end)
