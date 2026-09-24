# Changelog

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
