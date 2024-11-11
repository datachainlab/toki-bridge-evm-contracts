#!/bin/sh -e

if [ -z $2 ]; then
  echo "$0 <src e2e dir> <outdir>"
  exit 1
fi
E2E_DIR=$(pwd)/$1; shift
OUTDIR=$(pwd)/$1; shift
cd $(dirname $0)

mkdir_cp() {
  from=$1
  to=$2
  mkdir -p $(dirname $to)
  if [ -d $from ]; then
    echo cp -r $from $(dirname $to)/
    cp -r $from $(dirname $to)/
  else
    echo cp -r $from $to
    cp -r $from $to
  fi
}

while read f; do
  #echo $f
  mkdir_cp ${E2E_DIR}/$f ${OUTDIR}/$f
done <<EOS
Makefile
relayer/Makefile
relayer/scripts/render-handshake.sh
relayer/scripts/config/path.json
relayer/scripts/config/ibc-0.template.json
relayer/scripts/config/ibc-1.template.json
relayer/scripts/render.sh
relayer/scripts/handshake.sh
test
EOS
