# Changelog

## 0.5.4

- Fixed: Blessing sync never sent anything. The game's blanket "addon chat
  restricted" check says yes even out of combat, while messages go
  through fine. Sending now uses the specific restriction checks (still
  never in combat or during boss fights).
- Verified in a party: group members' buffs are readable out of combat, so
  the buff button works on your group.

## 0.5.3

- Buff button shows who's next: class icon, class-colored name, and
  "missing", time left, or "refresh (52m)". The icon is the Blessing you're
  about to cast (it changes as you learn more Blessings).
- New (on by default): when nobody is missing your Blessing, the button
  targets the lowest timer, so every press refreshes the oldest Blessing.
  Missing ones still come first, then ones under 5 minutes. Toggle it in
  settings ("Buff button: refresh the lowest timer...").
- Tooltip spells out the next press.

## 0.5.2

- Works around Forever's beta settings bug: your profile is also saved to a
  per-character file. If the main file doesn't load, the addon restores
  your profile from the character copy and says so in chat.

## 0.5.1

- When no saved settings were loaded (confirmed Forever beta bug after a
  full client restart), a chat notice explains it and points to
  `/ptk import`.
- Auto spec detection now uses your talent points. Forever has one talent
  tree with Holy, Protection and Retribution side by side, and the addon
  counts the points spent in each column.
- Tank Kit adds Holy Shield (a Forever Protection talent). Unedited Tank Kit
  lists upgrade automatically.
- Spell list updated from the real talent tree: Blessed Life removed (not
  in Forever); talents confirmed by name.

## 0.5.0 - M5: polish and packaging (first beta release candidate)

- Fixed: a gold box inside the buff button icon (a glow texture squeezed
  onto a small icon). Icon borders are now crisp thin edges; "missing" is a
  2px red edge.
- The Blessing grid button next to the buff button has a clearer icon and a
  tooltip; the grid window sizes itself to the paladins present.
- Settings: the selected spec mode is highlighted; the cooldown hint no
  longer overlaps the Options window's Close button.
- Blessing sync no longer queues messages while you're solo.
- Localization scaffold (`Locales/enUS.lua`).
- `tools/package.py` builds the release zip; README rewritten with
  install steps, features, the combat-restriction approach and known limits.
- `docs/PROBE_LOG.md`: verified-API summary and a launch-day checklist.
- Tests fail if the addon leaks a global variable.

## 0.4.0-dev - M4: Blessing Manager, Holy theme

- Blessing Manager (PallyPower-style):
  - Assignment grid (`/ptk bless`): one row per paladin, one column per
    class plus Aura. Click to cycle Blessings, right-click back, Shift-click
    to clear. You edit your row; the group leader and assistants can edit any.
  - Auto-suggest fills a sensible layout (Kings/Might for melee,
    Kings/Wisdom for casters, no Salvation on warriors, no Might on
    casters, distinct Auras). "Announce" posts it to party/raid, only when
    you click it.
  - Syncs with other paladins running the addon, only out of combat and
    outside boss encounters, in party/raid.
  - Buff button: one press casts your assigned Blessing on the next group
    member missing it (or with under 5 minutes left). Keybind under Key
    Bindings > AddOns. Target and spell are chosen out of combat only.
- Holy theme: gold-bordered windows, gold headers, holy icons, gold drag
  boxes and chat prefix.
- A missing Seal is only flagged in combat (grey "No Seal" out of combat).

## 0.3.0-dev - M3: Protection and Retribution

- Tank Kit (on for Protection by default): a big flashing "Righteous Fury
  missing" warning plus a sound on zone-in and ready checks; large cooldown
  icons for Judgement, Consecration, Holy Strike, Hammer of Justice and
  Templar's Bulwark, with Judgement labelled TAUNT while Seal of Fury is up;
  an Iron Creed indicator with time left. No threat display (restricted).
- Seal Tracker: Twist of Light's Echo shown next to the Seal (Ret), with
  the replaced Seal's icon and time left. State only, never advice.
- In combat, your own casts keep these current while buffs are hidden:
  Righteous Fury refreshes, Echo from swapping away from Command /
  Righteousness / Fury / Justice, Iron Creed from Holy Strike with
  Righteous Fury (all marked * when predicted).
- Default bars: Prot's defensives only (the rotation lives in the Tank
  Kit); Ret adds Crusade, Cleanse/Purify (group only). Unedited lists
  upgrade automatically.
- Settings: Echo, Righteous Fury warning and sound options.

## 0.2.0-dev - M2: Holy MVP

- Buff Sentinel: icons for a missing Seal, Aura, Blessing or (Prot)
  Righteous Fury; long buffs pulse with time left when about to expire
  (2 min by default). Sound when something newly goes missing (out of
  combat). `/ptk check` prints every check, and a ready check does too.
- Seal Tracker: active Seal with a draining time bar; smaller for Holy.
- Cooldown HUD: your spec's cooldown row with swipes that keep working in
  combat, greyed when unusable; unlearned spells hidden. Edit with
  `/ptk cd list|add|remove|reset`.
- Combat blindness handled: Forever hides your buffs in combat, so the
  addon keeps the last known state, keeps counting timers down, reads your
  Paladin aura from the stance bar, and predicts a Seal you cast in combat
  (shown with *). A Seal it truly can't see shows grey instead of a false
  "missing" alarm.
- Holy cooldown bar: Hammer of Justice added; Cleanse and Purify show only
  while you're in a party or raid (`/ptk cd group <spell>` toggles that for
  any spell). Unedited Holy lists are upgraded automatically.
- Cooldown bar ignores the global cooldown, in and out of combat.
- Settings: Options column (sound, show all buffs, Righteous Fury warnings,
  Seal bar, unlearned spells, vertical cooldown bar).

## 0.1.0-dev - M1: core

- Settings saved per character profile, with defaults that never overwrite
  your choices, a migration hook, and profile export/import as one pasteable
  string (checksummed; a damaged or edited string is rejected, and unknown
  settings are dropped).
- Spec choice: Auto / Holy / Protection / Retribution via `/ptk auto|holy|prot|ret`,
  the settings panel, or a keybind that cycles modes. Switching is instant.
  Auto currently detects your spec from tree-specific spells you know;
  talent-point detection comes once the level 10 probe shows how Forever's
  trees are stored.
- Per-spec module on/off matrix (modules themselves arrive in M2/M3).
- Movable frames: `/ptk unlock` shows a green box per enabled module and
  an alignment grid; positions are saved per spec; `/ptk lock`, `/ptk reset`.
- Settings panel in Options > AddOns (`/ptk` opens it): spec mode, detection
  status, module matrix, lock/reset, export/import/reset profile.
- Secret-value-safe reads (`Core/Secrets.lua`), a combat queue for anything
  that must wait until combat ends, and a spell registry that tracks what
  you know as you learn spells.

## 0.0.1 (unreleased) - M0: scaffold and diagnostics

- Core: namespace, event bus, internal messages, module registry, slash
  commands, Lua error capture saved to `NyteLytePaladinToolkitDB.errors`, and a record
  of whether saved variables loaded (for the beta reset bug).
- Compat layer for version-sensitive APIs (spells, spellbook, cooldowns,
  auras, secret-value checks).
- Spell and aura registry by name (`Data/Spells.lua`).
- `/ptk probe`, `/ptk probe combat`, `/ptk show`, `/ptk debug`, `/ptk errors`, and a
  copyable text window.
- Mocked-API test harness (`tests/run_tests.py`).
- Probe v2, after the first real run: spellbook flyouts (Blessings/Auras),
  every aura read path in combat, `C_Secrets` queries, restriction state,
  C_Traits talent-tree dump, duration-object methods found by name. Mocks now
  match the real client's secret-value behavior.
