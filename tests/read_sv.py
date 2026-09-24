"""Dev helper: prints sections of the addon's SavedVariables from the beta client.

Usage: python tests/read_sv.py probe.auraPaths probeCombat.events ...
With no arguments prints an overview. Noisy aura fields are hidden.
"""
import glob
import os
import sys

from lupa.lua51 import LuaRuntime

# Set WOW_WTF_DIR to read another client's WTF folder (default: the Forever beta).
WTF = os.environ.get("WOW_WTF_DIR", r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\WTF")


def find_sv():
    """The most recently written SavedVariables file across all accounts."""
    matches = glob.glob(os.path.join(WTF, "Account", "*", "SavedVariables", "NyteLytePaladinToolkit.lua"))
    if not matches:
        sys.exit("no NyteLytePaladinToolkit.lua under " + WTF)
    return max(matches, key=os.path.getmtime)

DUMP = r'''
function(t, maxdepth)
  local out = {}
  local skip = { isBossAura=1, isStealable=1, hideOnPartyFrames=1, timeMod=1, nameplateShowPersonal=1,
    nameplateShowAll=1, isTankRoleAura=1, isDPSRoleAura=1, isHealerRoleAura=1, isNameplateOnly=1,
    canActivePlayerDispel=1, isHarmful=1, points=1, isRaid=1, canApplyAura=1, isHelpful=1 }
  local function keys(t)
    local k = {}
    for x in pairs(t) do k[#k+1] = x end
    table.sort(k, function(a, b) return tostring(a) < tostring(b) end)
    return k
  end
  local function d(v, ind, depth)
    for _, k in ipairs(keys(v)) do
      local x = v[k]
      if not skip[k] then
        if type(x) == "table" then
          if depth >= maxdepth then
            out[#out+1] = ind .. tostring(k) .. " = {...}"
          else
            out[#out+1] = ind .. tostring(k) .. " = {"
            d(x, ind .. "  ", depth + 1)
            out[#out+1] = ind .. "}"
          end
        else
          out[#out+1] = ind .. tostring(k) .. " = " .. tostring(x)
        end
      end
    end
  end
  if type(t) ~= "table" then return tostring(t) end
  d(t, "", 0)
  return table.concat(out, "\n")
end
'''


def main():
    lua = LuaRuntime()
    with open(find_sv(), encoding="utf-8") as f:
        lua.execute(f.read())
    dump = lua.eval(DUMP)
    db = lua.globals().NyteLytePaladinToolkitDB
    paths = sys.argv[1:] or ["meta", "errors"]
    depth = 6
    for path in paths:
        if path.startswith("depth="):
            depth = int(path[6:])
            continue
        node = db
        for part in path.split("."):
            node = node[int(part)] if part.isdigit() else node[part]
            if node is None:
                break
        print("=== " + path)
        print(dump(node, depth) if node is not None else "nil")


if __name__ == "__main__":
    main()
