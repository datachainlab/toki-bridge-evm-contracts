#!/bin/sh

set -eu

DIR=$(dirname $0)
RELAYER=yrly
IBC_PATH=ibc01

set -x

$RELAYER service start $IBC_PATH

