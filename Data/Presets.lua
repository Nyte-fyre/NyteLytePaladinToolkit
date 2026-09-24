local _, PK = ...

-- Per-spec defaults: which modules are on, default cooldown lists (by
-- Data/Spells.lua key), and default frame positions. Every value here is only
-- a default; the player can override all of it per spec in settings.

local Presets = {}
PK.Presets = Presets

-- Module order as shown in settings.
Presets.MODULES = { "BuffSentinel", "SealTracker", "CooldownHUD", "BlessingManager", "TankKit" }

Presets.MODULE_LABELS = {
	BuffSentinel = "Buff Sentinel (missing buffs)",
	SealTracker = "Seal Tracker",
	CooldownHUD = "Cooldown HUD",
	BlessingManager = "Blessing Manager",
	TankKit = "Tank Kit",
}

Presets.modules = {
	holy = { BuffSentinel = true, SealTracker = true, CooldownHUD = true, BlessingManager = true, TankKit = false },
	prot = { BuffSentinel = true, SealTracker = true, CooldownHUD = true, BlessingManager = true, TankKit = true },
	ret = { BuffSentinel = true, SealTracker = true, CooldownHUD = true, BlessingManager = true, TankKit = false },
}

Presets.cooldownLists = {
	holy = { "HOLY_SHOCK", "DIVINE_FAVOR", "LAY_ON_HANDS", "DIVINE_SHIELD", "BLESSING_PROTECTION",
		"BLESSING_FREEDOM", "CLEANSE", "PURIFY", "CONSECRATION", "HOLY_STRIKE", "LIGHTS_VIGIL" },
	prot = { "JUDGEMENT", "CONSECRATION", "HOLY_STRIKE", "HAMMER_OF_JUSTICE", "TEMPLARS_BULWARK",
		"LAY_ON_HANDS", "BLESSING_PROTECTION", "DIVINE_PROTECTION", "DIVINE_SHIELD" },
	ret = { "HOLY_STRIKE", "JUDGEMENT", "HAMMER_OF_WRATH", "EXORCISM", "CONSECRATION",
		"HAMMER_OF_JUSTICE", "REPENTANCE", "LAY_ON_HANDS" },
}

-- Default anchor positions (offsets from the screen center, UIParent units).
Presets.layout = {
	BuffSentinel = { point = "CENTER", x = 0, y = -120, scale = 1 },
	SealTracker = { point = "CENTER", x = 0, y = -150, scale = 1 },
	CooldownHUD = { point = "CENTER", x = 0, y = -190, scale = 1 },
	BlessingManager = { point = "CENTER", x = 300, y = 0, scale = 1 },
	TankKit = { point = "CENTER", x = 0, y = 120, scale = 1 },
}

-- Per-spec tweaks on top of Presets.layout.
Presets.layoutOverrides = {
	holy = { SealTracker = { scale = 0.8 } }, -- Seal matters less for Holy: smaller
}

-- Full default layout for one spec.
function Presets.LayoutFor(spec)
	local out = {}
	for module, l in pairs(Presets.layout) do
		local copy = {}
		for k, v in pairs(l) do
			copy[k] = v
		end
		local o = Presets.layoutOverrides[spec] and Presets.layoutOverrides[spec][module]
		if o then
			for k, v in pairs(o) do
				copy[k] = v
			end
		end
		out[module] = copy
	end
	return out
end

-- Module options (per profile, shared by all specs).
Presets.moduleSettings = {
	BuffSentinel = {
		showAll = false, -- also show buffs that are fine, not just problems
		checkSeal = true,
		checkAura = true,
		checkBlessing = true, -- warn if you have no Blessing at all
		rfSpecs = { holy = false, prot = true, ret = false }, -- warn about Righteous Fury in these specs
		iconSize = 32,
	},
	SealTracker = { showBar = true, iconSize = 30 },
	CooldownHUD = {
		iconSize = 36,
		spacing = 4,
		direction = "RIGHT", -- RIGHT | LEFT | DOWN | UP
		perRow = 12,
		showUnknown = false, -- show spells you haven't learned (greyed out)
		dimUnusable = true,
	},
}
