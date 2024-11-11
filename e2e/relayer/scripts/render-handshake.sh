#!/bin/sh

SCRIPT_DIR=$(dirname $0)

if [ -z $2 ]; then
  echo "$0 <ibc0 handler address> <ibc1 handler address> [outdir]"
  exit 1
fi
IBC0_HANDLER=$1
IBC1_HANDLER=$2
OUTDIR=$3

set -eu

if [ -z $OUTDIR ]; then
  OUTDIR=$(mktemp -d)
elif [ ! -d $OUTDIR ]; then
  mkdir -p $OUTDIR
fi

cp $SCRIPT_DIR/config/path.json $OUTDIR/
sh $SCRIPT_DIR/render.sh $IBC0_HANDLER $IBC1_HANDLER $OUTDIR/chains

sh $SCRIPT_DIR/handshake.sh $OUTDIR/path.json $OUTDIR/chains
