#!/bin/sh -e

TOKI_DIR=$(dirname $0)
STATUS_FILE=${TOKI_DIR}/status.d/entrypoint-init-stop

SLEEP=${1:-3}

while true; do
  echo 'waiting entrypoint SIGUSR1 done...'
  if [ -e $STATUS_FILE ]; then
    break
  fi
  sleep $SLEEP
done
echo 'entrypoint SIGUSR1 is done'
