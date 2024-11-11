#!/bin/sh -e

if [ -z $2 ]; then
  echo "$0 <src e2e dir> <outdir>"
  exit 1
fi
E2E_DIR=$(pwd)/$1; shift
OUTDIR=$(pwd)/$1; shift
cd $(dirname $0)

TBL_SUBDIR=$(make --no-print-directory -sC ${E2E_DIR} echo-toki-bridge-local-dir)
TBL_DIR=${E2E_DIR}/${TBL_SUBDIR}
BSC_SUBDIR=development/chains/bsc

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
${TBL_SUBDIR}/development/env.mk
EOS

while read f; do
  echo $f
  mkdir_cp ${TBL_DIR}/${BSC_SUBDIR}/$f ${OUTDIR}/${TBL_SUBDIR}/${BSC_SUBDIR}/$f
done <<EOS
Makefile
Dockerfile
scripts
docker-compose.simple.yml
.env
config
init-holders
EOS
