#!/bin/sh -ex

HEADER="--- L3 $(arch) $(basename $0) "

cd $(dirname $0)

L2RUNDIR=/toki/run-ethereum
#GETH_IMAGE=${TOKIDIND_ETHEREUM_GETH_IMAGE} # set by Dockerfile
GETH_IMAGE=toki-ethereum-geth

L2DATADIR=$L2RUNDIR/geth-data
L2CONFDIR=$L2RUNDIR/geth-init

L3DATADIR=/geth-data
L3CONFDIR=/geth-init

UGID=$(id -u):$(id -g)

init() {
  if [ -e $L2DATADIR/geth/chaindata ]; then
    echo "${HEADER} chaindata is already exist"
    return
  fi
  echo "${HEADER} chaindata is not exist, init it..."
  cat $L2CONFDIR/genesis.json

  echo "${HEADER} run toki-eth-geth-init..."
  docker run --rm -u $UGID --name toki-eth-geth-init \
    -v $L2DATADIR:$L3DATADIR \
    -v $L2CONFDIR:$L3CONFDIR \
    --entrypoint sh \
    "${GETH_IMAGE}" \
    -c "
      geth --datadir=$L3DATADIR --state.scheme hash init $L3CONFDIR/genesis.json;
      for f in $L3CONFDIR/*.prv; do
        geth --datadir=$L3DATADIR account import --password /dev/null \$f
      done
    "
}

start() {
  if [ ! -e $L2RUNDIR/geth-data/geth/chaindata ]; then
    echo "$HEADER chaindata is not exist"
    exit 1
  fi

  i=10; while [ $i -gt 0 ]; do
    i=$(( i - 1 ))
    echo "${HEADER} ($i) run toki-eth-geth..."

    docker run --rm -d -u $UGID --name toki-eth-geth \
    -v $L2DATADIR:$L3DATADIR \
    -p 18545:8545 \
    --health-cmd "curl -sH 'content-type: application/json' --data '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_blockNumber\",\"params\":[]}' http://127.0.0.1:8545" \
    --health-interval="5s" \
    --health-timeout="10s" \
    --health-retries="30" \
    "${GETH_IMAGE}" \
    \
      --dev --dev.period 1 \
      --networkid=1337 \
      --datadir=$L3DATADIR \
      --verbosity=4 \
      --http \
      --http.api=debug,personal,eth,net,web3,txpool,engine,miner \
      --http.vhosts=* \
      --http.addr=0.0.0.0 \
      --http.port=8545 \
      --http.corsdomain=* \
      --rpc.allow-unprotected-txs \
      --rpc.gascap=100000000 \
      --allow-insecure-unlock \
      --unlock=0xa89F47C6b463f74d87572b058427dA0A13ec5425,0xcBED645B1C1a6254f1149Df51d3591c6B3803007 \
      --password=/dev/null \
      --gcmode=archive \
      --syncmode=full \
      --nodiscover \
      --mine \
      --miner.etherbase=0xa89F47C6b463f74d87572b058427dA0A13ec5425 \
      --miner.gasprice=0 \
      ;

    j=6; while [ $j -gt 0 ]; do
      j=$(( j - 1 ))
      sleep 5;
      docker ps
      if docker ps -f name=toki-eth-geth | grep healthy; then
        echo "succeeded in starting eth node"
        break
      fi
    done
    docker ps
    docker logs --tail=20 $(docker ps -f name=toki-eth-geth -q)
    if [ $j -gt 0 ]; then
       break
    fi
    echo "${HEADER} ($i) toki-eth-geth maybe stall. retry"
    curl -v -H 'content-type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' http://127.0.0.1:18545 || true
    docker inspect --format "{{json .State.Health}}" $( docker ps -f name=toki-eth-geth -q ) 
    sleep inf
    docker stop $( docker ps -f name=toki-eth-geth -q )
    while docker ps -f name=toki-eth-geth | grep toki-eth-geth; do sleep 5; done
  done
  docker ps
  if [ $i -gt 0 ]; then
    echo "${HEADER} succeeded in starting toki-eth-geth"
  else
    echo "${HEADER} fail to start toki-eth-geth"
    exit 1
  fi
}

case "x$1" in
  xstart)
    if [ ! -e $L2DATADIR/geth/chaindata ]; then
      init
    fi
    start
    ;;

  xstop)
    echo "${HEADER} stop toki-eth-geth..."
    /toki/stop-and-wait-container.sh toki-eth-geth
    ;;
esac
