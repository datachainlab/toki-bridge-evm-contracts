#!/bin/sh

SCRIPT_DIR=$(dirname $0)
CONF_DIR=$SCRIPT_DIR/config

if [ -z $2 ]; then
  echo "$0 <ibc0 handler address> <ibc1 handler address> [output dir]"
  exit 1
fi
IBC0_HANDLER=$1
IBC1_HANDLER=$2
OUTDIR=$3

set -eux

if [ -z $OUTDIR ]; then
  OUTDIR=$(mktemp -d)
elif [ ! -d $OUTDIR ]; then
  mkdir -p $OUTDIR
fi

create_chain_config() {
  template=$1
  handler_address=$2

  out=$OUTDIR/$(basename $template .template.json).json

  IBC_ADDR=$handler_address envsubst < $template > $out
}

create_chain_config $CONF_DIR/ibc-0.template.json $IBC0_HANDLER
create_chain_config $CONF_DIR/ibc-1.template.json $IBC1_HANDLER

echo $OUTDIR
