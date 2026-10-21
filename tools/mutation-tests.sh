#!/usr/bin/env bash
# tools/mutation-tests.sh
#
# Proves that tools/behavior-tests.lua is NOT VACUOUS.
#
# A test suite that passes on broken code proves nothing. This script breaks
# one protected behaviour at a time in a throwaway copy of the addon and
# asserts that the behaviour suite FAILS. If a mutation survives, the suite
# has a blind spot and this script fails.
#
# Each mutation lives in tools/mutations/<name>.py: it edits main.lua in the
# current working directory and asserts its own pattern still exists, so a
# mutation that no longer applies is reported as a failure rather than
# silently passing.
#
# Run from the repo root:
#     bash tools/mutation-tests.sh
#
# NOT shipped: tools/ is excluded from the release zip by tools/package.sh.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/cfct-mutation-$$"
LUA="${LUA:-lua5.1}"

PASS=0
FAIL=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# run_mutation <name> <description> <mutation-script>
run_mutation() {
    local name="$1"; shift
    local description="$1"; shift
    local mutation="$1"; shift

    local dir="$WORK/$name"
    rm -rf "$dir"
    mkdir -p "$dir"
    # Copy only what the behaviour suite needs: the addon sources, the tools
    # and the vendored libraries.
    cp -r "$REPO_ROOT/main.lua" "$REPO_ROOT/config.lua" "$REPO_ROOT/presets.lua" \
          "$REPO_ROOT/Presets" "$REPO_ROOT/Libs" "$REPO_ROOT/tools" "$dir/"

    if ! ( cd "$dir" && python3 "$mutation" ); then
        echo "  FAIL  $name -- the mutation did not apply (the source moved?)"
        FAIL=$((FAIL + 1))
        return
    fi

    local out
    out="$( cd "$dir" && "$LUA" tools/behavior-tests.lua 2>&1 )"
    local summary
    summary="$(printf '%s' "$out" | grep -oE 'checks=[0-9]+ failures=[0-9]+' | tail -1)"
    local failures
    failures="$(printf '%s' "$summary" | grep -oE 'failures=[0-9]+' | cut -d= -f2)"

    if [ -z "${failures:-}" ]; then
        echo "  FAIL  $name -- the suite did not report a summary (it crashed?)"
        printf '%s\n' "$out" | tail -5 | sed 's/^/          /'
        FAIL=$((FAIL + 1))
        return
    fi

    if [ "$failures" -gt 0 ]; then
        echo "  PASS  $name -- caught ($failures failing checks)"
        printf '%s\n' "$out" | grep -E '^\s*FAIL' | head -3 | sed 's/^/          /'
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $name -- SURVIVED: the suite still passed on broken code"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Mutation tests: does the behaviour suite actually catch regressions? ==="
echo ""

for mutation in "$REPO_ROOT"/tools/mutations/*.py; do
    name="$(basename "$mutation" .py)"
    run_mutation "$name" "$name" "$mutation"
done

echo ""
echo "=== mutation summary: $PASS caught, $FAIL survived ==="
if [ "$FAIL" -gt 0 ]; then
    echo "MUTATION TESTS FAILED -- the behaviour suite has a blind spot"
    exit 1
fi
echo "MUTATION TESTS PASSED -- every protected behaviour is covered"
exit 0
