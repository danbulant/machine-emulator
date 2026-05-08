#!/bin/bash
set -euo pipefail
: "${REPLACE_KEY:?}" "${REPLACE_CACHE_DIR:?}"
REPLACE_DIR="$(dirname "$(realpath "$0")")"
cd "$REPLACE_CACHE_DIR/$REPLACE_KEY"
echo "$REPLACE_KEY"
: > both
exec > >(tee stdout >> both) 2> >(tee stderr >> both)
trap 'exec >&- 2>&-; wait' EXIT
if [ -f spec ]; then
    lua5.4 "$REPLACE_DIR/subst.lua" body.sh body.run.sh
    exec bash body.run.sh
else
    exec bash body.sh
fi
