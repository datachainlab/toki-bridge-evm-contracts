#!/bin/sh -e

HOST_REGISTRY=${HOST_REGISTRY:-host:5000/dind}

if [ -z $1 ]; then
  echo "$0 <image>..."
  exit 1
fi
IMAGES="$@"

for i in $IMAGES; do
  echo "pull $i..."
  set +e
  docker inspect $i > /dev/null
  r=$?
  set -e
  if [ $r -eq 0 ]; then
    docker image ls $i | tail -1
  else
    echo docker pull -q $HOST_REGISTRY/$i...
    docker pull -q $HOST_REGISTRY/$i
    docker tag     $HOST_REGISTRY/$i $i
  fi
done
