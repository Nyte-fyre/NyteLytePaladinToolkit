local _, PK = ...

-- Spell and aura registry. Spells are resolved at runtime from the player's
-- spellbook. verify = true marks names reported for WoW Forever but not yet
-- confirmed on the real client.
-- names: English names; the first is preferred, the rest are alternates.
-- ids: spell IDs confirmed on Forever (any rank). On a non-English client the
--   English names match nothing, so the game's own name for these IDs
--   (C_Spell.GetSpellName, in the client's language) is tried first.
-- spec: which talent tree knowing this spell hints at (for Auto detection).

local S = {}
PK.Spells = S

S.list = {
	-- Seals
	{ key = "SEAL_RIGHTEOUSNESS", names = { "Seal of Righteousness" }, category = "seal", ids = { 21084, 20287 } },
	{ key = "SEAL_COMMAND", names = { "Seal of Command" }, category = "seal", spec = "ret", ids = { 20375 } },
	{ key = "SEAL_JUSTICE", names = { "Seal of Justice" }, category = "seal" },
	{ key = "SEAL_LIGHT", names = { "Seal of Light" }, category = "seal" },
	{ key = "SEAL_WISDOM", names = { "Seal of Wisdom" }, category = "seal" },
	{ key = "SEAL_CRUSADER", names = { "Seal of the Crusader", "Seal of Crusader" }, category = "seal" },
	{ key = "SEAL_FURY", names = { "Seal of Fury" }, category = "seal", spec = "prot" },

	-- Blessings (Sanctuary is removed in Forever; kept only to confirm that)
	{ key = "BLESSING_MIGHT", names = { "Blessing of Might" }, category = "blessing", ids = { 19740 } },
	{ key = "BLESSING_WISDOM", names = { "Blessing of Wisdom" }, category = "blessing" },
	{ key = "BLESSING_KINGS", names = { "Blessing of Kings" }, category = "blessing", verify = true },
	{ key = "BLESSING_LIGHT", names = { "Blessing of Light" }, category = "blessing" },
	{ key = "BLESSING_SALVATION", names = { "Blessing of Salvation" }, category = "blessing" },
	{ key = "BLESSING_FREEDOM", names = { "Blessing of Freedom", "Hand of Freedom" }, category = "blessing" },
	{ key = "BLESSING_PROTECTION", names = { "Blessing of Protection", "Hand of Protection" }, category = "blessing" },
	{ key = "BLESSING_SACRIFICE", names = { "Blessing of Sacrifice", "Hand of Sacrifice" }, category = "blessing" },
	{ key = "BLESSING_SANCTUARY", names = { "Blessing of Sanctuary" }, category = "blessing", verify = true, removed = true },

	-- Greater Blessings: unknown whether Forever has them
	{ key = "GREATER_MIGHT", names = { "Greater Blessing of Might" }, category = "greaterBlessing", verify = true },
	{ key = "GREATER_WISDOM", names = { "Greater Blessing of Wisdom" }, category = "greaterBlessing", verify = true },
	{ key = "GREATER_KINGS", names = { "Greater Blessing of Kings" }, category = "greaterBlessing", verify = true },
	{ key = "GREATER_LIGHT", names = { "Greater Blessing of Light" }, category = "greaterBlessing", verify = true },
	{ key = "GREATER_SALVATION", names = { "Greater Blessing of Salvation" }, category = "greaterBlessing", verify = true },

	-- Auras
	{ key = "AURA_DEVOTION", names = { "Devotion Aura" }, category = "aura" },
	{ key = "AURA_RETRIBUTION", names = { "Retribution Aura" }, category = "aura" },
	{ key = "AURA_CONCENTRATION", names = { "Concentration Aura" }, category = "aura" },
	{ key = "AURA_FIRE", names = { "Fire Resistance Aura" }, category = "aura" },
	{ key = "AURA_FROST", names = { "Frost Resistance Aura" }, category = "aura" },
	{ key = "AURA_SHADOW", names = { "Shadow Resistance Aura" }, category = "aura" },
	{ key = "AURA_CRUSADER", names = { "Crusader Aura" }, category = "aura", verify = true },
	{ key = "AURA_SANCTITY", names = { "Sanctity Aura" }, category = "aura", spec = "ret", verify = true },

	-- Self buffs and procs
	{ key = "RIGHTEOUS_FURY", names = { "Righteous Fury" }, category = "selfBuff" },
	{ key = "TWIST_ECHO", names = { "Echo", "Twist of Light" }, category = "proc", spec = "ret", verify = true },
	-- Iron Creed is a 5-rank Protection talent; its buff name/duration are unverified.
	{ key = "IRON_CREED", names = { "Iron Creed" }, category = "proc", spec = "prot", verify = true },

	-- Abilities
	{ key = "HOLY_STRIKE", names = { "Holy Strike" }, category = "ability", verify = true },
	{ key = "JUDGEMENT", names = { "Judgement" }, category = "ability", ids = { 20271 } },
	{ key = "CONSECRATION", names = { "Consecration" }, category = "ability" },
	{ key = "HOLY_SHOCK", names = { "Holy Shock" }, category = "ability", spec = "holy", ids = { 1311606 } },
	{ key = "DIVINE_FAVOR", names = { "Divine Favor" }, category = "ability", spec = "holy", ids = { 20216 } },
	{ key = "LAY_ON_HANDS", names = { "Lay on Hands" }, category = "ability" },
	{ key = "DIVINE_SHIELD", names = { "Divine Shield" }, category = "ability" },
	{ key = "DIVINE_PROTECTION", names = { "Divine Protection" }, category = "ability" },
	{ key = "HAMMER_OF_JUSTICE", names = { "Hammer of Justice" }, category = "ability" },
	{ key = "HAMMER_OF_WRATH", names = { "Hammer of Wrath" }, category = "ability" },
	{ key = "EXORCISM", names = { "Exorcism" }, category = "ability" },
	{ key = "HOLY_WRATH", names = { "Holy Wrath" }, category = "ability" },
	{ key = "REPENTANCE", names = { "Repentance" }, category = "ability", spec = "ret" },
	{ key = "CLEANSE", names = { "Cleanse" }, category = "ability" },
	{ key = "PURIFY", names = { "Purify" }, category = "ability" },
	{ key = "DIVINE_INTERVENTION", names = { "Divine Intervention" }, category = "ability" },
	{ key = "FLASH_OF_LIGHT", names = { "Flash of Light" }, category = "ability" },
	{ key = "HOLY_LIGHT", names = { "Holy Light" }, category = "ability" },

	-- Talent-gated, presence unverified
	-- Talents confirmed in Forever's talent tree (level 10 probe, 2026-09-24).
	{ key = "TEMPLARS_BULWARK", names = { "Templar's Bulwark" }, category = "talent", spec = "prot", ids = { 1311015 } },
	{ key = "LIGHTS_VIGIL", names = { "Light's Vigil" }, category = "talent", spec = "holy", ids = { 1310911 } },
	{ key = "INFUSION_OF_LIGHT", names = { "Infusion of Light" }, category = "talent", spec = "holy", ids = { 426065 } },
	{ key = "SACRED_ARBITER", names = { "Sacred Arbiter" }, category = "talent", spec = "ret", ids = { 1311087 } },
	{ key = "SANCTIFIED_JUDGEMENT", names = { "Sanctified Judgement" }, category = "talent", spec = "ret", ids = { 1311074 } },
	{ key = "TWIST_OF_LIGHT", names = { "Twist of Light" }, category = "talent", spec = "ret", ids = { 1310735 } },
	{ key = "CRUSADE", names = { "Crusade" }, category = "talent", spec = "ret", ids = { 1311083 } },
	{ key = "CHAMPION_OF_THE_LIGHT", names = { "Champion of the Light" }, category = "talent", spec = "ret", ids = { 1311084 } },
	{ key = "HOLY_SHIELD", names = { "Holy Shield" }, category = "talent", spec = "prot", ids = { 20925 } },
	-- Holy talent (Forever launch): one ally at a time, 5 min, boosts your Holy Light on them.
	{ key = "OATH_OF_LIGHT", names = { "Oath of Light" }, category = "talent", spec = "holy", ids = { 1328548 } },
}

S.byKey = {}
for _, entry in ipairs(S.list) do
	S.byKey[entry.key] = entry
end

-- Builds a lowercase name -> spellbook entry index from Compat.ScanSpellbook().
-- Forever's spellbook lists every learned rank separately (Seal of
-- Righteousness 21084 and 20287 at level 11, lowest rank first), and casts
-- report the rank actually cast. So each entry keeps `ids`, the set of all
-- learned rank IDs, and the entry itself is the last (highest) learned rank.
function S.IndexSpellbook(book)
	local index = {}
	for _, item in ipairs(book) do
		if type(item.name) == "string" then
			local lname = item.name:lower()
			local learned = item.itemType ~= "FutureSpell"
			local prev = index[lname]
			local ids = prev and prev.ids or {}
			if learned and item.spellID then
				ids[item.spellID] = true
			end
			-- The first entry, or any later learned rank, becomes the entry.
			if not prev or learned then
				index[lname] = setmetatable({ ids = ids }, { __index = item })
			end
		end
	end
	return index
end

-- Names to look the entry up by: the client's own name for each known ID
-- (so German, French, ... clients match), then the English names.
function S.LookupNames(entry)
	local names, seen = {}, {}
	local function add(n)
		if type(n) == "string" and n ~= "" and not PK.Compat.IsSecret(n) and not seen[n:lower()] then
			seen[n:lower()] = true
			names[#names + 1] = n
		end
	end
	for _, id in ipairs(entry.ids or {}) do
		add(PK.Compat.GetSpellName(id))
	end
	for _, n in ipairs(entry.names) do
		add(n)
	end
	return names
end

-- Resolves a registry entry. Returns a result table:
-- { spellID, name, method = "spellbook" | "futureSpell" | "C_Spell" | nil, known }
function S.Resolve(entry, bookIndex)
	local lookup = S.LookupNames(entry)
	for _, name in ipairs(lookup) do
		local item = bookIndex and bookIndex[name:lower()]
		if item then
			local future = item.itemType == "FutureSpell"
			return {
				spellID = item.spellID,
				ids = item.ids,
				name = item.name,
				method = future and "futureSpell" or "spellbook",
				known = not future,
			}
		end
	end
	for _, name in ipairs(lookup) do
		local info = PK.Compat.GetSpellInfo(name)
		if info and info.spellID then
			return {
				spellID = info.spellID,
				ids = { [info.spellID] = true },
				name = info.name,
				method = "C_Spell",
				known = PK.Compat.IsSpellKnown(info.spellID),
			}
		end
	end
	return { method = nil, known = false }
end
