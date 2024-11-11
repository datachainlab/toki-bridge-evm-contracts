#!/bin/sh -e

# --- constants -------------------------
# This is default accounts #0 displayed at starting hardhat network
PRIVATE_KEY_HARDHAT=ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# This is from toki-bridge-local/development/chains/bsc/init-holders/0x00731540cd6060991d6b9c57ce295998d9bc2fab
PRIVATE_KEY_BNB=043a3427c36481e3cce70f5e6738b5f4d1a7e87fa90aa833f4bf2d3d690d4919

# This is from toki-bridge-local/development/chains/eth/config/dev-key0.prv
PRIVATE_KEY_ETH=e517af47112e4f501afb26e4f34eadc8b0ad8eadaf4962169fc04bc8ddbfe091

# --- parse args -------------------------
if [ -z $1 ]; then
  echo "$0 <parameter file>"
  exit 1
fi
PARAMFILE=$(readlink -f $1)
if [ ! -f $PARAMFILE ]; then
  echo "parameter file not found: $PARAMFILE"
  exit 1
fi

OUTDIR=$(dirname $PARAMFILE)/output
test -d $OUTDIR || mkdir -p $OUTDIR

NAME=$(echo $(basename ${PARAMFILE}) | cut -d . -f 1)
#echo $NAME

ACTION=$(echo $NAME | cut -d - -f 1)
CHAIN=$(echo $NAME | cut -d - -f 2)
TARGET=$(echo $NAME | cut -d - -f 3)
VARIANT=$(echo $NAME | cut -d - -f 4-)
echo "ACTION=$ACTION, CHAIN=$CHAIN, TARGET=$TARGET, VARIANT=$VARIANT"

# --- setup script parameters -------------------------
export DEPLOY_TARGET=$TARGET
export DEPLOY_BUILDER="hardhat"
export DEPLOY_INPUT=$PARAMFILE
export DEPLOY_OUTPUT_PREFIX=$OUTDIR/$NAME

case x$CHAIN in
  xhardhat)
    export DEPLOY_NETWORK=hardhat
    export DEPLOY_PRIVATE_KEY=$PRIVATE_KEY_HARDHAT
    export DEPLOY_RPC_URL=http://localhost:8000
    ;;
  xbnb)
    export DEPLOY_NETWORK=envvar
    export DEPLOY_MAX_FEE_PER_GAS=3000000000
    export DEPLOY_MAX_PRIORITY_FEE_PER_GAS=3000000000
    export DEPLOY_PRIVATE_KEY=$PRIVATE_KEY_BNB
    export DEPLOY_RPC_URL=http://localhost:8545
    ;;
  xeth)
    export DEPLOY_NETWORK=envvar
    export DEPLOY_PRIVATE_KEY=$PRIVATE_KEY_ETH
    export DEPLOY_RPC_URL=http://localhost:18545
    ;;
  *)
    echo "unknown chain: $CHAIN"
    exit 1
esac

# --- run -------------------------
set -x
cd $(dirname $0)/..
npx hardhat run script/hardhat/run-${ACTION}.ts --no-compile --network ${DEPLOY_NETWORK}
