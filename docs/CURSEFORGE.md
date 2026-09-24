# Publishing on CurseForge

Everything needed to create the project and upload the first file. Lessons
carried over from ReagentRoute (project 1707609):

- **Upload as Beta or Release, never Alpha only.** CurseForge's app doesn't
  list projects whose only files are Alpha.
- **Every file goes through moderation.** The first one also waits for
  project approval.
- **The zip must contain one folder named exactly like the TOC:**
  `NyteLytePaladinToolkit/NyteLytePaladinToolkit.toc`. `python
  tools/package.py` builds it that way, with forward-slash paths.

## 1. Create the project

Go to <https://authors.curseforge.com/#/projects/create/choose-game>, pick
**World of Warcraft**, then fill in:

| Field | Value |
|---|---|
| Name | `Nyte Lyte's Paladin Toolkit` |
| Summary | see below |
| Description | see below |
| Main category | **Class → Paladin** (or the closest Paladin/Class category offered) |
| Additional categories | **Buffs & Debuffs**, **Combat** |
| License | **MIT License** |
| Logo / avatar | `docs/logo.png` (400×400, original art) |
| Source code URL | `https://github.com/Nyte-fyre/NyteLytePaladinToolkit` |
| Issues URL | `https://github.com/Nyte-fyre/NyteLytePaladinToolkit/issues` |

If the name is taken, fall back to `Nyte Lyte Paladin Toolkit`. The in-game
name stays the same either way.

### Summary (short blurb)

```
All-in-one Paladin addon for WoW: Forever: buff & Seal tracking, cooldowns, a Tank Kit, and PallyPower-style Blessing coordination with a one-press buff button.
```

### Description (paste as Markdown)

```markdown
**Nyte Lyte's Paladin Toolkit** replaces a stack of WeakAuras and PallyPower
with one addon built for **World of Warcraft: Forever**. Pick Holy,
Protection or Retribution (or let it detect your spec from your talents) and
it shows what matters for that spec.

### Features
- **Spec aware:** Auto / Holy / Protection / Retribution, each with its
  own modules, cooldown bar and frame positions. Switch instantly with
  `/ptk holy`, `/ptk prot`, `/ptk ret` or a keybind.
- **Buff Sentinel:** icons pop up when your Aura or Blessing is missing or
  about to run out. Also covers Righteous Fury as Protection, and your
  Seal in combat. `/ptk check` and ready checks report it all.
- **Seal Tracker:** your Seal with a draining timer, plus Twist of Light's
  Echo for Retribution.
- **Cooldown HUD:** your spec's cooldowns with swipes that keep working in
  combat. It ignores the global cooldown, and Cleanse/Purify only show
  in a group. Edit it with `/ptk cd`.
- **Tank Kit:** a big Righteous Fury warning, large tanking cooldowns
  (Judgement shows TAUNT under Seal of Fury), and an Iron Creed timer.
- **Blessing Manager (PallyPower-style):**
  - An assignment grid for every paladin in the group, with auto-suggest
    and live sync between paladins running the addon.
  - A **buff button**: one press casts your assigned Blessing on whoever
    needs it most. Missing first, then about to expire, then the lowest
    timer.
- **Profile export/import:** copy your whole setup as one text string.

### Plays by Blizzard's rules
Forever hides a lot of combat information from addons, and this addon
follows those rules:
- **No combat log, threat meter, enemy tracking or rotation advice.**
- **Never sends chat or marks targets by itself.** "Announce" only posts
  when you click it.
- **Every button press casts exactly one spell.** Nothing is automated.
- Where Forever hides your buffs mid-fight, the addon keeps what it saw
  before the pull and follows your own casts. Anything worked out this way
  is marked with `*`.

### Getting started
Type `/ptk` for settings, `/ptk unlock` to move frames, and `/ptk bless`
for the Blessing grid. `/ptk help` lists every command.

### Beta notes
Built and tested against the WoW: Forever beta. Some later spells and
talents (Seal of Fury, Twist of Light, Iron Creed) couldn't be tested at
the beta's level cap yet. Their details correct themselves once the addon
sees them. If your settings ever reset after a game restart (a known beta
issue), the addon tells you. Keep a `/ptk export` string saved to restore
them.

Free and open source (MIT). Bug reports and ideas:
https://github.com/Nyte-fyre/NyteLytePaladinToolkit/issues
```

## 2. Upload the first file

After creating the project, open its **Files** tab and upload:

- **File:** `dist/NyteLytePaladinToolkit-<version>.zip` (run
  `python tools/package.py` first; it names the zip after the TOC version).
- **Release type:** **Beta**. It's still pre-launch and tested on the beta,
  but Beta files appear in the app, unlike Alpha.
- **Game version:** the **WoW Forever** flavor (the client reports
  interface 16001, build 1.60.1). Tag only Forever. The addon uses
  Forever's retail-style API and won't work on Classic Era, TBC or Retail.
- **Changelog:** paste the top section of `CHANGELOG.md`.

## 3. After approval

1. Copy the **project ID** from the project page (right sidebar, "Project ID").
2. Add it to the TOC under `## X-License`: `## X-Curse-Project-ID: <id>`.
3. Commit, push, rebuild the zip for the next upload.
4. Optional later: link the GitHub repo in CurseForge's "Source" settings
   and add a `.pkgmeta`-driven webhook, so each tagged release packages
   automatically (`.pkgmeta` is already in the repo).
