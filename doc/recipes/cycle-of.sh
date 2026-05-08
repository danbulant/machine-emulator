#!/bin/bash
# Print the cycle count from the Cycles: line following the Nth match of PATTERN.
# Usage: cycle-of.sh PATTERN [N]   (N defaults to 1)
awk -v pat="$1" -v n="${2:-1}" '
    $0 ~ pat { if (++i == n) { waiting = 1; next } }
    waiting && $1 == "Cycles:" { print $2; exit }
'
