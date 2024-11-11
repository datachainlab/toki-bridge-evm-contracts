#!/bin/sh -e

cd $(dirname $0)
. common.shsrc
L2RUNDIR=/toki/run-ethereum

case "x$1" in
  xstart)
    #${TOKI_DIR}/pull-image.sh ${TOKIDIND_ETHEREUM_GETH_IMAGE}
    docker build -t toki-ethereum-geth -f $L2RUNDIR/Dockerfile $L2RUNDIR
    ;;

  xstop)
    ;;
esac
