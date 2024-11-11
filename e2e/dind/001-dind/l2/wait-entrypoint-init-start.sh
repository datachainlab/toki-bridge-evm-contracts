#!/bin/sh -e

TOKI_DIR=$(dirname $0)
STATUS_FILE=${TOKI_DIR}/status.d/entrypoint-init-start

SLEEP=${1:-3}

while true; do
  echo "--- L2 $(date) waiting entrypoint start..."
  echo -n '  '; uptime
  if [ -e $STATUS_FILE ]; then
    break
  fi
  sleep $SLEEP
done
echo '--- L2 entrypoint started'
