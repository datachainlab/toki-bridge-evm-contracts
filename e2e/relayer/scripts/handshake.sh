#!/bin/sh

set -eu

SCRIPT_DIR=$(dirname $0)

if [ -z $2 ]; then
  echo "$0 <path.json> <chain-dir>"
  exit 1
fi
PATH_JSON=$1
CHAIN_DIR=$2

RELAYER=yrly
IBC_PATH=ibc01

set -x

rm -f /root/.yui-relayer/config/config.yaml

${RELAYER} config init
${RELAYER} chains add-dir $CHAIN_DIR
${RELAYER} paths  add ibc0 ibc1 $IBC_PATH --file $PATH_JSON
cat /root/.yui-relayer/config/config.json

$RELAYER tx clients $IBC_PATH
$RELAYER tx connection $IBC_PATH
$RELAYER tx channel $IBC_PATH
