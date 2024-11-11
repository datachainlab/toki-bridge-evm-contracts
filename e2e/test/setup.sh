#!/bin/sh

if [ "x$1" = "x" ]; then
  echo "$0 <input parameter file>"
  exit
fi
npx ts-node src/setup.ts "$1"
