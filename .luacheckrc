std = "lua51"
max_line_length = 140
codes = true
exclude_files = { "tests/mocks.lua" }
ignore = {
	"212/self", -- unused self in methods
}

globals = {
	"PaladinKit", "PaladinKitDB",
	"SLASH_PALADINKIT1", "SLASH_PALADINKIT2", "SlashCmdList",
}

read_globals = {
	-- Lua extensions provided by WoW
	"date", "time", "debugstack", "geterrorhandler", "seterrorhandler", "tinsert", "wipe", "issecretvalue",
	"unpack",
	-- namespaces
	"C_AddOns", "C_ChatInfo", "C_ClassTalents", "C_Spell", "C_SpellBook", "C_Timer", "C_Traits", "C_UnitAuras",
	"Enum", "Settings",
	-- functions
	"CreateFrame", "GetBuildInfo", "GetLocale", "GetNumSpellTabs", "GetSpellBookItemName", "GetSpellTabInfo",
	"GetTime", "InCombatLockdown", "IsInGroup", "IsInRaid", "UnitClass", "UnitExists", "UnitLevel", "UnitName",
	"UnitRace",
	-- frames and fonts
	"ChatFontNormal", "UIParent", "UISpecialFrames",
}
