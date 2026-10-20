#!/usr/bin/env bash
# tools/package.sh -- deterministic CurseForge release package for ClassicFCT.
#
# Builds a single-folder zip (ClassicFCT/<files>) from an EXPLICIT manifest.
# Nothing is globbed, so no workspace path (desks/, bench/, classroom/,
# CAIRN.md, workshop.md, hands-up.md, .git/, .vscode/, ...) can leak into a
# release by accident.
#
# Usage:
#   tools/package.sh [output-dir]
#
# Output:
#   <output-dir>/ClassicFCT-<version>.zip   (default: dist/)
#   <output-dir>/ClassicFCT-<version>.zip.sha256
#
# Requires: bash, zip, sha256sum.  Run from the repo root or anywhere
# (the script resolves the repo root from its own location).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${1:-$REPO_ROOT/dist}"
ADDON_DIR="ClassicFCT"

# ----------------------------------------------------------------------------
# 1. Version: read from a .toc so there is one source of truth.
# ----------------------------------------------------------------------------
VERSION="unknown"
for toc in ClassicFCT-Vanilla.toc ClassicFCT-TBC.toc ClassicFCT-Titan.toc \
           ClassicFCT-Forever.toc ClassicFCT-Mainline.toc; do
    if [[ ! -f "$toc" ]]; then
        echo "ERROR: missing toc: $toc" >&2
        exit 1
    fi
    v="$(sed -n 's/^## Version:[[:space:]]*//p' "$toc" | head -1)"
    if [[ -z "$v" ]]; then
        echo "ERROR: no '## Version:' in $toc" >&2
        exit 1
    fi
    if [[ "$v" != "$VERSION" && "$VERSION" != "unknown" ]]; then
        echo "ERROR: version mismatch: $toc has '$v', expected '$VERSION'" >&2
        exit 1
    fi
    VERSION="$v"
done

# ----------------------------------------------------------------------------
# 2. The manifest. Every shipped file is listed. Nothing else ships.
#    Order is fixed so the zip is reproducible.
# ----------------------------------------------------------------------------
MANIFEST=(
    # -- client manifests --
    "ClassicFCT-Vanilla.toc"
    "ClassicFCT-TBC.toc"
    "ClassicFCT-Titan.toc"
    "ClassicFCT-Forever.toc"
    "ClassicFCT-Mainline.toc"
    # -- addon code --
    "main.lua"
    "config.lua"
    "presets.lua"
    # -- vendored libraries --
    "Libs/libs.xml"
    "Libs/LibStub/LibStub.lua"
    "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua"
    "Libs/CallbackHandler-1.0/CallbackHandler-1.0.xml"
    "Libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua"
    "Libs/LibSharedMedia-3.0/lib.xml"
    # -- locales --
    "Locales/locales.lua"
    "Locales/locales.xml"
    "Locales/enUS.lua"
    "Locales/deDE.lua"
    "Locales/ruRU.lua"
    "Locales/frFR.lua"
    "Locales/esES.lua"
    "Locales/esMX.lua"
    "Locales/itIT.lua"
    "Locales/ptBR.lua"
    "Locales/zhCN.lua"
    "Locales/zhTW.lua"
    "Locales/koKR.lua"
    # -- presets --
    "Presets/presets.xml"
    "Presets/Classic.lua"
    "Presets/ClassicPlus.lua"
    "Presets/MoP.lua"
    # -- project page / legal --
    "README.md"
    "CHANGELOG.txt"
    "LICENSE"
    "LICENSE-LGPL-2.1.txt"
    "THIRD-PARTY-NOTICES.md"
)

# ----------------------------------------------------------------------------
# 3. Preflight: every manifest entry must exist, and no workspace path may
#    appear in the manifest.
# ----------------------------------------------------------------------------
FORBIDDEN=( "desks/" "bench/" "classroom/" "CAIRN.md" "workshop.md" "hands-up.md"
            "AGENTS.md" ".git/" ".vscode/" ".luarc.json" ".gitignore" ".gitattributes" )

missing=0
for f in "${MANIFEST[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: manifest file missing: $f" >&2
        missing=1
    fi
done
for f in "${MANIFEST[@]}"; do
    for bad in "${FORBIDDEN[@]}"; do
        if [[ "$f" == "$bad"* ]]; then
            echo "ERROR: workspace path in manifest: $f" >&2
            missing=1
        fi
    done
done
[[ $missing -eq 0 ]] || exit 1

# Every .toc and .xml load-list entry must resolve inside the package.
# .toc entries are relative to the repo root; .xml entries are relative to
# the directory that contains the .xml file.
while IFS= read -r ref; do
    if [[ ! -f "$ref" ]]; then
        echo "ERROR: load-list reference does not resolve: $ref" >&2
        missing=1
    fi
done < <(
    for toc in ClassicFCT-Vanilla.toc ClassicFCT-TBC.toc ClassicFCT-Titan.toc \
               ClassicFCT-Forever.toc ClassicFCT-Mainline.toc; do
        sed -n 's/^[[:space:]]*\([^#<].*\)$/\1/p' "$toc" | sed 's/\\/\//g'
    done
    for xml in Locales/locales.xml Presets/presets.xml; do
        base="$(dirname "$xml")"
        sed -n 's/.*file="\([^"]*\)".*/\1/p' "$xml" | sed 's/\\/\//g' | sed "s|^|$base/|"
    done
)

# ----------------------------------------------------------------------------
# 4. Stage and zip. Fixed timestamps + sorted order => byte-identical output
#    for identical input.
# ----------------------------------------------------------------------------
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/$ADDON_DIR"
for f in "${MANIFEST[@]}"; do
    mkdir -p "$STAGE/$ADDON_DIR/$(dirname "$f")"
    cp -p "$f" "$STAGE/$ADDON_DIR/$f"
done

# Normalize mtimes so the zip is reproducible (2020-01-01T00:00:00Z).
find "$STAGE" -exec touch -h -d "2020-01-01T00:00:00Z" {} +

mkdir -p "$OUT_DIR"
ZIP="$OUT_DIR/${ADDON_DIR}-${VERSION}.zip"
rm -f "$ZIP"

# -X: drop extra file attributes; -r: recurse; sorted input order.
( cd "$STAGE" && find "$ADDON_DIR" -type f | LC_ALL=C sort | zip -X -q "$ZIP" -@ )

# ----------------------------------------------------------------------------
# 5. Verify the built package: exact file set, single top-level folder,
#    no workspace paths.
# ----------------------------------------------------------------------------
listed="$(unzip -Z1 "$ZIP" | LC_ALL=C sort)"
expected="$(printf '%s\n' "${MANIFEST[@]}" | sed "s|^|$ADDON_DIR/|" | LC_ALL=C sort)"

if [[ "$listed" != "$expected" ]]; then
    echo "ERROR: package contents do not match the manifest" >&2
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$listed") >&2 || true
    exit 1
fi

top_levels="$(unzip -Z1 "$ZIP" | cut -d/ -f1 | LC_ALL=C sort -u)"
if [[ "$top_levels" != "$ADDON_DIR" ]]; then
    echo "ERROR: package must contain exactly one top-level folder ('$ADDON_DIR'), got: $top_levels" >&2
    exit 1
fi

if unzip -Z1 "$ZIP" | grep -qE '(^|/)(desks|bench|classroom|\.git|\.vscode)/'; then
    echo "ERROR: workspace path present in package" >&2
    exit 1
fi

# ----------------------------------------------------------------------------
# 6. Checksum + summary.
# ----------------------------------------------------------------------------
( cd "$OUT_DIR" && sha256sum "$(basename "$ZIP")" > "$(basename "$ZIP").sha256" )

echo "PACKAGED $ZIP"
echo "  version : $VERSION"
echo "  files   : $(unzip -Z1 "$ZIP" | wc -l | tr -d ' ')"
echo "  sha256  : $(cut -d' ' -f1 < "$ZIP.sha256")"
