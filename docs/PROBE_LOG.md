# Probe log

What `/ptk probe` has confirmed on real clients. Anything not listed here is
still unverified. Re-run the probe on launch day (Nov 4 2026) and record the
differences.

## Already known from ReagentRoute's `/rrdiag` (Forever beta, build 1.60.1.69977, 2026-09-23)

- Addons load. `GetBuildInfo()` interface = **16001**. `WOW_PROJECT_ID` = **1** (Mainline).
- With plain, `_Vanilla`, `_TBC` and `_Mainline` TOCs present, the client
  loaded `_Mainline`. This addon ships a single plain `NyteLytePaladinToolkit.toc`.
- Global `GetItemInfo` is gone and `C_Item.GetItemInfo` works. Only
  `C_Container` exists for bags.
- `BasicFrameTemplateWithInset`, `BackdropTemplate`, `UIPanelScrollFrameTemplate`
  and `UIPanelButtonTemplate` all create fine.
- SavedVariables were written to disk and read back on that machine.
- Addon path: `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`.

## Paladin Toolkit probe #1 (2026-09-24, build 1.60.1.69977, Undead Paladin, level 7)

Zero Lua errors. Probe and combat capture both saved.

### Client
- Interface 16001, `WOW_PROJECT_ID` 1, locale enUS. It is a full retail
  client underneath: `C_Housing`, `C_DelvesUI` and friends are all present.
- `issecretvalue`, `issecrettable`, `canaccessvalue`, `canaccesstable`,
  `scrubsecretvalues`, `C_Secrets`, `C_CurveUtil`, `C_DurationUtil` and
  `C_RestrictedActions` all exist.
- **`C_SwingTimer` exists** (not investigated yet).
- Legacy globals are all gone except `IsSpellKnown`.
- The Settings API is present: `Settings.RegisterCanvasLayoutCategory`,
  `RegisterVerticalLayoutCategory`, `RegisterAddOnCategory` and
  `OpenToCategory`. `InterfaceOptions_AddCategory` is gone.
- These templates all create: BasicFrameTemplateWithInset, BackdropTemplate,
  SettingsListTemplate, UIPanelScrollFrame/Button, SecureActionButtonTemplate,
  CooldownFrameTemplate, UICheckButtonTemplate, OptionsSliderTemplate,
  MinimalSliderTemplate, UIDropDownMenuTemplate, WowStyle1DropdownTemplate.
- Methods present: `Cooldown:SetCooldownFromDurationObject`,
  `Cooldown:SetCooldownDuration`, `Cooldown:SetUseAuraDisplayTime`,
  `StatusBar:SetTimerDuration`.
- Every event we'll need registers except `LEARNED_SPELL_IN_TAB`; use
  `LEARNED_SPELL_IN_SKILL_LINE`. Confirmed: `SPELLS_CHANGED`, `UNIT_AURA`,
  `SPELL_UPDATE_COOLDOWN`, `PLAYER_TALENT_UPDATE`, `CHARACTER_POINTS_CHANGED`,
  `ACTIVE_TALENT_GROUP_CHANGED`, `TRAIT_CONFIG_UPDATED`, `READY_CHECK`,
  `ENCOUNTER_START/END`, `GROUP_ROSTER_UPDATE`, `UPDATE_SHAPESHIFT_FORM(S)`,
  `UNIT_ABSORB_AMOUNT_CHANGED`, `ADDON_RESTRICTION_STATE_CHANGED`.

### Secret values (the big one)
- **`UnitHealth("player")`, `UnitPower("player")` and
  `UnitGetTotalAbsorbs("player")` are secret even out of combat.**
  `UnitHealthMax` and `UnitPowerMax` for the player are readable. Target
  health is secret. **Seal of Fury's absorb amount therefore can't be read,
  so show it only through display-only widgets or drop it.**
- **Player auras out of combat are fully readable**: name, spellId,
  duration, expirationTime, sourceUnit and the rest.
- **In combat, `GetAuraDataByIndex("player", ...)` and
  `GetPlayerAuraBySpellID` returned nothing.** No errors and no
  secret-marked values, just empty results, even for the Seal of
  Righteousness cast during the fight. Probe v2 finds out why and tests
  other routes.
- **Cooldowns in combat:** `startTime`, `duration` and `modRate` are secret,
  while **`isActive` and `isEnabled` stay readable**. `C_Spell.IsSpellUsable`
  stays readable. `GetSpellCooldownDuration` returns a userdata duration
  object with a protected metatable (`getmetatable` returns `false`).
- Out of combat, cooldown info is plain numbers.

### Spells
- The spellbook is retail-style. Skill lines are **Holy / Protection /
  Retribution**, plus General (racials and passives).
- **Blessings and Auras live in spellbook flyouts**: "Blessings" (flyout
  264) and "Auras" (flyout 270). Probe #1 didn't open flyouts; probe v2 does.
- Confirmed at level 7: Seal of Righteousness 21084, Holy Light 635/639,
  Blessing of Might 19740, Devotion Aura 465, Judgement 20271, Divine
  Protection 498. **Holy Strike is 679** (spell name confirmed, and it's in
  the Retribution skill line).
- **Blessings last 3600s (60 min), confirmed.** Seal of Righteousness lasts 30s.
- **Paladin Auras are shapeshift forms**: `GetShapeshiftFormInfo(1)` gave
  spellID 465 (Devotion Aura), active. This gives a second way to read the
  active aura, which may work in combat.
- Judgement is "not usable" with no Seal active, as expected.

### Spec / talents
- Legacy talent functions are gone. `C_SpecializationInfo.GetSpecialization()`
  returns 1 and `GetNumSpecializationsForClassID(2)` returns 1, so the retail
  spec API only knows one "spec" and can't be used for detection.
- `C_ClassTalents.GetActiveConfigID()` returns a config ("Paladin", type 4)
  with treeIDs. **Talent trees go through `C_Traits`.** Probe v2 dumps
  them. The character needs level 10+ and at least one talent point spent to
  test detection.

### Addon messages
- `RegisterAddonMessagePrefix` returned 0 (success). A WHISPER to self
  looped back, with sender = character name. Group channels are untested.

### SavedVariables
- On a fresh install `existedAtLoad` was false (correct). After `/reload`,
  `loads` went to 2, so saved variables **did** load on reload. Still
  untested: a full client restart (the reported bug).
