std = "lua51"
max_line_length = 140
codes = true
exclude_files = { "tests/mocks.lua" }
ignore = {
	"212/self", -- unused self in methods
}

globals = {
	"NyteLytePaladinToolkit", "NyteLytePaladinToolkitDB", "NyteLytePaladinToolkitCharDB",
	"SLASH_NYTELYTEPALADINTOOLKIT1", "SLASH_NYTELYTEPALADINTOOLKIT2", "SlashCmdList",
	"BINDING_HEADER_NYTELYTEPALADINTOOLKIT", "BINDING_NAME_NLPT_CYCLE_SPEC", "BINDING_NAME_NLPT_TOGGLE_LOCK",
	"StaticPopupDialogs",
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
	"UnitRace", "GetRealmName", "UnitHealth", "StaticPopup_Show", "GetFlyoutInfo", "GetFlyoutSlotInfo",
	-- frames and fonts
	"ChatFontNormal", "UIParent", "UISpecialFrames",
	"C_Secrets", "C_ClassTalents",
}
