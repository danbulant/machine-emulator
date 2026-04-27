#!/bin/bash
# No # docs:begin/end markers: this recipe wraps "cartesi-machine -i -- sh"
# in a heredoc to make the interactive session capturable, but the README
# prose teaches the user to run "cartesi-machine -i -- sh" *interactively*
# and type ls/exit at the prompt. Showing the heredoc would mislead readers
# about how to use interactive mode, so the displayed command stays
# hand-typed in README.md.template.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
{
    cartesi-machine -i -- sh 2>&1 <<'MACHINE'
ls /bin
exit
MACHINE
} > "$out" 2>&1
