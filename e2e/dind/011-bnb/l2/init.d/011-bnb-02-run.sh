#!/bin/sh -e

HEADER="--- L3 $(arch) $(basename $0) "

cd $(dirname $0)
. common.shsrc

BOOTSTRAP_FILE=${STAT_DIR}/$(basename $0 .sh).bootstrap-done
L2RUNDIR=${TOKI_DIR}/run-bnb

case "x$1" in
  xstart)
    if [ ! -e ${BOOTSTRAP_FILE} ]; then
      echo "$HEADER bootstrap-bsc..."
      make -C $L2RUNDIR bootstrap-bsc
      touch ${BOOTSTRAP_FILE}
    fi
    echo "$HEADER network-bsc..."
    make -C $L2RUNDIR network-bsc
    echo "$HEADER network-bsc done"
    sleep 5
    docker ps
    echo "$HEADER show latest 20 lines of toki-bsc-rpc log..."
    docker logs --tail=20 $(docker ps -f name=toki-bsc-rpc -q)
    ;;

  xstop)
    echo "$HEADER stop network-bsc..."
    make -C $L2RUNDIR network-stop-bsc
    ;;
esac
