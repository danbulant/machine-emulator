# Common preamble for cache.*.sh scripts. Set any custom outs/reads arrays
# BEFORE sourcing, so lib.sh can emit the .d file at source-time:
#
#   #!/bin/bash
#   reads=("$CACHE_DIR/dep.out")                  # optional, default ()
#   outs=("$CACHE_DIR/a.out" "$CACHE_DIR/b.out")  # optional, default single
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
#   <body uses $out (= ${outs[0]}), $HERE>
#
# When the caller's argv contains --emit-deps, lib.sh prints a self-contained
# make rule (gcc -MMD style) to stdout and exits 0 before the body runs.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
_key="$(basename "${BASH_SOURCE[1]}")"
_key="${_key#cache.}"
_key="${_key%.sh}"

declare -p outs  >/dev/null 2>&1 || outs=("$CACHE_DIR/$_key.out")
declare -p reads >/dev/null 2>&1 || reads=()
out="${outs[0]}"

for _a in "$@"; do
    [[ "$_a" == "--emit-deps" ]] || continue
    _script="$(basename "${BASH_SOURCE[1]}")"
    _rs="${reads[*]+${reads[*]} }"
    if (( ${#outs[@]} == 1 )); then
        printf '%s: %s lib.sh %s\n' "${outs[0]}" "$_script" "$_rs"
    else
        printf '%s &: %s lib.sh %s| %s\n\tbash $<\n' \
            "${outs[*]}" "$_script" "$_rs" "$CACHE_DIR"
    fi
    exit 0
done
unset _a _key

cd "$HERE"
