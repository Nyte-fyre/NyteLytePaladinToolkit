# Changelog

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
