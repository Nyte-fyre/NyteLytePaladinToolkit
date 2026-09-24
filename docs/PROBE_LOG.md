# Probe log

## Summary: verified API surface (beta build 1.60.1.69977, as of 2026-09-24)

| What | Out of combat | In combat | Used by |
|---|---|---|---|
| Player auras (`C_UnitAuras.GetAuraDataByIndex`) | readable | **refused** (error) | AuraService (frozen snapshot) |
| `C_Secrets.ShouldAurasBeSecret()` | false | true | AuraService (skips refused reads) |
| Own `UNIT_SPELLCAST_SUCCEEDED` spell ID | readable | **readable** | AuraService predictions |
| `UNIT_AURA` updateInfo | readable | secret | (only used as a "rescan" trigger) |
| Cooldown `isActive`, `isEnabled`, `isOnGCD` | readable | **readable** | IconMixin:RefreshCooldown |
| Cooldown startTime/duration/modRate | readable | secret | display only (duration objects) |
| `C_Spell.GetSpellCooldownDuration` + `Cooldown:SetCooldownFromDurationObject` | works | works | cooldown swipes |
| `C_Spell.IsSpellUsable` | readable | readable | cooldown dimming |
| Stance bar (active Paladin aura) | readable | readable | AuraService:GetPaladinAura |
| `UnitHealth`/`UnitPower`/`UnitGetTotalAbsorbs("player")` | **secret** | secret | not used |
| `UnitHealthMax`/`UnitPowerMax("player")` | readable | readable | not used |
| Addon messages | allowed | **restricted** (`AreOutgoingAddonChatMessagesRestricted`) | Comm queue |
| Settings API (canvas category) | works | works | UI/Settings.lua |
| Party members' auras | **unverified** | assumed secret | Roster (unreadable = unknown) |
| Talent trees (`C_Traits`) | **unverified** (needs level 10+) | - | SpecProfile (stubbed) |

## Launch-day checklist (Nov 4 2026)

1. Install, log in, `/console scriptErrors 1`, `/reload`. Any errors?
2. `GetBuildInfo()` interface is still 16001? If not, update `## Interface:`.
3. Addon folder path on the launch client: update README and `tools/install.ps1`.
4. `/ptk probe` then `/reload`, and compare against the summary table above
   (`python tests/read_sv.py probe.api probe.secrecy probe.registry.unresolved`).
5. `/ptk probe combat` in a real fight, then `/reload`, and check the table's
   "In combat" column.
6. Talents: C_Traits tree dump -> implement `Compat.GetTalentPointsByTree()`.
7. Verify the guessed names and durations: Seal of Fury, Twist of Light Echo
   ("Echo", 10s), Iron Creed (6s), Templar's Bulwark, Light's Vigil,
   Righteous Fury duration. Fix `Data/Spells.lua` and `DEFAULT_DURATION` in
   AuraService.
8. In a group: party aura readability (`probe.group`), and a Blessing sync
   test between two paladins running the addon.
9. Restart the client fully and check `probe.savedVariables.existedAtLoad`
   (the reported SavedVariables bug).


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

## Combat probe #2 (2026-09-24, level 8, random mobs, probe v2)

Cast order in the fight: Judgement, Seal of Righteousness, Holy Strike,
Judgement, Holy Strike, Judgement, Hammer of Justice, Seal of the Crusader,
Seal of Righteousness, Holy Strike, Blessing of Might, Judgement. Zero Lua errors.

- **`UNIT_SPELLCAST_SUCCEEDED` for the player is fully readable in combat**:
  unit, castGUID and **spellID**. Confirmed IDs: Judgement 20271, Seal of
  Righteousness 21084, **Seal of the Crusader 21082**, Holy Strike 679,
  **Hammer of Justice 853**, Blessing of Might 19740. Seal prediction in
  AuraService works on this.
- **`UNIT_AURA` in combat:** `updateInfo` fields (isFullUpdate, addedAuras,
  removed/updatedAuraInstanceIDs) are all secret.
- **Every player aura read in combat throws**, including
  `GetAuraDataByIndex`, `GetBuffDataByIndex` and `GetUnitAuraInstanceIDs`:
  "Auras cannot be accessed when secret while tainted by
  'NyteLytePaladinToolkit'". `GetAuraDataBySpellName` and
  `GetUnitAuraBySpellID` return nil. `C_Secrets.ShouldAurasBeSecret()` is
  true in combat, so AuraService checks it and skips the call.
- **Cooldown info in combat** has readable `isActive`, `isEnabled` and
  **`isOnGCD`** (the last one is absent for off-GCD spells like
  Judgement). startTime, duration, modRate, activeCategory and
  timeUntilEndOfStartRecovery are secret. Holy Strike right after casting:
  isActive=true, isOnGCD=false (a real cooldown). Other spells:
  isActive=true, isOnGCD=true (only the GCD). CooldownHUD uses
  `isActive and not isOnGCD`.
- **Duration object methods** (found by name; the metatable is protected):
  GetRemainingDuration, GetElapsedDuration, GetTotalDuration, GetStartTime,
  GetEndTime, GetModRate, GetRemainingPercent, GetElapsedPercent,
  EvaluateRemainingPercent, EvaluateElapsedPercent, EvaluateRemainingDuration,
  IsZero, IsActive, HasSecretValues. In combat every getter returns a
  secret, so the object is for display only (`SetCooldownFromDurationObject`).
- `C_Spell.IsSpellUsable` stays readable in combat.
- `C_Secrets` in combat: ShouldAurasBeSecret, ShouldCooldownsBeSecret and
  ShouldUnitPowerBeSecret are true. ShouldUnitHealthMaxBeSecret and
  ShouldUnitPowerMaxBeSecret are false. Every known spell has
  GetSpellAuraSecrecy / GetSpellCooldownSecrecy = 2 (Enum.SecrecyLevel
  ContextuallySecret: 0 Never, 1 Always, 2 Contextually).
- **Addon messages:** `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()`
  is **true in combat**. The BlessingManager sync must check it
  (`Compat.CanSendAddonMessages`). `C_RestrictedActions.IsAddOnRestrictionActive(type)`
  takes an `Enum.AddOnRestrictionType` (Combat 0, Encounter 1,
  ChallengeMode 2, PvPMatch 3, Map 4, Chat 5). The probe now asks for each.
- The stance bar (active Paladin aura) stays readable in combat (Devotion 465).

Still pending: static `/ptk probe` at level 10+ with a talent point spent,
covering spellbook flyouts (Blessings/Auras) and the C_Traits talent trees.
