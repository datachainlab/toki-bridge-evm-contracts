#!/bin/sh

SCRIPT_DIR=$(dirname $0)

if [ -z $2 ]; then
  echo "$0 <ibc0 handler address> <ibc1 handler address> [render outdir]"
  exit 1
fi
IBC0_HANDLER=$1
IBC1_HANDLER=$2
OUTDIR=$3

set -eux

sh $SCRIPT_DIR/render-handshake.sh $IBC0_HANDLER $IBC1_HANDLER $OUTDIR
sh $SCRIPT_DIR/service.sh
