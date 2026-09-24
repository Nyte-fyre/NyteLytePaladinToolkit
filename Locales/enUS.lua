local _, PK = ...

-- Localization scaffold. English is the source language: PK.L["Some text"]
-- returns "Some text" unless a translation for the client's locale exists.
-- To add a language, create Locales/<locale>.lua (e.g. deDE.lua), list it in
-- the TOC after this file, and fill in:
--
--   if GetLocale() ~= "deDE" then return end
--   local L = select(2, ...).L
--   L["Seal Tracker"] = "Siegel-Anzeige"
--
-- Spell and aura names never need translating: they are resolved from the
-- player's own spellbook at runtime (Data/Spells.lua only lists English
-- names as a fallback for lookups).

PK.L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
