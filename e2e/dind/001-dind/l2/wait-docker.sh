#!/bin/sh -e

SLEEP=${1:-10}

while true; do
  echo 'waiting docker daemon...'
  if docker info > /dev/null 2>&1; then
    break
  fi
  sleep $SLEEP
done

exit 0
