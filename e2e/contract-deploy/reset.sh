#!/bin/bash -eu

# How to run `reset` deploy
#   1. create testnettest_00001_reset-<chain> parameter file and hardhat-run
#      run `reset.sh deploy`
#   2. takeover deploy-<chain>-oneshot-0 output file because relayer or e2e/test uses it
#      run `reset.sh takeover`
#   3. relayer handshake
#      - run `make -C .. relayer-stop`
#      - run `make -C .. oneshot-relay`
#

CMD=${1:-""}

cd $(dirname $0)
PARAMDIR=../contract-deploy

deploy_reset() {
  CHAIN=$1
  DEPLOY_NAME=testnettest_00001_reset-${CHAIN}
  LATEST_INPUT=$PARAMDIR/deploy-${CHAIN}-oneshot-0.parameter.json
  LATEST_OUTPUT=$PARAMDIR/output/deploy-${CHAIN}-oneshot-0.contract.json

  set -x
  jq '. + {"reuse": input}' $LATEST_INPUT $LATEST_OUTPUT > $DEPLOY_NAME.parameter.json

  rm -rf ../../.openzeppelin/*.json
  ../hardhat-run.sh $DEPLOY_NAME.parameter.json
}

takeover_output() {
  CHAIN=$1
  DEPLOY_NAME=testnettest_00001_reset-${CHAIN}
  LATEST_OUTPUT=$PARAMDIR/output/deploy-${CHAIN}-oneshot-0.contract.json

  set -x
  jq -s '.[0] + .[1]' $PARAMDIR/output/$DEPLOY_NAME.contract.json $PARAMDIR/output/$DEPLOY_NAME.reuse.json > $LATEST_OUTPUT
}

case "x$CMD" in
  "xdeploy" )
    deploy_reset bnb
    deploy_reset eth
    ;;
  "xtakeover" )
    takeover_output bnb
    takeover_output eth
    ;;
  "xrelayer" )
    set -x
    make -C .. relayer-stop || true
    SKIP_LOGS=1 make -C .. oneshot-relay
    ;;
  * )
    echo "unknown command: $CMD"
    echo "$0 <deploy | takeover | relayer>"
    exit 1
    ;;
esac


