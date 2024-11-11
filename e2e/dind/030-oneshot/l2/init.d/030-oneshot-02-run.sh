#!/bin/sh -e

cd $(dirname $0)
. common.shsrc

DEPLOY_FILE=${L2RELAYERDIR}/contract-deploy/output/deploy-bnb-oneshot-0.contract.json

case "x$1" in
  xstart)
    if [ -e ${DEPLOY_FILE} ]; then
      make -C $L2RELAYERDIR oneshot-relay SKIP_LOGS=1 ONCE=1
    else
      echo "Contract deploy file is not exists. Skip relayer start"
    fi
    ;;

  xstop)
    make -C $L2RELAYERDIR relayer-stop
    ;;
esac
