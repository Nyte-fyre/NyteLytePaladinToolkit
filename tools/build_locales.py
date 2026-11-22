"""Build Locales/<code>.lua from tools/translations.tsv.

translations.tsv has one row per English string (first column, exactly as in
L["..."]) and one column per language. This script checks it against the code
(every key the addon uses, no stale rows, the same %s / %d placeholders in the
same order) and writes one Lua file per language.

  python tools/build_locales.py           write Locales/*.lua
  python tools/build_locales.py --check   exit 1 if the files are stale or a row is wrong
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import locale_keys  # noqa: E402

ROOT = locale_keys.ROOT
TSV = os.path.join(ROOT, "tools", "translations.tsv")
# esES also serves Latin American Spanish clients.
ALSO = {"esES": ["esMX"]}
PLACEHOLDER = re.compile(r"%[sd]")


def read_rows():
    lines = open(TSV, encoding="utf-8").read().replace("\r\n", "\n").split("\n")
    header = lines[0].split("\t")
    rows = []
    for n, line in enumerate(lines[1:], start=2):
        if line == "":
            continue
        cols = line.split("\t")
        if len(cols) != len(header):
            raise SystemExit("translations.tsv line %d: %d columns, expected %d" % (n, len(cols), len(header)))
        rows.append((n, cols))
    return header, rows


def problems(header, rows, keys):
    out = []
    seen = set()
    for n, cols in rows:
        en = cols[0]
        if en in seen:
            out.append("line %d: duplicate row %r" % (n, en))
        seen.add(en)
        if en not in keys:
            out.append("line %d: %r is no longer used by the addon" % (n, en))
        want = PLACEHOLDER.findall(en)
        for code, text in zip(header[1:], cols[1:]):
            if text.strip() == "":
                out.append("line %d %s: empty translation" % (n, code))
            elif PLACEHOLDER.findall(text) != want:
                out.append("line %d %s: placeholders %s, English has %s" % (n, code, PLACEHOLDER.findall(text), want))
            if text.count("|c") != en.count("|c") or text.count("|r") != en.count("|r"):
                out.append("line %d %s: color codes differ from English" % (n, code))
    for k in keys:
        if k not in seen:
            out.append("missing row for %r" % k)
    return out


def render(code, header, rows):
    col = header.index(code)
    codes = [code] + ALSO.get(code, [])
    cond = " or ".join('PK.NewLocale("%s")' % c for c in codes)
    out = [
        "-- %s translation of Nyte Lyte's Paladin Toolkit." % "/".join(codes),
        "-- Generated from tools/translations.tsv by tools/build_locales.py; edit the TSV, not this file.",
        "local _, PK = ...",
        "local L = %s" % cond,
        "if not L then",
        "\treturn",
        "end",
        "",
    ]
    for _, cols in rows:
        out.append('L["%s"] = "%s"' % (cols[0], cols[col]))
    return "\n".join(out) + "\n"


def main():
    header, rows = read_rows()
    keys = locale_keys.collect()
    bad = problems(header, rows, keys)
    if bad:
        print("translations.tsv has problems:")
        for b in bad:
            print("  " + b)
        return 1
    stale = []
    for code in header[1:]:
        path = os.path.join(ROOT, "Locales", code + ".lua")
        text = render(code, header, rows)
        cur = open(path, encoding="utf-8").read().replace("\r\n", "\n") if os.path.exists(path) else ""
        if cur != text:
            if "--check" in sys.argv:
                stale.append(code)
            else:
                open(path, "w", encoding="utf-8", newline="\n").write(text)
    if stale:
        print("Locales out of date (%s): run python tools/build_locales.py" % ", ".join(stale))
        return 1
    verb = "checked" if "--check" in sys.argv else "wrote"
    print("%s %d languages x %d strings" % (verb, len(header) - 1, len(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
