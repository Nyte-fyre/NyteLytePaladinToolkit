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

## Paladin Toolkit probe results

_None yet. First run pending._
