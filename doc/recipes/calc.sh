#!/bin/bash
set -o pipefail

reqfile=$(mktemp /tmp/calc.XXXXXX)
status="accept"
while :
do
  rollup $status > "$reqfile"
  request_type=$(jq -j .request_type < "$reqfile")
  status="reject"
  if [ "$request_type" = "advance_state" ];
  then
    jq -j '.data.payload' < "$reqfile" | \
      hex --decode | \
        bc | \
          grep . | \
            tr -d '\\\n' | \
              hex --encode | \
                jq -R '{ payload: . }' | \
                  rollup notice > /dev/null && \
                    status="accept"
  fi
done
rm "$reqfile"
