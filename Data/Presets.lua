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

-- Default anchor positions (relative to UIParent CENTER), same for every spec.
Presets.layout = {
	BuffSentinel = { point = "CENTER", x = 0, y = -120 },
	SealTracker = { point = "CENTER", x = 0, y = -150 },
	CooldownHUD = { point = "CENTER", x = 0, y = -190 },
	BlessingManager = { point = "CENTER", x = 300, y = 0 },
	TankKit = { point = "CENTER", x = 0, y = 120 },
}
