#!/bin/bash -eux

cd $(dirname $0)

deploy_tao_then_app() {
  CHAIN=$1
  TAO_DEPLOY_BASENAME=deploy-${CHAIN}-tao-0
  APP_DEPLOY_BASENAME=deploy-${CHAIN}-oneshot-app-0

  # At first, call deploy script with DEPLOY_TARGET=tao.
  make -C .. ${TAO_DEPLOY_BASENAME}

  # Second, create oneshot parameter file with tao.deployed is set.
 IBC_HANDLER_ADDRESS=$(cat ./output/${TAO_DEPLOY_BASENAME}.contract.json | jq -r '.[]| select(.name == "OwnableIBCHandler") | .address')
 cat deploy-${CHAIN}-oneshot-0.parameter.json | jq ".tao.deployed.ownableIbcHandler |= \"${IBC_HANDLER_ADDRESS}\"" > ${APP_DEPLOY_BASENAME}.parameter.json

  # Third, call deploy oneshot
  make -C .. ${APP_DEPLOY_BASENAME}
}

deploy_tao_then_app bnb
deploy_tao_then_app eth
