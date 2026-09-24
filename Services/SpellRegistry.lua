local _, PK = ...

-- Resolves every Data/Spells.lua entry to the player's actual spell (ID,
-- name, icon, known) from the spellbook, and keeps it current as spells are
-- learned. Modules look spells up here by key instead of calling APIs.
-- Fires PK_SPELLS_UPDATED after each refresh.

local Compat = PK.Compat
local Spells = PK.Spells
local R = { byKey = {} }
PK.SpellRegistry = R

-- Rebuilds the cache. Returns the number of known registry spells.
function R:Refresh()
	local book = Compat.ScanSpellbook()
	local index = Spells.IndexSpellbook(book)
	local known = 0
	local byKey = {}
	for _, entry in ipairs(Spells.list) do
		local r = Spells.Resolve(entry, index)
		r.key = entry.key
		r.category = entry.category
		r.spec = entry.spec
		if r.spellID then
			r.icon = Compat.GetSpellTexture(r.spellID)
		end
		if r.known then
			known = known + 1
		end
		byKey[entry.key] = r
	end
	self.byKey = byKey
	PK:Debug("SpellRegistry: %d known of %d", known, #Spells.list)
	PK:Fire("PK_SPELLS_UPDATED")
	return known
end

-- { spellID, name, icon, known, method, category, spec } or nil.
function R:Get(key)
	return self.byKey[key]
end

function R:IsKnown(key)
	local r = self.byKey[key]
	return r ~= nil and r.known == true
end

-- Number of known spells hinting at each tree: { holy = n, prot = n, ret = n }.
function R:CountKnownBySpec()
	local counts = { holy = 0, prot = 0, ret = 0 }
	for _, r in pairs(self.byKey) do
		if r.known and r.spec and counts[r.spec] then
			counts[r.spec] = counts[r.spec] + 1
		end
	end
	return counts
end

local function queueRefresh()
	PK:Debounce("SpellRegistry", 0.3, function()
		R:Refresh()
	end)
end

PK:RegisterEvent("SPELLS_CHANGED", R, queueRefresh)
PK:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", R, queueRefresh)
