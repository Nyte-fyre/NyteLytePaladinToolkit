local _, PK = ...

-- Spell and aura registry, by name only. Spell IDs are resolved at runtime
-- from the player's spellbook (never hardcoded). verify = true marks names
-- reported for WoW Forever but not yet confirmed on the real client.
-- names: first entry is the preferred name, the rest are alternates to try.
-- spec: which talent tree knowing this spell hints at (for Auto detection).

local S = {}
PK.Spells = S

S.list = {
	-- Seals
	{ key = "SEAL_RIGHTEOUSNESS", names = { "Seal of Righteousness" }, category = "seal" },
	{ key = "SEAL_COMMAND", names = { "Seal of Command" }, category = "seal", spec = "ret" },
	{ key = "SEAL_JUSTICE", names = { "Seal of Justice" }, category = "seal" },
	{ key = "SEAL_LIGHT", names = { "Seal of Light" }, category = "seal" },
	{ key = "SEAL_WISDOM", names = { "Seal of Wisdom" }, category = "seal" },
	{ key = "SEAL_CRUSADER", names = { "Seal of the Crusader", "Seal of Crusader" }, category = "seal" },
	{ key = "SEAL_FURY", names = { "Seal of Fury" }, category = "seal", spec = "prot", verify = true },

	-- Blessings (Sanctuary is removed in Forever; kept only to confirm that)
	{ key = "BLESSING_MIGHT", names = { "Blessing of Might" }, category = "blessing" },
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
	{ key = "IRON_CREED", names = { "Iron Creed" }, category = "proc", spec = "prot", verify = true },

	-- Abilities
	{ key = "HOLY_STRIKE", names = { "Holy Strike" }, category = "ability", verify = true },
	{ key = "JUDGEMENT", names = { "Judgement" }, category = "ability" },
	{ key = "CONSECRATION", names = { "Consecration" }, category = "ability" },
	{ key = "HOLY_SHOCK", names = { "Holy Shock" }, category = "ability", spec = "holy" },
	{ key = "DIVINE_FAVOR", names = { "Divine Favor" }, category = "ability", spec = "holy" },
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
	{ key = "TEMPLARS_BULWARK", names = { "Templar's Bulwark" }, category = "talent", spec = "prot", verify = true },
	{ key = "LIGHTS_VIGIL", names = { "Light's Vigil" }, category = "talent", spec = "holy", verify = true },
	{ key = "INFUSION_OF_LIGHT", names = { "Infusion of Light" }, category = "talent", spec = "holy", verify = true },
	{ key = "SACRED_ARBITER", names = { "Sacred Arbiter" }, category = "talent", spec = "ret", verify = true },
	{ key = "SANCTIFIED_JUDGEMENT", names = { "Sanctified Judgement" }, category = "talent", spec = "ret", verify = true },
	{ key = "TWIST_OF_LIGHT", names = { "Twist of Light" }, category = "talent", spec = "ret", verify = true },
	{ key = "CRUSADE", names = { "Crusade" }, category = "talent", spec = "ret", verify = true },
	{ key = "CHAMPION_OF_THE_LIGHT", names = { "Champion of the Light" }, category = "talent", spec = "ret", verify = true },
	{ key = "BLESSED_LIFE", names = { "Blessed Life" }, category = "talent", spec = "prot", verify = true },
}

S.byKey = {}
for _, entry in ipairs(S.list) do
	S.byKey[entry.key] = entry
end

-- Builds a lowercase name -> spellbook entry index from Compat.ScanSpellbook().
function S.IndexSpellbook(book)
	local index = {}
	for _, item in ipairs(book) do
		if type(item.name) == "string" then
			local lname = item.name:lower()
			-- Prefer a learned spell over a "future" one of the same name.
			local prev = index[lname]
			if not prev or (prev.itemType == "FutureSpell" and item.itemType ~= "FutureSpell") then
				index[lname] = item
			end
		end
	end
	return index
end

-- Resolves a registry entry. Returns a result table:
-- { spellID, name, method = "spellbook" | "futureSpell" | "C_Spell" | nil, known }
function S.Resolve(entry, bookIndex)
	for _, name in ipairs(entry.names) do
		local item = bookIndex and bookIndex[name:lower()]
		if item then
			local future = item.itemType == "FutureSpell"
			return {
				spellID = item.spellID,
				name = item.name,
				method = future and "futureSpell" or "spellbook",
				known = not future,
			}
		end
	end
	for _, name in ipairs(entry.names) do
		local info = PK.Compat.GetSpellInfo(name)
		if info and info.spellID then
			return {
				spellID = info.spellID,
				name = info.name,
				method = "C_Spell",
				known = PK.Compat.IsSpellKnown(info.spellID),
			}
		end
	end
	return { method = nil, known = false }
end
