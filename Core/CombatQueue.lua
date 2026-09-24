local _, PK = ...

-- Runs work that must not happen in combat (secure frame attributes, addon
-- messages) as soon as combat ends. Work is keyed, so queuing the same key
-- twice keeps only the latest function.

local CombatQueue = {}
PK.CombatQueue = CombatQueue

local queue, order = {}, {}

-- Runs fn now if out of combat, otherwise after combat. Returns true if it ran now.
function CombatQueue:Run(key, fn)
	if not PK.Compat.InCombat() then
		PK.SafeCall(fn)
		return true
	end
	if not queue[key] then
		order[#order + 1] = key
	end
	queue[key] = fn
	return false
end

function CombatQueue:Pending()
	return #order
end

PK:RegisterEvent("PLAYER_REGEN_ENABLED", CombatQueue, function()
	local keys = order
	local fns = queue
	order, queue = {}, {}
	for _, key in ipairs(keys) do
		PK.SafeCall(fns[key])
	end
end)
