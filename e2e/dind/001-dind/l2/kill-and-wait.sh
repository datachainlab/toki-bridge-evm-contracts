#!/bin/sh -e

if [ -z $2 ]; then
  echo "$0 <signal> <pid>"
  exit 1
fi

SIG=$1; shift
PID=$1; shift

ps -p $PID
kill -$SIG $PID

while $(kill -0 $PID 2>/dev/null); do
  sleep 1
done
