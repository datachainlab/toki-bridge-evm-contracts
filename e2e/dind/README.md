# prepare

## prerequirements

 - git
 - nodejs(npm)
 - docker

Note that you give enough CPU resource to dockerd, or this dind container may not run well.

## setup e2e

```
dind$ make prepare
```

## run container image registry locally

```
dind$ make container-image-registry
```

## create oneshot image

```
dind$ make image
```

---
# do your work

## run committed containers

```
dind$ make run
```

The containers is under condition that:
  - Ethereum node are run and it expose json-rpc endpoint on :18545 of L1 host.
  - BSC nodes are run and it expose json-rpc endpoint on :18545 of L1 host.
  - Toki app contracts on both chains are deployed and relayer is relaying them.
  - Pools are deposited by `make deposit` on e2e/test/ dir.

You can check json-rpc endpoint:

```
$ curl -sH 'content-type: application/json' --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://127.0.0.1:8545/ || true
$ curl -sH 'content-type: application/json' --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://127.0.0.1:18545/ || true
```

And you can see deposit values:

```
dind$ make -C 030-oneshot check-show
```


## do your work

for example, run withdrawRemote and see deposit values are updated:

```
e2e/test$ make testWithdrawRemote
dind$ make check-show
```

## reset to committed state

Simply stop container:

```
dind$ make stop
```

and re-run.

```
dind$ make run
```

You can see deposit value is roll back.

```
dind$ make check-show
```

---
# Known bugs

## bnb chain is stop when `make run`

You notice `make check` shows BNB chain is stalled.

Cause unknown yet.
Please `make stop` and `make run` again.
