# PaladinKit — Handoff for Claude Code

Working name: **PaladinKit** (folder `PaladinKit`, slash commands `/pk` and `/paladinkit`). Rename later with find/replace.

Save this file as `CLAUDE.md` in the repo root so every session starts with it.

## 0. Kickoff prompt (paste as the first message)

> Read CLAUDE.md fully. Build PaladinKit for WoW: Forever, milestone by milestone (section 13). Start with M0 (scaffold + diagnostics) and stop for my in-game test results before M1. Ask me at most one question at a time, and only if a probe result can't answer it. Prefer complete files over partial snippets.

---

## 1. Goal

One all-in-one addon for **Paladins in World of Warcraft: Forever** (Classic+, launches Nov 4 2026; beta live Sept 17 – Oct 21 2026, level cap 20 in beta). It replaces the owner's old WeakAuras setups and PallyPower with a single addon.

It has a **spec choice node** (Holy / Protection / Retribution / Auto). The active spec tailors which modules and presets are on. Every module is independently toggleable for every spec. Holy is the first spec to get right; Prot and Ret must exist at v1.

## 2. Owner and working style

- Owner is a Paladin player with some WeakAuras experience, **not a Lua developer**.
- Prefers **complete, copy-paste-ready files and direct edits** over walkthroughs. Keep explanations short. Give test instructions as exact in-game commands to paste.
- Claude Code **cannot run WoW**. The test loop is: you write code, the owner runs `/reload`, and pastes back Lua errors and `/pk probe` output. Design everything around that loop (section 9).

## 3. Target platform (facts, with confidence)

Sourced from public reporting during the beta; treat as **reported, verify with the probe**.

- Forever uses the **modern (retail/Midnight-style) addon API and UI architecture**, not the old Classic API. Blizzard stated it shares "the vast majority of APIs available in 12.1.5". Classic-era addons do not load unchanged.
- Client interface number: **16001** (`## Interface: 16001`). Build seen: 1.60.1.x.
- Beta addon path reported by addon authors: `World of Warcraft/_classic_beta_/Interface/AddOns/`. **Launch path unknown** — make the install scripts configurable.
- **Midnight-style combat restrictions ("secret values") are active.** In combat, many values (enemy/party health, damage, threat, other players' spell IDs, most non-whitelisted aura data) are secret: they can be passed to display APIs but cannot be compared, used in arithmetic, or branched on. A beta test showed `UnitHealth` returning a "number" that cannot be added to.
- Blizzard ships a built-in damage meter and a Cooldown Manager; a swing timer is "maybe coming soon". Boss encounters are designed to be playable without addons.
- Reported as **removed globals** in beta build 69913: `GetItemInfo`, `GetSpellInfo`, `GetSpellBookItemName`, `GetNumTalentTabs`, `GetTalentInfo`, and related. Use `C_Spell`, `C_Item`, `C_SpellBook` etc. Put every such call behind `Core/Compat.lua` so there is one place to fix.
- Reported beta bug: **SavedVariables are written but not loaded on fresh client start**, so settings may reset. Do not treat that as an addon bug; provide profile export/import (section 11).
- Blizzard addon policy: addons must be **free with open, visible source**. License MIT, public repo. Donation links are fine.
- Blizzard says addons that **automate communicating or marking** are restricted. No auto-chat, auto-whisper, or auto-marking, ever.

### Paladin changes in Forever that matter for this addon (reported)

- All Blessings last **60 minutes**. **Blessing of Kings is trained** (from level 20), no longer a talent. **Blessing of Sanctuary is removed.**
- **Judgement no longer consumes your active Seal.**
- New class spells and effects: **Holy Strike** (learned at level 6, melee, instant, ~12 sec cooldown), **Seal of Fury** (Protection; melee attacks add Holy damage and feed an absorb shield; Judgement while in Seal of Fury acts as a taunt).
- **Twist of Light** (Ret): replacing Seal of Command/Righteousness/Fury/Justice with another Seal grants an **"Echo"** buff; your next melee attack applies the replaced Seal once.
- Righteous Fury: +90% Holy threat (Improved RF removed). **Iron Creed** (Prot): with RF active, Holy Strike grants ~10% damage reduction for 6 sec. **Templar's Bulwark** (Prot): big emergency defensive.
- Talent names to verify in the client: Light's Vigil, Infusion of Light (Holy); Sanctified Judgement, Sacred Arbiter, Twist of Light, Crusade, Champion of the Light (Ret).
- Raids are 10 and 20 player, so multiple paladins per raid is common and blessing coordination matters.

## 4. Hard rules (do not break)

1. **Secret-value safety.** Never compare, do arithmetic on, concatenate, or use as a table key any value from a restricted API without first checking `issecretvalue(v)` (if the global exists; guard with `Compat`). Wrap unverified API reads in `pcall`. When data is secret, **degrade silently** (hide the element or show a static state); never throw Lua errors.
2. **Prefer display-only paths in combat.** For cooldowns use the duration-object APIs (e.g. `C_Spell.GetSpellCooldownDuration` / cooldown APIs returning non-secret `isActive`, and `Cooldown:SetCooldownFromDurationObject`) instead of reading start/duration numbers. Verify exact names against warcraft.wiki.gg "Patch 12.0.1/API changes", "12.0.5", and "12.1.0" pages and against the probe. Use the `ignoreGCD` option where the API offers it so the GCD swipe doesn't clutter the icons.
3. **No forbidden features:** no combat-log (CLEU) parsing, no threat meters, no party/raid health-based alerts, no enemy cast or debuff timers that rely on secret data, no rotation advisor/priority glows, no tracking other players' cooldowns from events, no auto-messaging/marking.
4. **Secure frames:** never change secure attributes in combat. Guard with `InCombatLockdown()` and queue changes for `PLAYER_REGEN_ENABLED`.
5. **No external libraries in v1** (no Ace3/LibStub). Small dependency-free core. Optional LibSharedMedia may come later.
6. **Clean-room implementation.** Do not copy code from PallyPower, WeakAuras, or other addons. Implement from the behavior described here.
7. **Verify, don't assume.** Every API name and every spell/aura name is unverified until the probe confirms it on the real client. Spells are resolved **by name at runtime**; do not hardcode numeric spell IDs.

## 5. Repository layout

```
PaladinKit/
  PaladinKit.toc
  Bindings.xml
  Core/
    Init.lua          -- namespace, module registry, event bus, logging
    Compat.lua        -- ALL wrappers around version-sensitive APIs
    Secrets.lua       -- IsSecret(), SafeNumber(), safe aura/cooldown readers
    Config.lua        -- SavedVariables, profiles, defaults, migrate, export/import
    SpecProfile.lua   -- spec choice node, detection, per-spec module matrix
  Data/
    Spells.lua        -- name registry by category (section 8)
    Presets.lua       -- per-spec default cooldown lists and module toggles
  Modules/
    Diagnostics.lua   -- /pk probe
    BuffSentinel.lua
    SealTracker.lua
    CooldownHUD.lua
    BlessingManager.lua
    TankKit.lua
  UI/
    Frames.lua        -- icon/bar widgets, frame pool, lock/unlock, drag
    Settings.lua      -- config panel
    BlessingGrid.lua  -- assignment grid window
  Locales/enUS.lua
  tools/
    install.ps1  install.sh        -- copy or symlink into AddOns dir (env WOW_ADDONS_DIR)
  tests/                            -- busted specs for pure-Lua logic
  .luacheckrc  .pkgmeta  README.md  CHANGELOG.md  LICENSE (MIT)
```

TOC essentials: `## Interface: 16001`, `## Title: PaladinKit`, `## Notes`, `## Version`, `## SavedVariables: PaladinKitDB`, `## IconTexture` (optional), load order Core → Data → UI → Modules → Locales as needed. Add `## Category`/other fields only if the client accepts them.

## 6. Spec choice node (core feature)

### Modes
`auto | holy | prot | ret`. The **effective spec** drives presets and default module toggles. Users can override any module toggle per spec.

### Detection (best effort, manual override always wins)
Forever keeps Classic-style three talent trees (Holy / Protection / Retribution), so there is no retail specialization API. `SpecProfile.Detect()` tries strategies in order and returns `{spec, confidence, method}`:

1. Manual mode setting (if not `auto`).
2. Whatever talent-tree/point-count API the probe finds on this client (candidates: `C_Talent`, `C_ClassTalents`, `C_SpecializationInfo`, legacy talent functions if present). Pick the tree with the most points spent.
3. Heuristic by known spells via `IsPlayerSpell`/`C_SpellBook` (e.g. Holy Shock known ⇒ Holy tree invested; Seal of Fury / Templar's Bulwark ⇒ Prot; Twist of Light / Sacred Arbiter ⇒ Ret). Verify which of these are talents in the beta.
4. Unknown ⇒ fall back to `holy` and show "Auto could not detect — pick a spec" in settings.

Re-run on `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, and the talent-change events the probe finds (e.g. `CHARACTER_POINTS_CHANGED`, `PLAYER_TALENT_UPDATE`, `ACTIVE_TALENT_GROUP_CHANGED`). Fire an internal `PK_SPEC_CHANGED` event; modules re-layout on it.

### Fast switching
- `/pk holy`, `/pk prot`, `/pk ret`, `/pk auto`.
- Dropdown at the top of the settings panel and an optional keybind that cycles modes.
- Switching is instant and in-place (no `/reload`).

### Default module matrix (all overridable)

| Module | Holy | Prot | Ret |
|---|---|---|---|
| BuffSentinel | on | on (RF required) | on |
| SealTracker | on (low prominence) | on (Seal of Fury) | on (+ Twist Echo) |
| CooldownHUD | on (Holy list) | on (Prot list) | on (Ret list) |
| BlessingManager | on | on | on |
| TankKit | off | on | off |

## 7. Modules

Each module: `PK:RegisterModule(name, {OnEnable, OnDisable, OnSpecChanged, defaults})`. Modules never touch each other directly; they communicate through the internal event bus. Every module must survive being disabled and re-enabled without `/reload`.

### 7.1 BuffSentinel — "what am I missing?"
- Checks **self**: Seal active, Aura active, Righteous Fury (Prot: required, red warning; other specs: off by default), your Blessing(s) on yourself if applicable.
- Visual: icon row; a missing buff shows as a desaturated icon with a red border/glow; expiring soon (configurable threshold) pulses. Optional text label and optional sound (built-in `SOUNDKIT` only in v1).
- **Group scan (out of combat only):** for each group member in range/visible, check whether they have the Blessings this paladin is assigned to give (from BlessingManager assignments). Show a compact "missing: 3" indicator and list on hover. Refresh on `GROUP_ROSTER_UPDATE` and throttled `UNIT_AURA`.
- In combat: read only what the probe proves non-secret for `player`; otherwise hide/freeze the indicator (never error).
- Pre-pull check: `/pk check` prints or flashes a summary; also triggers on ready check if that event is available.

### 7.2 SealTracker
- Bar/icon for the active Seal with remaining time. Do not hardcode durations — read from aura data when non-secret; otherwise use a display-only path.
- **Ret:** Twist of Light **Echo** indicator (buff present/absent + timer if readable). Do **not** suggest when to twist; only show state.
- **Prot:** Seal of Fury state; optionally the Seal of Fury absorb amount **only if** `UnitGetTotalAbsorbs("player")` (or the modern equivalent) is non-secret per the probe.
- Because Judgement no longer consumes Seals, do not model "Seal consumed by Judgement".

### 7.3 CooldownHUD — replaces the WeakAuras cooldown rows
- Data-driven row(s) of icons for **your own** spells. Default lists per spec in `Data/Presets.lua` (names only; users can add/remove by spell name in settings).
  - **Holy:** Holy Shock, Divine Favor, Lay on Hands, Divine Shield, Blessing of Protection, Blessing of Freedom, Cleanse/Purify, Consecration, Holy Strike, plus any Holy talent abilities the probe finds (e.g. Light's Vigil — verify).
  - **Prot:** Judgement, Consecration, Holy Strike, Hammer of Justice, Templar's Bulwark (verify), Lay on Hands, Blessing of Protection, Divine Protection/Shield.
  - **Ret:** Holy Strike, Judgement, Hammer of Wrath, Exorcism, Consecration, Hammer of Justice, Repentance, Lay on Hands.
- Icon states: ready (full color), on cooldown (swipe + optional time text), unusable/not-learned (hidden by default; option to show desaturated).
- Use duration objects and the cooldown `isActive` flag in combat (rule 4.2); fall back to numeric start/duration only when non-secret.
- Layout: horizontal/vertical, grow direction, icon size, spacing, wrap; per-spec positions; draggable when unlocked.

### 7.4 BlessingManager — PallyPower-style coordination
Purpose: assign Blessings/Auras among the paladins in a group/raid, sync assignments, and give one-click buff buttons.

**Roster and assignments**
- Grid window (`UI/BlessingGrid.lua`): rows = paladins in group, columns = the 8 other classes (plus optional "Pets"). Cell = which Blessing that paladin gives that class. One extra column = the paladin's Aura.
- Blessing list is **data-driven** from the spellbook (Might, Wisdom, Kings, Light, Salvation, Freedom, Protection, Sacrifice — **Sanctuary is removed**). Whether Greater Blessings exist in Forever is **unknown — probe the spellbook**; support single-target buff buttons first, add Greater variants only if they exist.
- "Auto-suggest" button proposes a sensible layout from which Blessings each paladin knows (e.g. Kings/Might for melee, Kings/Wisdom for casters). It only fills the grid; the user confirms.
- Permissions: each paladin edits their own row; group leader/assistants may edit any row.

**Sync protocol (addon messages, out of combat only)**
- Prefix `PKBM` via `C_ChatInfo.RegisterAddonMessagePrefix` / `SendAddonMessage` on `PARTY` / `RAID`.
- Messages: `HELLO|version|knownBlessings|knownAuras`, `ASSIGN|seq|paladin|classToken|blessingKey`, `AURA|seq|paladin|auraKey`, `CLEAR`, `REQ` (request full state). Keep each message < 255 bytes; chunk if needed. Include a monotonically increasing `seq` + timestamp for conflict resolution (last write wins; leader/assist wins ties).
- **Never send in combat or during an encounter.** Queue and flush on `PLAYER_REGEN_ENABLED` / `ENCOUNTER_END`. Throttle sends. Test that `SendAddonMessage` works on the real client (probe).
- Chat announcements (e.g. "assignments") are **manual, button-triggered only** — never automatic.

**Buff buttons**
- `SecureActionButtonTemplate` buttons: one "Buff next missing" button plus optional per-class buttons. Attributes `type=spell`, `spell=<name>`, `unit=<token>` (or a `macrotext` `/cast [@unit,...]`), updated **out of combat only** (rule 4.4). Bind to keybinds via `Bindings.xml`.
- "Next missing" selection uses out-of-combat aura reads of group members, skipping dead/offline/not visible units.
- The window and buttons can be hidden entirely if the player is not in a group.

### 7.5 TankKit (Prot preset; toggleable for any spec)
- Big, unmissable **Righteous Fury** warning when missing (with option to also warn on zone-in/ready check).
- **Taunt readiness**: Judgement cooldown state while Seal of Fury is the active Seal (cooldown display only, no logic beyond showing state).
- Consecration, Holy Strike, Hammer of Justice, Templar's Bulwark cooldown emphasis (reuses CooldownHUD widgets).
- Iron Creed damage-reduction buff indicator **if** readable.
- No threat display (threat APIs are restricted).

## 8. Spell and aura registry (`Data/Spells.lua`)

Names only, localized via `C_Spell` lookups; store `{key, name, category, verify=bool}`. Resolve name → spellID at runtime and cache; log unresolved names to the probe output.

- **Seals:** Righteousness, Command, Justice, Light, Wisdom, Crusader, Fury *(verify)*
- **Blessings:** Might, Wisdom, Kings, Light, Salvation, Freedom, Protection, Sacrifice *(Sanctuary removed)*
- **Auras:** Devotion, Retribution, Concentration, Fire Resistance, Frost Resistance, Shadow Resistance
- **Self buff:** Righteous Fury; **Ret proc/buff:** Twist of Light Echo *(verify exact aura name)*
- **Abilities:** Holy Strike *(new)*, Judgement, Consecration, Holy Shock, Divine Favor, Lay on Hands, Divine Shield, Divine Protection, Hammer of Justice, Hammer of Wrath, Exorcism, Holy Wrath, Repentance, Cleanse, Purify, Divine Intervention
- **Talent-gated, verify presence:** Templar's Bulwark, Light's Vigil, Infusion of Light, Sacred Arbiter, Sanctified Judgement

## 9. Diagnostics (`/pk probe`) — build this first

Because Claude Code cannot run the game, `/pk probe` is the most important early feature. It opens a **scrollable, selectable EditBox** so the owner can copy everything and paste it back. It reports:

- Client version/build, interface number, `issecretvalue` present?
- Which of these exist: `C_UnitAuras.*` (`GetAuraDataByIndex`, `GetPlayerAuraBySpellID`, `GetAuraDataBySpellName`, `GetUnitAuras`), `C_Spell.*` (`GetSpellInfo`, `GetSpellCooldown`, `GetSpellCooldownDuration`), `C_SpellBook.*`, `C_ChatInfo.*`, `Cooldown:SetCooldownFromDurationObject`, talent APIs, `C_Secrets.*`, `C_CurveUtil.*`, `Settings.*`, and the removed legacy globals.
- For every name in `Data/Spells.lua`: resolved? spellID? known by the player?
- Spec detection: every strategy's raw result and the final decision.
- Player aura readability **out of combat**, and `/pk probe combat` which runs after the owner enters combat with a dummy and reports which fields of the player's own auras and cooldowns are secret vs readable.
- Addon message prefix registration result and a loopback self-send test.
- Interface/AddOns folder path hint and the SavedVariables load state (helps diagnose the reset bug).

Also add `/pk debug on|off` for verbose logging to the same copy window, and `/pk errors` reminding the owner to run `/console scriptErrors 1`.

## 10. Config schema (SavedVariables `PaladinKitDB`)

```lua
PaladinKitDB = {
  version = 1,
  profileKeys = { ["Char-Realm"] = "Default" },
  profiles = {
    Default = {
      specMode = "auto",            -- auto | holy | prot | ret
      modules = {                   -- per-spec overrides of the default matrix
        holy = { BuffSentinel = true, SealTracker = true, CooldownHUD = true, BlessingManager = true, TankKit = false },
        prot = { ... }, ret = { ... },
      },
      layout = {                    -- per spec, per module: point, x, y, scale, iconSize, growDir
        holy = { CooldownHUD = { point = "CENTER", x = 0, y = -180 } },
      },
      cooldownLists = { holy = { "Holy Shock", ... }, prot = { ... }, ret = { ... } },
      alerts = { sound = true, expiringThresholdSec = 120 },
      blessing = { assignments = {}, autoSuggest = true },
    },
  },
}
```

Include a `migrate()` stub and default-filling that never wipes user keys.

## 11. Settings UI and profile export/import

- Use the client's `Settings` API if the probe finds it; otherwise a standalone draggable config frame opened by `/pk`.
- Top: **Spec mode dropdown** (Auto/Holy/Prot/Ret) with the "Detected: X (confidence)" text.
- Per-spec module toggle matrix (the table in section 6), plus per-module options (icon size, spacing, grow direction, alerts).
- **Lock/Unlock** layout with a grid and `/pk unlock`, `/pk lock`, `/pk reset`.
- **Export/Import profile** as a single pasteable string (simple dependency-free serializer + checksum). This is the workaround for the reported SavedVariables persistence bug and for sharing setups.

## 12. Tooling and workflow

- Lint with **luacheck** (`.luacheckrc` declaring WoW globals) and keep it clean.
- Unit-test pure-Lua logic with **busted**: spec-detection decision logic, assignment conflict resolution, serializer round-trip, auto-suggest layout. Mock WoW APIs in `tests/mocks.lua`.
- `tools/install.ps1` and `tools/install.sh`: copy or symlink `PaladinKit/` into the AddOns dir given by env `WOW_ADDONS_DIR` (default to the beta path in section 3, easily overridden for launch).
- In-game loop for the owner: `/console scriptErrors 1` → `/reload` → reproduce → paste errors and `/pk probe`.
- Commit after every milestone with a clear message. Keep `CHANGELOG.md` current.
- Release later via GitHub + CurseForge using the BigWigs packager (`.pkgmeta`); MIT license; donation link allowed.

## 13. Milestones and acceptance

**M0 — Scaffold + Diagnostics.** Addon loads with zero Lua errors on the beta client; `/pk`, `/pk probe`, `/pk probe combat`, `/pk debug` work; probe output is complete and copyable. *Stop here for the owner's test results.*

**M1 — Core.** Init/event bus, Compat, Secrets, Config with defaults/migration, SpecProfile (all four modes, manual switching works, auto-detection using whatever the probe found), frame widgets with lock/unlock/drag, settings panel skeleton, profile export/import.

**M2 — Holy MVP.** BuffSentinel, SealTracker, CooldownHUD with the Holy preset. Works out of combat; in combat degrades silently per rule 4.1. Toggling any module on/off and switching spec live works without `/reload`.

**M3 — Prot and Ret presets.** TankKit, Twist of Light Echo indicator, Prot/Ret cooldown lists and default matrix.

**M4 — BlessingManager.** Grid UI, sync protocol, secure buff buttons, keybinds, auto-suggest. Test with two paladin clients (owner + friend/alt) if possible.

**M5 — Polish.** Locales scaffold, README with screenshots, packaging files, final luacheck/busted pass, `docs/PROBE_LOG.md` capturing the verified API surface for launch-day re-check.

**v0.1 definition of done (target: before Nov 4 launch):** M0–M3 complete, plus a usable BlessingManager if M4 is ready; README explains install path and known beta limitations.

## 14. Known unknowns (resolve with the probe, then record answers in `docs/PROBE_LOG.md`)

- Are the player's own auras and cooldowns readable in combat, and which spells are whitelisted?
- Exact aura names and durations: Seal of Fury, Twist of Light Echo, Iron Creed buff, Righteous Fury.
- Do Greater Blessings exist? Final Blessing/Aura list from the real spellbook.
- Which talent/spec API exists; are Seal of Fury / Templar's Bulwark talents or trained spells?
- Do addon messages work on PARTY/RAID, and are they blocked during encounters?
- Does `UnitGetTotalAbsorbs("player")` return a readable value in combat?
- Will the addon path or interface number change at launch? Re-run the probe on launch day.

## 15. Non-goals (v1)

Threat meters, damage meters, boss mods, party health/heal alerts, enemy debuff/cast trackers, rotation advisors, auto-chat/whisper/marking, third-party library dependencies, Retail/Classic Era support.

## 16. References

- Warcraft Wiki API change pages: Patch 12.0.1, 12.0.5, 12.1.0 (`warcraft.wiki.gg`) — secret values, duration objects, cooldown APIs, aura APIs
- Icy Veins, "Addons in WoW Forever?" — Blizzard UI statement (shares Mainline APIs, 12.1.5)
- wow4ever.quest/en/addons and wowforeverbuilds.com — beta addon compatibility, interface 16001, beta path, removed globals
- Warcraft Tavern / Zockify / ForeverChanges — Paladin changes in Forever
- Blizzard news: World of Warcraft: Forever beta dates (Sept 17 – Oct 21), launch Nov 4 2026, 3:00 p.m. PST

---

## 17. Working decisions (agreed with owner, 2026-09-23)

These override the matching parts of sections 9, 12 and 5 above.

- **Repo:** `<Desktop>\PaladinKit`, repo root = addon folder.
- **Installed via a junction:** `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\PaladinKit` → repo (`tools\install.ps1`). Edits are live after `/reload`.
- **Read results from disk, don't ask for pastes.** `/pk probe` and `/pk probe combat` save to `PaladinKitDB.probe` / `.probeCombat`; captured Lua errors go to `PaladinKitDB.errors`. After the owner types `/reload`, read `C:\Program Files (x86)\World of Warcraft\_classic_beta_\WTF\Account\<account>\SavedVariables\PaladinKit.lua` (the account folder seen so far is `<account>`). The copy window is the fallback.
- **Tests:** `python tests/run_tests.py` (lupa, Lua 5.1) instead of busted; mocks in `tests/mocks.lua`, with secret values modeled as proxies that error on compare, math and concat. Keep it passing before asking the owner to test. Put pure logic in files that don't touch WoW APIs so it can be tested directly.
- **Lint:** `.luacheckrc` is kept current; luacheck isn't installed yet.
- **Architecture:** Core (Init, Compat, Secrets, Config, SpecProfile, CombatQueue) → Services (SpellRegistry, AuraService, CooldownService, Comm) → pure Logic → UI widgets → Modules. Only Services call version-sensitive APIs, and only through Compat. Modules only render what Services publish. Every safe read has three states: value / SECRET / UNAVAILABLE.
- **Plain Lua 5.1 `xpcall` passes no extra arguments** (WoW's does); `PK.SafeCall` wraps calls in a closure so both work.
- **Never register `COMBAT_LOG_EVENT_UNFILTERED`**, not even inside the probe.
