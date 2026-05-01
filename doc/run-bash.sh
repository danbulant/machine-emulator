#!/bin/bash
set -euo pipefail
cd "$(dirname "$1")"
echo "$_REPLACE_KEY"
exec > >(tee stdout >> both) 2> >(tee stderr >> both)
trap 'exec >&- 2>&-; wait' EXIT
exec bash "$1"
