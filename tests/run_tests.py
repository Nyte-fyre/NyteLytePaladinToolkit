"""Loads PaladinKit against mocked WoW APIs (tests/mocks.lua) under Lua 5.1 and
drives the M0 flows: login, /pk probe, /pk probe combat through a fake
combat, and the other slash commands. Fails on any Lua error, any error the
addon captured, or any secret value that reached PaladinKitDB.

Needs lupa (pip install lupa). Run: python tests/run_tests.py
"""
import os
import re
import sys

from lupa.lua51 import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOC = os.path.join(ROOT, "PaladinKit.toc")


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
    lua.execute(read(os.path.join(ROOT, "tests", "mocks.lua")))
    loader = lua.eval("""function(src, name, ns)
        local f, err = loadstring(src, "@" .. name)
        if not f then error(err) end
        f("PaladinKit", ns)
    end""")
    ns = lua.table()
    for rel in toc_files():
        loader(read(os.path.join(ROOT, rel)), "PaladinKit/" + rel.replace(os.sep, "/"), ns)
    return lua


CHECKS = r"""
local function slash(msg) SlashCmdList.PALADINKIT(msg) end

MOCK.fire("ADDON_LOADED", "PaladinKit")
MOCK.fire("PLAYER_LOGIN")
assert(PaladinKitDB and PaladinKitDB.meta.loads == 1, "db not initialised")
assert(PaladinKit.svState.existedAtLoad == false, "fresh install should report no SV at load")

slash("")
slash("help")
slash("probe")
local p = PaladinKitDB.probe
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
MOCK.runTimers()
MOCK.combat = false
MOCK.fire("PLAYER_REGEN_ENABLED")
local c = PaladinKitDB.probeCombat
assert(c and #c.samples == 5, "expected 5 combat samples, got " .. tostring(c and #c.samples))

slash("debug on")
PaladinKit:Debug("hello %s", "world")
slash("debug show")
slash("debug clear")
slash("show")
slash("errors")
slash("nonsense words")
MOCK.fire("PLAYER_LOGOUT")

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
walk(PaladinKitDB, "PaladinKitDB")

RESULT = {
  errorsCaptured = #PaladinKit.errorList,
  errorsRaised = #MOCK.errorsRaised,
  firstError = MOCK.errorsRaised[1] or (PaladinKit.errorList[1] and PaladinKit.errorList[1].msg),
  probeTextLength = #PaladinKit.modules.Diagnostics.ProbeText(),
  decision = p.spec and p.spec.decision.spec .. " via " .. p.spec.decision.method,
  unresolved = p.registry and #p.registry.unresolved or -1,
  combatUnitHealth = c.samples[3].units["UnitHealth(player)"].value,
  combatCooldown = c.samples[3].cooldowns.spells and c.samples[3].cooldowns.spells["Judgement"]
    and c.samples[3].cooldowns.spells["Judgement"].cooldown.startTime,
}
"""

SCENARIOS = [
    ("forever-shaped client", []),
    ("no issecretvalue", ["MOCK_NO_SECRETS"]),
    ("no C_SpellBook / C_UnitAuras", ["MOCK_NO_SPELLBOOK", "MOCK_NO_AURAS"]),
]


def main():
    failed = 0
    for name, flags in SCENARIOS:
        try:
            lua = new_runtime(flags)
            lua.execute(CHECKS)
            r = lua.globals().RESULT
            ok = r.errorsCaptured == 0 and r.errorsRaised == 0
            status = "PASS" if ok else "FAIL"
            print(f"[{status}] {name}: decision={r.decision}, unresolved={r.unresolved}, "
                  f"probe text {r.probeTextLength} chars, combat UnitHealth={r.combatUnitHealth}, "
                  f"combat Judgement start={r.combatCooldown}")
            if not ok:
                failed += 1
                print("   first error:", r.firstError)
        except Exception as e:  # Lua error surfaced to Python
            failed += 1
            print(f"[FAIL] {name}: {e}")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
