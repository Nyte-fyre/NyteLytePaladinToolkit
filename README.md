# Nyte Lyte's Paladin Toolkit

An all-in-one Paladin addon for **World of Warcraft: Forever**: buff and seal
tracking, cooldowns, and PallyPower-style blessing coordination, tuned for
Holy, Protection or Retribution.

**Status: early development (M1: core).** Settings, spec switching, movable
frames and profile export/import work; the buff/seal/cooldown modules come next.

## Install (Forever beta)

Copy or link this folder into:

```
World of Warcraft\_classic_beta_\Interface\AddOns\NyteLytePaladinToolkit
```

The folder must be named `NyteLytePaladinToolkit` and contain `NyteLytePaladinToolkit.toc`. From a
clone, `tools\install.ps1` does this (set `WOW_ADDONS_DIR` for other paths).

## Commands

| Command | What it does |
|---|---|
| `/ptk` | Open settings |
| `/ptk auto` / `holy` / `prot` / `ret` | Choose spec mode |
| `/ptk spec` | Show the active spec and what Auto detected |
| `/ptk unlock` / `lock` / `reset` | Move frames, lock them, reset positions |
| `/ptk export` / `import` | Copy your profile as text / paste one in |
| `/ptk probe` | Records what the client supports and shows it in a copyable window |
| `/ptk probe combat` | Arms a capture for your next fight (hit a target dummy ~10s) |
| `/ptk show` | Shows the last probe results again |
| `/ptk debug on\|off\|show\|clear` | Verbose logging |
| `/ptk errors` | Shows Lua errors the addon caught this session |

## Development

- `python tests/run_tests.py` runs the addon against mocked WoW APIs
  under Lua 5.1 (needs `pip install lupa`).
- Probe output is saved to `WTF\Account\<account>\SavedVariables\NyteLytePaladinToolkit.lua`
  on `/reload` or logout.

## Known beta limitations

- The beta has a reported bug where saved settings don't load on a fresh
  client start. Profile export/import (coming in M1) is the workaround.
- Beta characters are capped at level 20, so many spells and talents can't
  be verified until launch.

## License

MIT. Free, with open source, as Blizzard's addon policy requires.
