# Test contracts on IBC environment

This e2e directory performs:
  - Create and run container images of private-net blockchain of BNB and Ethereum.
  - Deploy bridge contracts(some contracts are mock or dummy) to the private chains.
  - Setup relayer container image with eth-chain and mock-prover modules.
    The configurations is:
      - src-chain is bnb
      - dst-chain is eth
      - see relayer/scripts/config directory for details.
  - The `dind` directory is to create a container image that has been completed until deposit. see [./dind/README.md]

---
# Start private-net of ethereum and bnb chain

## Create container images

This step is to download images from the DockerHub, so you may need to login.

```
make image
```

## Start containers by docker compose

```
make oneshot-network
```

This runs:
  1. Start bnb nodes
  2. Start ethereum nodes

---
# Deploy contracts

1. create parameter file

You can create your own parameter files or use predefined files:
 - `contract-deploy/deploy-bnb-oneshot-0.parameters.json`
 - `contract-deploy/deploy-eth-oneshot-0.parameters.json`

2. deploy

```
make oneshot-deploy
```

This runs:
 1. Deploy contracts to bnb and eth chain and generates results to contract-deploy/output/

---
# Configure and start relayer

```
make oneshot-relay
```

This runs:
 1. Start relayer

Wait a few minutes to complete handshake.

Relayer configuration files are generated from relay/scripts/config/ and contract-deploy/output/ files.
You can edit them.

---
# Test IBC

At first, setup test libraries.

```
cd test
make setup
```

There are some tests:

 - show
 - testSendCredit
 - tetTransferToken
 - testTransferPool

Some tests requires to deposit tokens. call `npm run deposit`.

Then you can run test by `make <test>`.
