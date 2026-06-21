#!/bin/bash
set -euo pipefail
: "${REPLACE_KEY:?}" "${REPLACE_CACHE_DIR:?}"
REPLACE_DIR="$(dirname "$(realpath "$0")")"
cd "$REPLACE_CACHE_DIR/$REPLACE_KEY"
echo "$REPLACE_KEY"
: > both
exec > >(tee stdout >> both) 2> >(tee stderr >> both)
# Stamp the stream markers with an end-of-run mtime after tee has flushed, so the ordering edge a
# downstream block hangs off (cache/<key>/both) always advances and stays newer than this block's
# artifacts, even when the captured stream is empty. Without it an empty marker keeps its start-of-run
# mtime and an incremental parallel build can order a consumer ahead of the artifacts it globs.
trap 'exec >&- 2>&-; wait; touch both stdout stderr 2>/dev/null || true' EXIT
if [ -f spec ]; then
    lua5.4 "$REPLACE_DIR/vars.lua" body.lua body.run.lua
    body=body.run.lua
else
    body=body.lua
fi
status=0
lua5.4 "$body" || status=$?
if [ "$status" -ne 0 ]; then exit "$status"; fi
while IFS= read -r artifact; do
    [ -z "$artifact" ] && continue
    if [ ! -e "$artifact" ]; then
        echo "missing declared output: $artifact" >&2
        status=1
    fi
done < outputs
exit "$status"
