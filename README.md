# PaladinKit

An all-in-one Paladin addon for **World of Warcraft: Forever**: buff and seal
tracking, cooldowns, and PallyPower-style blessing coordination, tuned for
Holy, Protection or Retribution.

**Status: early development (M0: scaffold and diagnostics).** Only the
diagnostics commands work so far.

## Install (Forever beta)

Copy or link this folder into:

```
World of Warcraft\_classic_beta_\Interface\AddOns\PaladinKit
```

The folder must be named `PaladinKit` and contain `PaladinKit.toc`. From a
clone, `tools\install.ps1` does this (set `WOW_ADDONS_DIR` for other paths).

## Commands

| Command | What it does |
|---|---|
| `/pk probe` | Records what the client supports and shows it in a copyable window |
| `/pk probe combat` | Arms a capture for your next fight (hit a target dummy ~10s) |
| `/pk show` | Shows the last probe results again |
| `/pk debug on\|off\|show\|clear` | Verbose logging |
| `/pk errors` | Shows Lua errors PaladinKit caught this session |

## Development

- `python tests/run_tests.py` runs the addon against mocked WoW APIs
  under Lua 5.1 (needs `pip install lupa`).
- Probe output is saved to `WTF\Account\<account>\SavedVariables\PaladinKit.lua`
  on `/reload` or logout.

## Known beta limitations

- The beta has a reported bug where saved settings don't load on a fresh
  client start. Profile export/import (coming in M1) is the workaround.
- Beta characters are capped at level 20, so many spells and talents can't
  be verified until launch.

## License

MIT. Free, with open source, as Blizzard's addon policy requires.
