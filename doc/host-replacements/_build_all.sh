#!/bin/bash
# Orchestrator: runs all doc-generation computations and caches outputs to $CACHE_DIR.
# Source this file (do not execute it directly).
# Usage: . "$(dirname "${BASH_SOURCE[0]}")/_build_all.sh"

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "Source this file; do not execute it." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$(cd "$SCRIPT_DIR/../target-replacements" && pwd)"
export CACHE_DIR="${CACHE_DIR:-/tmp/cartesi-docs-cache}"
mkdir -p "$CACHE_DIR"

if [ -f "$CACHE_DIR/all.done" ]; then
    return 0
fi

set -e

# ---- helpers ----------------------------------------------------------------

_strip() { sed -r 's/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g' | tr -d '\r'; }

# Run a script in $SCRIPT_DIR, combining stdout+stderr, stripping ANSI.
_run() {
    local script="$1"; shift
    (cd "$SCRIPT_DIR" && bash "$script" "$@" 2>&1) | _strip
}

# Run a target script (in target-replacements/).
_run_t() {
    local script="$1"; shift
    (cd "$TARGET_DIR" && bash "$script" "$@" 2>&1) | _strip
}

_trunc() { printf '%s' "${1:0:8}"; }

# Find first hash matching "<key>: <64-hex>" or '"<key>": "<64-hex>"'
_find_hash() {
    printf '%s' "$1" | grep -oP "\"*${2}\"*: \"*\\K[a-fA-F0-9]{64}" | head -1
}

# Find last Cycles: N value
_find_cycles() { printf '%s' "$1" | grep -oP 'Cycles: \K\d+' | tail -1; }

# Find first Lua/JSON field value: 'key = 0xHEX' or 'key = N'
_find_lua_val() {
    printf '%s' "$1" | grep -oP "\"*${2}\"* = \"*\\K(0x[0-9a-fA-F]+|-?\\d+)" | head -1
}

_all_hashes()  { printf '%s' "$1" | grep -oP '\d+: \K[a-fA-F0-9]{64}'; }
_all_cycles()  { printf '%s' "$1" | grep -oP 'Cycles: \K\d+'; }

# ---- config-dump-nothing (must run first: generates config-nothing-to-do.lua) ----

DUMP_NOTHING=$(_run machine.host.lua.config-dump-nothing.sh)
printf '%s\n' "$(_find_lua_val "$DUMP_NOTHING" "mvendorid")" > "$CACHE_DIR/host.lua.config-mvendorid.out"
printf '%s\n' "$(_find_lua_val "$DUMP_NOTHING" "mimpid")"    > "$CACHE_DIR/host.lua.config-mimpid.out"
printf '%s\n' "$(_find_lua_val "$DUMP_NOTHING" "marchid")"   > "$CACHE_DIR/host.lua.config-marchid.out"
# Generate config-nothing-to-do.lua used by state-hashes-lua and state-transition-dump-step.
printf '%s\n' "$DUMP_NOTHING" \
    | sed 's/machine_config = {/return {/' \
    | grep -v '^Cycles: 0$' \
    > "$SCRIPT_DIR/config-nothing-to-do.lua"

# ---- config-dump-ls-bin ----

_run machine.host.lua.config-dump-ls-bin.sh > "$CACHE_DIR/host.lua.config-dump-ls-bin.out"

# ---- cycles-limit-exec (needs config-nothing-to-do.lua in SCRIPT_DIR) ----

CYCLES_LIMIT_EXEC=$(_run machine.host.cmdline.cycles-limit-exec.sh)
printf '%s\n' "$CYCLES_LIMIT_EXEC" > "$CACHE_DIR/host.cmdline.cycles-limit-exec.out"

# ---- limit-exec ----

_run machine.host.cmdline.limit-exec.sh "$CYCLES_LIMIT_EXEC" > "$CACHE_DIR/host.cmdline.limit-exec.out"

# ---- rolling-ioctl-echo-loop ----

(cd "$SCRIPT_DIR" && bash machine.host.cmdline.rolling-ioctl-echo-loop.sh >/dev/null 2>&1)
CLIENT=$(cat "$SCRIPT_DIR/client.out" | _strip)
SERVER=$(cat "$SCRIPT_DIR/server.out" | _strip)
rm -f "$SCRIPT_DIR/client.out" "$SCRIPT_DIR/server.out"

printf '%s\n' "$SERVER" > "$CACHE_DIR/host.cmdline.rolling-ioctl-echo-loop-server.out"
# JS slice(0,5) = lines 1-5 (sed 1-indexed)
printf '%s\n' "$CLIENT" | sed -n '1,5p'   > "$CACHE_DIR/host.cmdline.rolling-ioctl-echo-loop-0client.out"
printf '%s\n' "$CLIENT" | sed -n '8,28p'  > "$CACHE_DIR/host.cmdline.rolling-ioctl-echo-loop-1client.out"
printf '%s\n' "$CLIENT" | sed -n '31,52p' > "$CACHE_DIR/host.cmdline.rolling-ioctl-echo-loop-2client.out"
printf '%s\n' "$CLIENT" | sed -n '54,63p' > "$CACHE_DIR/host.cmdline.rolling-ioctl-echo-loop-3client.out"
i=0
while IFS= read -r h; do
    printf '%s\n' "$(_trunc "$h")" > "$CACHE_DIR/host.cmdline.rolling-ioctl-echo-loop-hashes${i}.out"
    i=$((i+1))
done < <(_all_hashes "$CLIENT")
i=0
while IFS= read -r c; do
    printf '%s\n' "$c" > "$CACHE_DIR/host.cmdline.rolling-ioctl-echo-loop-cycles${i}.out"
    i=$((i+1))
done < <(_all_cycles "$CLIENT")

# ---- rolling-calc-template ----

(cd "$SCRIPT_DIR" && bash machine.host.cmdline.rolling-calc-template.sh >/dev/null 2>&1)
cat "$SCRIPT_DIR/template.out" | _strip > "$CACHE_DIR/host.cmdline.rolling-calc-template.template.out"
cat "$SCRIPT_DIR/server.out"   | _strip > "$CACHE_DIR/host.cmdline.rolling-calc-template.server.out"
cat "$SCRIPT_DIR/client.out"   | _strip > "$CACHE_DIR/host.cmdline.rolling-calc-template.client.out"
rm -f "$SCRIPT_DIR/template.out" "$SCRIPT_DIR/server.out" "$SCRIPT_DIR/client.out"
cat "$SCRIPT_DIR/calc.sh" > "$CACHE_DIR/host.cmdline.rolling-calc-sh.out"

# ---- remote ----

(cd "$SCRIPT_DIR" && bash machine.host.cmdline.remote.sh >/dev/null 2>&1)
cat "$SCRIPT_DIR/client.out" | _strip > "$CACHE_DIR/host.cmdline.remote-client.out"
cat "$SCRIPT_DIR/server.out" | _strip > "$CACHE_DIR/host.cmdline.remote-server.out"
rm -f "$SCRIPT_DIR/client.out" "$SCRIPT_DIR/server.out"

# ---- remote-begin ----

(cd "$SCRIPT_DIR" && bash machine.host.cmdline.remote-begin.sh >/dev/null 2>&1)
cat "$SCRIPT_DIR/client.out" | _strip > "$CACHE_DIR/host.cmdline.remote-begin-client.out"
rm -f "$SCRIPT_DIR/client.out" "$SCRIPT_DIR/server.out"

# ---- remote-end ----

(cd "$SCRIPT_DIR" && bash machine.host.cmdline.remote-end.sh >/dev/null 2>&1)
cat "$SCRIPT_DIR/client.out" | _strip > "$CACHE_DIR/host.cmdline.remote-end-client.out"
cat "$SCRIPT_DIR/server.out" | _strip > "$CACHE_DIR/host.cmdline.remote-begin-end-server.out"
rm -f "$SCRIPT_DIR/client.out" "$SCRIPT_DIR/server.out"

# ---- cmdline basics ----

_run machine.host.cmdline.interactive-ls.sh   > "$CACHE_DIR/host.cmdline.interactive-ls.out"
_run machine.host.cmdline.ls.sh               > "$CACHE_DIR/host.cmdline.ls.out"
_run machine.host.cmdline.nothing.sh          > "$CACHE_DIR/host.cmdline.nothing.out"
_run machine.host.cmdline.flash.sh            > "$CACHE_DIR/host.cmdline.flash.out"
_run machine.host.cmdline.persistent-flash.sh > "$CACHE_DIR/host.cmdline.persistent-flash.out"

# ---- state hashes ----

STATE_HASHES_LIMIT=$(_run machine.host.cmdline.state-hashes-limit-exec.sh "$CYCLES_LIMIT_EXEC")
printf '%s\n' "$STATE_HASHES_LIMIT" > "$CACHE_DIR/host.cmdline.state-hashes-limit-exec.out"
printf '%s\n' "$(_trunc "$(_find_hash "$STATE_HASHES_LIMIT" "0")")" \
    > "$CACHE_DIR/host.cmdline.state-hashes-initial.out"
printf '%s\n' "$(_trunc "$(_find_hash "$STATE_HASHES_LIMIT" "$CYCLES_LIMIT_EXEC")")" \
    > "$CACHE_DIR/host.cmdline.state-hashes-final-limit-exec.out"

STATE_HASHES_NO_LIMIT=$(_run machine.host.cmdline.state-hashes-no-limit.sh)
printf '%s\n' "$STATE_HASHES_NO_LIMIT" > "$CACHE_DIR/host.cmdline.state-hashes-no-limit.out"
CYCLES_NO_LIMIT=$(_find_cycles "$STATE_HASHES_NO_LIMIT")
printf '%s\n' "$CYCLES_NO_LIMIT" > "$CACHE_DIR/host.cmdline.state-hashes-cycles-no-limit.out"
printf '%s\n' "$(_trunc "$(_find_hash "$STATE_HASHES_NO_LIMIT" "$CYCLES_NO_LIMIT")")" \
    > "$CACHE_DIR/host.cmdline.state-hashes-final-no-limit.out"

# ---- persistent machine ----

_run machine.host.cmdline.persistent-machine.sh     "$CYCLES_LIMIT_EXEC" > "$CACHE_DIR/host.cmdline.persistent-machine.out"
_run machine.host.cmdline.persistent-stored-hash.sh "$CYCLES_LIMIT_EXEC" > "$CACHE_DIR/host.cmdline.persistent-stored-hash.out"

# ---- templates ----

_run machine.host.cmdline.templates-run.sh   > "$CACHE_DIR/host.cmdline.templates-run.out"
_run machine.host.cmdline.templates-store.sh > "$CACHE_DIR/host.cmdline.templates-store.out"
TEMPLATES_HASH=$(_run machine.host.cmdline.templates-hash.sh)
printf '%s\n' "$TEMPLATES_HASH"              > "$CACHE_DIR/host.cmdline.templates-hash.out"
printf '%s\n' "$(_trunc "$TEMPLATES_HASH")"  > "$CACHE_DIR/host.cmdline.templates-trunc-hash.out"

# ---- proofs ----

_run machine.host.cmdline.proofs-pristine-run.sh  > "$CACHE_DIR/host.cmdline.proofs-pristine-run.out"
_run machine.host.cmdline.proofs-pristine-json.sh > "$CACHE_DIR/host.cmdline.proofs-pristine-json.out"

PROOFS_INPUT=$(_run machine.host.cmdline.proofs-input-json.sh)
printf '%s\n' "$PROOFS_INPUT" > "$CACHE_DIR/host.cmdline.proofs-input-json.out"
printf '%s\n' "$(_trunc "$(_find_hash "$PROOFS_INPUT" "root_hash")")" \
    > "$CACHE_DIR/host.cmdline.proofs-input-roothash.out"

PROOFS_OUTPUT_RUN=$(_run machine.host.cmdline.proofs-output-run.sh)
printf '%s\n' "$PROOFS_OUTPUT_RUN" > "$CACHE_DIR/host.cmdline.proofs-output-run.out"
PROOFS_OUTPUT_RUN_CYCLES=$(_find_cycles "$PROOFS_OUTPUT_RUN")

PROOFS_OUTPUT=$(_run machine.host.cmdline.proofs-output-json.sh)
printf '%s\n' "$PROOFS_OUTPUT" > "$CACHE_DIR/host.cmdline.proofs-output-json.out"
printf '%s\n' "$(_trunc "$(_find_hash "$PROOFS_OUTPUT" "root_hash")")" \
    > "$CACHE_DIR/host.cmdline.proofs-output-roothash.out"

# ---- rarely ----

_run machine.host.cmdline.rarely-append-bootargs-loglevel.sh  > "$CACHE_DIR/host.cmdline.rarely-append-bootargs-loglevel.out"
_run machine.host.cmdline.rarely-id.sh                        > "$CACHE_DIR/host.cmdline.rarely-id.out"
_run machine.host.cmdline.rarely-append-bootargs-single-id.sh > "$CACHE_DIR/host.cmdline.rarely-append-bootargs-single-id.out"
_run machine.host.cmdline.default-rom-bootargs.sh             > "$CACHE_DIR/host.cmdline.default-rom-bootargs.out"

PERIODIC_INITIAL_CYCLE=$((PROOFS_OUTPUT_RUN_CYCLES - 10))
printf '%s\n' "$PERIODIC_INITIAL_CYCLE" > "$CACHE_DIR/host.cmdline.rarely-periodic-initial-cycle.out"
_run machine.host.cmdline.rarely-periodic-hashes.sh "$PERIODIC_INITIAL_CYCLE" > "$CACHE_DIR/host.cmdline.rarely-periodic-hashes.out"
_run machine.host.cmdline.rarely-step.sh "$CYCLES_LIMIT_EXEC"                 > "$CACHE_DIR/host.cmdline.rarely-step.out"

# ---- lua ----

_run machine.host.lua.state-hashes-lua.sh "config-nothing-to-do"                       > "$CACHE_DIR/host.lua.state-hashes-lua.out"
_run machine.host.lua.state-hashes-utility.sh                                           > "$CACHE_DIR/host.lua.state-hashes-utility.out"
_run machine.host.lua.state-transition-dump-step.sh "config-nothing-to-do" "$CYCLES_LIMIT_EXEC" > "$CACHE_DIR/host.lua.state-transition-dump-step.out"

rm -f "$SCRIPT_DIR/config-nothing-to-do.lua"

# ---- lua remote ----

(cd "$SCRIPT_DIR" && bash machine.host.lua.remote.sh >/dev/null 2>&1)
cat "$SCRIPT_DIR/client.out" | _strip > "$CACHE_DIR/host.lua.remote-client.out"
cat "$SCRIPT_DIR/server.out" | _strip > "$CACHE_DIR/host.lua.remote-server.out"
rm -f "$SCRIPT_DIR/client.out" "$SCRIPT_DIR/server.out"

# ---- target ----

_run_t machine.target.linux.interactive-ls.sh > "$CACHE_DIR/target.linux.interactive-ls.out"
_run_t machine.target.linux.hello-cpp.sh      > "$CACHE_DIR/target.linux.hello-cpp.out"
_run_t machine.target.architecture.dtc.sh     > "$CACHE_DIR/target.architecture.dtc.out"

# ---- done ----

touch "$CACHE_DIR/all.done"
