#!/bin/bash
set -o pipefail

declare -A emit=([advance_state]=notice [inspect_state]=report)
reqfile=$(mktemp /tmp/calc.XXXXXX)
status="accept"
while :
do
  rollup $status > "$reqfile"
  request_type=$(jq -j .request_type < "$reqfile")
  status="reject"
  jq -j '.data.payload' < "$reqfile" | \
    hex --decode | \
      bc | \
        grep . | \
          tr -d '\\\n' | \
            hex --encode | \
              jq -R '{ payload: . }' | \
                rollup "${emit[$request_type]}" > /dev/null && \
                  status="accept"
done
rm "$reqfile"
