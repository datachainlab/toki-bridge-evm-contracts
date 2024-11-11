#!/bin/sh -e

if [ -z $2 ]; then
  echo "$0 <remote registry> <image>..."
  exit 1
fi

LOCAL_REGISTRY="localhost:5000/dind"
REMOTE_REGISTRY=${1:-docker.io}; shift
IMAGES="$@"

for i in $IMAGES; do
  if [ -z $(docker image ls -q $i) ]; then
    docker pull $REMOTE_REGISTRY/$i
  fi
  docker tag $i $LOCAL_REGISTRY/$i
  docker push $LOCAL_REGISTRY/$i
done
