"""Loads NyteLytePaladinToolkit against mocked WoW APIs (tests/mocks.lua) under Lua 5.1 and
drives the M0 flows (login, /ptk probe, /ptk probe combat through a fake
combat), then tests/m1_flows.lua (spec switching, frames, settings,
export/import) and tests/logic_spec.lua (pure logic). Fails on any Lua error, any error the
addon captured, or any secret value that reached NyteLytePaladinToolkitDB.

Needs lupa (pip install lupa). Run: python tests/run_tests.py
"""
import os
import re
import sys

from lupa.lua51 import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOC = os.path.join(ROOT, "NyteLytePaladinToolkit.toc")


def toc_files():
    files = []
    with open(TOC, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                files.append(line.replace("\\", os.sep))
    return files


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def new_runtime(flags):
    lua = LuaRuntime(unpack_returned_tuples=True)
    for flag in flags:
        lua.execute(f"{flag} = true")
    if "MOCK_CLASS_WARRIOR" in flags:
        lua.execute('MOCK_CLASS = "WARRIOR"')
    lua.execute(read(os.path.join(ROOT, "tests", "mocks.lua")))
    loader = lua.eval("""function(src, name, ns)
        local f, err = loadstring(src, "@" .. name)
        if not f then error(err) end
        f("NyteLytePaladinToolkit", ns)
    end""")
    lua.execute("MOCK_GLOBALS_BEFORE = {} for k in pairs(_G) do MOCK_GLOBALS_BEFORE[k] = true end")
    ns = lua.table()
    for rel in toc_files():
        loader(read(os.path.join(ROOT, rel)), "NyteLytePaladinToolkit/" + rel.replace(os.sep, "/"), ns)
    return lua


CHECKS = r"""
local function slash(msg) SlashCmdList.NYTELYTEPALADINTOOLKIT(msg) end

if MOCK_CHAR_BACKUP then
  -- Account file didn't load (beta bug) but the per-character backup did.
  NyteLytePaladinToolkitCharDB = { savedAt = 900, profileName = "Default",
    profile = { specMode = "ret", locked = true, cooldownLists = { holy = { "HOLY_SHOCK" } } } }
end

MOCK.fire("ADDON_LOADED", "NyteLytePaladinToolkit")
MOCK.fire("PLAYER_LOGIN")
assert(NyteLytePaladinToolkitDB and NyteLytePaladinToolkitDB.meta.loads == 1, "db not initialised")
assert(NyteLytePaladinToolkit.svState.existedAtLoad == false, "fresh install should report no SV at load")
if MOCK_CHAR_BACKUP then
  local p = NyteLytePaladinToolkit.profile
  assert(NyteLytePaladinToolkit.svState.restoredFromCharacter, "restored from character backup")
  assert(p.specMode == "ret" and #p.cooldownLists.holy == 1, "backup profile restored")
  assert(p.cooldownLists.prot and p.moduleSettings, "missing keys filled from defaults")
  p.specMode = "auto"
  p.cooldownLists.holy = NyteLytePaladinToolkit.Config.DeepCopy(NyteLytePaladinToolkit.Presets.cooldownLists.holy)
else
  assert(NyteLytePaladinToolkit.svState.restoredFromCharacter == nil, "nothing to restore")
end

slash("")
slash("help")
slash("probe")
local p = NyteLytePaladinToolkitDB.probe
assert(p, "no probe saved")
assert(p.client.interface == 16001, "interface")
assert(next(p.stepErrors) == nil or MOCK_EXPECT_STEP_ERRORS, "step errors: " .. tostring(next(p.stepErrors)))

-- self-whisper loopback arrives asynchronously
local sent = MOCK.sent[1]
if sent then
  MOCK.fire("CHAT_MSG_ADDON", sent.prefix, sent.text, sent.channel, "Tester")
  assert(#p.comm.received == 1, "loopback not recorded")
end

slash("probe combat")
MOCK.combat = true
slash("probe")               -- refused in combat, must not error
MOCK.fire("PLAYER_REGEN_DISABLED")
MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 20271)
MOCK.fire("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-2", 1)
MOCK.fire("UNIT_AURA", "player", { isFullUpdate = false, addedAuras = { { name = MOCK.secret(), spellId = MOCK.secret() } },
  removedAuraInstanceIDs = { 7 } })
MOCK.runTimers()
MOCK.combat = false
MOCK.fire("PLAYER_REGEN_ENABLED")
local c = NyteLytePaladinToolkitDB.probeCombat
assert(c and #c.samples == 6 and #c.events == 2, "expected 6 combat samples and 2 events, got " .. tostring(c and #c.samples))

slash("debug on")
NyteLytePaladinToolkit:Debug("hello %s", "world")
slash("debug show")
slash("debug clear")
slash("show")
slash("errors")
slash("nonsense words")
MOCK.fire("PLAYER_LOGOUT")
assert(type(NyteLytePaladinToolkitCharDB) == "table" and NyteLytePaladinToolkitCharDB.profile == NyteLytePaladinToolkit.profile,
  "character backup written on logout")

-- Walk the saved data: no secret value may be stored anywhere.
local seen = {}
local function walk(t, path)
  if seen[t] then return end
  seen[t] = true
  for k, v in pairs(t) do
    if MOCK.isSecret(k) or MOCK.isSecret(v) then
      error("secret value saved at " .. path .. "." .. tostring(k))
    end
    if type(v) == "table" then walk(v, path .. "." .. tostring(k)) end
  end
end
walk(NyteLytePaladinToolkitDB, "NyteLytePaladinToolkitDB")

RESULT = {
  errorsCaptured = #NyteLytePaladinToolkit.errorList,
  errorsRaised = #MOCK.errorsRaised,
  firstError = MOCK.errorsRaised[1] or (NyteLytePaladinToolkit.errorList[1] and NyteLytePaladinToolkit.errorList[1].msg),
  probeTextLength = #NyteLytePaladinToolkit.modules.Diagnostics.ProbeText(),
  decision = p.spec and p.spec.decision.spec .. " via " .. p.spec.decision.method,
  unresolved = p.registry and #p.registry.unresolved or -1,
  combatUnitHealth = c.samples[3].units["UnitHealth(player)"].value,
  combatCooldown = c.samples[3].cooldowns.spells and c.samples[3].cooldowns.spells["Judgement"]
    and c.samples[3].cooldowns.spells["Judgement"].cooldown.startTime,
}
"""

# Globals the addon is allowed to create (everything else is a leak, e.g. a
# missing `local`). Frame names, slash commands and keybinding labels are fine.
ALLOWED_GLOBAL_PREFIXES = ("NyteLytePaladinToolkit", "SLASH_NYTELYTEPALADINTOOLKIT", "BINDING_")
TEST_GLOBALS = {"RESULT", "M1_OK", "M2_OK", "M3_OK", "M4_OK", "LOGIC_OK", "MOCK_GLOBALS_BEFORE"}


def leaked_globals(lua):
    names = lua.eval("""(function()
        local out = {}
        for k in pairs(_G) do
            if not MOCK_GLOBALS_BEFORE[k] then out[#out + 1] = tostring(k) end
        end
        table.sort(out)
        return table.concat(out, ",")
    end)()""")
    return [n for n in names.split(",") if n and n not in TEST_GLOBALS
            and not n.startswith(ALLOWED_GLOBAL_PREFIXES)]


DORMANT_CHECKS = r"""
MOCK.fire("ADDON_LOADED", "NyteLytePaladinToolkit")
MOCK.fire("PLAYER_LOGIN")
MOCK.fire("SPELLS_CHANGED")
MOCK.fire("UNIT_AURA", "player", {})
MOCK.fire("PLAYER_REGEN_DISABLED")
MOCK.runTimers()
local P = NyteLytePaladinToolkit
assert(P.dormant == true and P.playerClass == "WARRIOR", "dormant on a Warrior")
assert(NyteLytePaladinToolkitDB == nil, "saved settings untouched (not even created)")
assert(P.profile == nil, "no profile loaded")
assert(_G.NyteLytePaladinToolkitBuffButton == nil, "no buff button")
assert(MOCK.settingsOpened == 0, "no settings opened")
local printed = #MOCK.printed
SlashCmdList.NYTELYTEPALADINTOOLKIT("")
SlashCmdList.NYTELYTEPALADINTOOLKIT("probe")
assert(#MOCK.printed == printed + 2 and MOCK.printed[#MOCK.printed]:find("only runs on Paladins"), "slash explains")
assert(MOCK.settingsOpened == 0, "settings still not opened")
for _, f in ipairs({ "PLAYER_LOGOUT" }) do MOCK.fire(f) end
assert(NyteLytePaladinToolkitCharDB == nil, "no character backup written")
RESULT = { errorsCaptured = 0, errorsRaised = 0, decision = "dormant (Warrior)", unresolved = 0,
  probeTextLength = 0, combatUnitHealth = "-", combatCooldown = "-" }
"""

SCENARIOS = [
    ("forever-shaped client", []),
    ("no issecretvalue", ["MOCK_NO_SECRETS"]),
    ("no C_SpellBook / C_UnitAuras", ["MOCK_NO_SPELLBOOK", "MOCK_NO_AURAS"]),
    ("account file lost, character backup restores", ["MOCK_CHAR_BACKUP"]),
    ("non-Paladin (Warrior): dormant", ["MOCK_CLASS_WARRIOR"]),
]


def main():
    failed = 0
    for name, flags in SCENARIOS:
        try:
            lua = new_runtime(flags)
            if "MOCK_CLASS_WARRIOR" in flags:
                lua.execute(DORMANT_CHECKS)
                r = lua.globals().RESULT
                errors = lua.eval("#NyteLytePaladinToolkit.errorList + #MOCK.errorsRaised")
                leaked = leaked_globals(lua)
                ok = errors == 0 and not leaked
                print(f"[{'PASS' if ok else 'FAIL'}] {name}: {r.decision}" + (f", leaked {leaked}" if leaked else ""))
                failed += 0 if ok else 1
                continue
            lua.execute(CHECKS)
            for extra in ("m1_flows.lua", "m2_flows.lua", "m3_flows.lua", "m4_flows.lua", "logic_spec.lua"):
                lua.execute(read(os.path.join(ROOT, "tests", extra)))
            r = lua.globals().RESULT
            leaked = leaked_globals(lua)
            if leaked:
                raise AssertionError("addon created unexpected globals: " + ", ".join(leaked))
            errors = lua.eval("#NyteLytePaladinToolkit.errorList + #MOCK.errorsRaised")
            ok = errors == 0
            first = lua.eval("MOCK.errorsRaised[1] or (NyteLytePaladinToolkit.errorList[1] and NyteLytePaladinToolkit.errorList[1].msg)")
            status = "PASS" if ok else "FAIL"
            print(f"[{status}] {name}: decision={r.decision}, unresolved={r.unresolved}, "
                  f"probe text {r.probeTextLength} chars, combat UnitHealth={r.combatUnitHealth}, "
                  f"combat Judgement start={r.combatCooldown}")
            if not ok:
                failed += 1
                print("   first error:", first)
        except Exception as e:  # Lua error surfaced to Python
            failed += 1
            print(f"[FAIL] {name}: {e}")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
