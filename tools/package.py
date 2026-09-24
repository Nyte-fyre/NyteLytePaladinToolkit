"""Builds the release zip: dist/NyteLytePaladinToolkit-<version>.zip

The zip holds one top-level folder, NyteLytePaladinToolkit/, with only the
files the game needs (same exclusions as .pkgmeta: no tests, tools, docs,
CLAUDE.md or dotfiles). Upload it to CurseForge or a GitHub release.

Run: python tools/package.py            (version from the TOC)
     python tools/package.py 0.5.0      (override the version in the file name)
"""
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = "NyteLytePaladinToolkit"
INCLUDE_DIRS = ["Core", "Logic", "Data", "Services", "UI", "Modules", "Locales"]
INCLUDE_FILES = [ADDON + ".toc", "Bindings.xml", "LICENSE", "README.md", "CHANGELOG.md"]


def toc_version():
    with open(os.path.join(ROOT, ADDON + ".toc"), encoding="utf-8") as f:
        m = re.search(r"^## Version:\s*(\S+)", f.read(), re.M)
    return m.group(1) if m else "dev"


def toc_files():
    with open(os.path.join(ROOT, ADDON + ".toc"), encoding="utf-8") as f:
        return [line.strip().replace("\\", "/") for line in f
                if line.strip() and not line.startswith("#")]


def main():
    version = sys.argv[1] if len(sys.argv) > 1 else toc_version()
    files = list(INCLUDE_FILES)
    for d in INCLUDE_DIRS:
        base = os.path.join(ROOT, d)
        for dirpath, _, names in os.walk(base):
            for n in sorted(names):
                if n.endswith((".lua", ".xml")):
                    files.append(os.path.relpath(os.path.join(dirpath, n), ROOT).replace("\\", "/"))
    missing = [f for f in toc_files() if f not in files]
    if missing:
        sys.exit("TOC lists files that aren't packaged: " + ", ".join(missing))
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    out = os.path.join(ROOT, "dist", f"{ADDON}-{version}.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in files:
            z.write(os.path.join(ROOT, rel), f"{ADDON}/{rel}")
    print(f"wrote {out} ({len(files)} files)")


if __name__ == "__main__":
    main()
