#!/bin/sh

set -eu

TMPL=$1

err() {
    echo $1
    exit 1
}
test -z $TMPL && err "$0 <template file>"
test -z $RELAYER && err "RELAYER is not set"
test -z $RELAYER_VERSION && err "RELAYER_VERSION is not set"
test -z $IBC_ETH && err "IBC_ETH is not set"
test -z $IBC_ETH_VERSION && err "IBC_ETH_VERSION is not set"
test -z $IBC_HD_SIGNER && err "IBC_HD_SIGNER is not set"
test -z $IBC_HD_SIGNER_VERSION && err "IBC_HD_SIGNER_VERSION is not set"

set -x
cat $TMPL \
  | sed -e "s#^\t${RELAYER} v.*\$#\t${RELAYER} ${RELAYER_VERSION}#" \
  | sed -e "s#^\t${IBC_ETH} v.*\$#\t${IBC_ETH} ${IBC_ETH_VERSION}#" \
  | sed -e "s#^\t${IBC_HD_SIGNER} v.*\$#\t${IBC_HD_SIGNER} ${IBC_HD_SIGNER_VERSION}#" \
  ;
