#!/bin/sh -e

if [ -z $1 ]; then
  echo "$0 <name>"
  exit 1
fi

NAME=$1; shift

id=$(docker ps -f "name=$NAME" -q)
if [ ! -z $id ]; then
  docker stop -t 300 $id
fi
