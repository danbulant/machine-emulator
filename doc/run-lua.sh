#!/bin/bash
set -euo pipefail
FILTER_DIR="$(dirname "$(realpath "$0")")"
cd "$(dirname "$1")"
echo "$_REPLACE_KEY"
exec > >(tee stdout >> both) 2> >(tee stderr >> both)
trap 'exec >&- 2>&-; wait' EXIT
if [ -f spec ]; then
    lua5.4 "$FILTER_DIR/subst.lua" "$(basename "$1")" body.run.lua
    exec lua5.4 body.run.lua
else
    exec lua5.4 "$1"
fi
