#!/bin/sh
# Symlinks this repo into the WoW AddOns folder as "PaladinKit".
# Usage: WOW_ADDONS_DIR="/path/to/Interface/AddOns" tools/install.sh [--copy]
# On Windows prefer tools/install.ps1 (makes a junction; no admin needed).
set -e
repo=$(cd "$(dirname "$0")/.." && pwd)
addons=${WOW_ADDONS_DIR:-"/c/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns"}
[ -d "$addons" ] || { echo "AddOns folder not found: $addons (set WOW_ADDONS_DIR)"; exit 1; }
target="$addons/PaladinKit"

if [ -L "$target" ]; then
	rm "$target"
elif [ -e "$target" ]; then
	echo "$target exists and is a real folder. Move or delete it yourself, then re-run."
	exit 1
fi

if [ "$1" = "--copy" ]; then
	mkdir -p "$target"
	for f in "$repo"/*; do
		case "$(basename "$f")" in tests|tools|docs) ;; *) cp -R "$f" "$target/" ;; esac
	done
	echo "Copied PaladinKit to $target"
else
	ln -s "$repo" "$target"
	echo "Linked $target -> $repo"
fi
