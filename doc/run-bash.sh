#!/bin/bash
set -euo pipefail
FILTER_DIR="$(dirname "$(realpath "$0")")"
cd "$(dirname "$1")"
echo "$_REPLACE_KEY"
exec > >(tee stdout >> both) 2> >(tee stderr >> both)
trap 'exec >&- 2>&-; wait' EXIT
if [ -f spec ]; then
    lua5.4 "$FILTER_DIR/subst.lua" "$(basename "$1")" body.run.sh
    exec bash body.run.sh
else
    exec bash "$1"
fi
