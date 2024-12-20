CONTRACT_DEPLOY_CONFIG_DIR = $(CURDIR)/contract-deploy
TOKI_BRIDGE_LOCAL_REVISION = ce9248f137aa91f516e9e043d50b42c3d01ab8e1
TOKI_BRIDGE_LOCAL_DIR = toki-bridge-local-$(TOKI_BRIDGE_LOCAL_REVISION)

.PHONY: help
help:
	@echo "$(MAKE) <image | network | bootstrap | network-down>"

.PHONY: toki-bridge-local echo-toki-bridge-local-dir

toki-bridge-local: $(TOKI_BRIDGE_LOCAL_DIR)

echo-toki-bridge-local-dir:
	@echo $(TOKI_BRIDGE_LOCAL_DIR)

$(TOKI_BRIDGE_LOCAL_DIR):
	@if [ "x$(GIT_HTTPS)" = "x1" ]; then \
	  echo git clone -b main https://github.com/datachainlab/toki-bridge-local $@; \
	  git clone -b main https://github.com/datachainlab/toki-bridge-local $@; \
	else \
	  echo git clone -b main git@github.com:datachainlab/toki-bridge-local $@; \
	  git clone -b main git@github.com:datachainlab/toki-bridge-local $@; \
	fi
	cd $@; \
	  git checkout $(TOKI_BRIDGE_LOCAL_REVISION)
	  git submodule init; git submodule update; \
	cd ..

.PHONY: image-name-bsc image-name-eth image-name-relayler
image-name-bsc: $(TOKI_BRIDGE_LOCAL_DIR)
	@v=$$( $(MAKE) -pqR -C $(TOKI_BRIDGE_LOCAL_DIR)/development/chains/bsc | awk '$$1=="GIT_CHECKOUT_BRANCH" && $$2=="="{print $$3}' ); \
	  echo toki-bsc-geth:$$v; \
	  echo toki-bsc-geth-bootstrap:$$v;
image-name-eth: $(TOKI_BRIDGE_LOCAL_DIR)
	@v=$$( $(MAKE) -pqR -C $(TOKI_BRIDGE_LOCAL_DIR)/development/chains/eth | awk '$$1=="GETH_VERSION" && $$2=="="{print $$3}' ); \
	  echo toki-eth-geth:$$v
	@v=$$( $(MAKE) -pqR -C $(TOKI_BRIDGE_LOCAL_DIR)/development/chains/eth | awk '$$1=="LODESTAR_VERSION" && $$2=="="{print $$3}' ); \
	  echo toki-eth-lodestar:$$v
	@echo toki-eth-deposit:latet
image-name-relayer:
	@$(MAKE) -C relayer image-name


.PHONY: image image-bsc image-eth image-relayer
image-bsc: $(TOKI_BRIDGE_LOCAL_DIR)
	# toki-bsc-geth:$(GIT_CHECKOUT_BRANCH)
	# toki-bsc-geth-bootstrap:$(GIT_CHECKOUT_BRANCH) #datadir=/root/storage/{bsc-rpc|bsc-validator(1-4)}
	$(MAKE) -C $(TOKI_BRIDGE_LOCAL_DIR)/development/chains/bsc docker-build

image-eth: $(TOKI_BRIDGE_LOCAL_DIR)
	# toki-eth-geth:$(GETH_VERSION) # build, init, account import
	# toki-eth-lodestar:$(LODESTAR_VERSION)
	# toki-eth-deposit:latest
	$(MAKE) -C $(TOKI_BRIDGE_LOCAL_DIR)/development/chains/eth GETH_HTTP_PORT=18545 docker-build

image-relayer:
	# toki-relayer-eth-mock
	$(MAKE) -C relayer image

image: $(TOKI_BRIDGE_LOCAL_DIR)
	$(MAKE) image-bsc
	$(MAKE) image-eth
	$(MAKE) image-relayer

.PHONY: prune-volume
prune-volume:
	docker volume rm -f bsc_toki-bsc-rpc bsc_toki-bsc-validator1 bsc_toki-bsc-validator2 bsc_toki-bsc-validator3 bsc_toki-bsc-validator4

.PHONY: bootstrap bootstrap-bsc bootstrap-eth
bootstrap-bsc: $(TOKI_BRIDGE_LOCAL_DIR)
	$(MAKE) -C $(TOKI_BRIDGE_LOCAL_DIR)/development/chains/bsc bootstrap # init, account new
bootstrap-eth: $(TOKI_BRIDGE_LOCAL_DIR)
	# do nothing
bootstrap: $(TOKI_BRIDGE_LOCAL_DIR)
	$(MAKE) bootstrap-bsc
	$(MAKE) bootstrap-eth

.PHONY: network network-bsc network-eth
network-bsc: $(TOKI_BRIDGE_LOCAL_DIR)
	# $(MAKE) -C $(TOKI_BRIDGE_LOCAL_DIR)/development/chains/bsc network
	@cd $(TOKI_BRIDGE_LOCAL_DIR)/development/chains/bsc; \
	  export GIT_CHECKOUT_BRANCH=$$( $(MAKE) -pqR | awk '$$1=="GIT_CHECKOUT_BRANCH" && $$2=="="{print $$3}' ); \
	  i=0; while [ $$i -lt 10 ]; do \
	    i=$$((i + 1)); \
	    echo "$$i trying to start bsc nodes..."; \
	    docker compose -f docker-compose.simple.yml up -d toki-bsc-rpc; \
	    sleep 10; \
	    docker compose -f docker-compose.simple.yml up -d toki-bsc-validator1 toki-bsc-validator2 toki-bsc-validator3 toki-bsc-validator4; \
	    sleep 60; \
	    docker ps | grep toki-bsc-geth; \
	    if docker ps -f name=toki-bsc-rpc | grep healthy; then \
	      echo "succeeded in starting bsc nodes"; \
	      exit 0; \
	    fi; \
	    $(MAKE) -C ../../../.. network-stop-bsc; \
	  done; \
	  echo "fail to start bsc nodes"; \
	  exit 1

network-eth: $(TOKI_BRIDGE_LOCAL_DIR)
	$(MAKE) -C $(TOKI_BRIDGE_LOCAL_DIR)/development/chains/eth GETH_HTTP_PORT=18545 BEACON_HTTP_PORT=19596 network
network: $(TOKI_BRIDGE_LOCAL_DIR)
	$(MAKE) network-bsc
	$(MAKE) network-eth

.PHONY: network-check
network-check:
	# bsc
	curl -sH 'content-type: application/json' --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' http://localhost:8545/ || true
	curl -sH 'content-type: application/json' --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://localhost:8545/ || true
	# eth
	curl -sH 'content-type: application/json' --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' http://localhost:18545/  || true
	curl -sH 'content-type: application/json' --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://localhost:18545/ || true

.PHONY: network-stop network-stop-bsc network-stop-eth
network-stop-bsc: $(TOKI_BRIDGE_LOCAL_DIR)
	# docker compose \
	#   -f $(TOKI_BRIDGE_LOCAL_DIR)/development/chains/bsc/docker-compose.simple.yml \
	#   stop -t 300 \
	#   toki-bsc-rpc toki-bsc-validator1 toki-bsc-validator2 toki-bsc-validator3 toki-bsc-validator4
	for n in toki-bsc-validator4 toki-bsc-validator3 toki-bsc-validator2 toki-bsc-validator1 toki-bsc-rpc; do \
	  cid=$$(docker ps -q -f name=$$n); \
	  docker exec $$cid sh -c " \
	    pkill -TERM geth; \
	    while pgrep -l geth ; do sleep 1; done; \
	  "; \
	  docker stop $$cid; \
	  docker rm $$cid; \
	done

network-stop-eth: $(TOKI_BRIDGE_LOCAL_DIR)
	docker compose \
	  -f $(TOKI_BRIDGE_LOCAL_DIR)/development/chains/eth/docker-compose.yml \
	  stop -t 300 \
	  toki-eth-geth toki-eth-lodestar toki-eth-deposit toki-eth-lodestar-validator
network-stop: $(TOKI_BRIDGE_LOCAL_DIR)
	$(MAKE) network-stop-bsc
	$(MAKE) network-stop-eth

.PHONY: network-down network-down-bsc network-down-eth
network-down-bsc: $(TOKI_BRIDGE_LOCAL_DIR)
	$(MAKE) -C $(TOKI_BRIDGE_LOCAL_DIR)/development/chains/bsc network-down
network-down-eth: $(TOKI_BRIDGE_LOCAL_DIR)
	$(MAKE) -C $(TOKI_BRIDGE_LOCAL_DIR)/development/chains/eth network-down
network-down: $(TOKI_BRIDGE_LOCAL_DIR)
	$(MAKE) network-down-bsc
	$(MAKE) network-down-eth

.PHONY: network-prune
network-prune: $(TOKI_BRIDGE_LOCAL_DIR)
	$(MAKE) network-down
	$(MAKE) prune-volume

.PHONY: network-hardhat
network-hardhat:
	$(MAKE) -C .. network-hardhat

.PHONY: clean-artifcts
clean-artifacts:
	@$(MAKE) -C .. clean-artifacts

../artifacts:
	$(MAKE) -C .. setup
	$(MAKE) -C .. build-hardhat
	$(MAKE) -C .. typechain

deploy:
	@mkdir -p $(CONTRACT_DEPLOY_CONFIG_DIR)/output
	@DEPLOY_BUILDER="hardhat" \
	DEPLOY_INPUT=$(CONTRACT_DEPLOY_CONFIG_DIR)/$(_DEPLOY_NAME).parameter.json \
	DEPLOY_OUTPUT_PREFIX=$(CONTRACT_DEPLOY_CONFIG_DIR)/output/$(_DEPLOY_NAME) \
	  $(MAKE) -C .. deploy

deploy-%:
	rm -rf ../.openzeppelin/*.json
	./hardhat-run.sh $(CONTRACT_DEPLOY_CONFIG_DIR)/$@.parameter.json

.PHONY: oneshot-network
oneshot-network:
	$(MAKE) network-down
	$(MAKE) prune-volume
	$(MAKE) bootstrap
	$(MAKE) network

sleep:
	@echo "sleeep..."; sleep 10; echo "awake"

.PHONY: oneshot-deploy
oneshot-deploy: ../artifacts
	rm -rf contract-deploy/output
	@pids=""; \
	  $(MAKE) deploy-eth-oneshot-0 & pids="$$pids $$!"; \
	  $(MAKE) deploy-bnb-oneshot-0 & pids="$$pids $$!"; \
	  ps | grep "deploy-" ; \
	  echo "waiting $$pids..." ;\
	  for pid in $$pids; do \
	    e=0; wait $$pid || e=$$?; \
	    if [ $$e -ne 0 -a $$e -ne 127 ]; then \
	      echo "pid=$$pid failed with status=$$e"; \
	      exit $$e; \
	    fi \
	  done
	docker ps
	ls -l contract-deploy/output

.PHONY: relayer-stop
relayer-stop:
	$(MAKE) -C relayer stop

.PHONY: oneshot-relay
oneshot-relay:
	rm -rf relayer/abi; $(MAKE) -C relayer abi
	IBC0_HANDLER=$$(cat $(CONTRACT_DEPLOY_CONFIG_DIR)/output/deploy-bnb-oneshot-0.contract.json | jq -r '.[] | select(.name == "OwnableIBCHandler") | .address'); \
	IBC1_HANDLER=$$(cat $(CONTRACT_DEPLOY_CONFIG_DIR)/output/deploy-eth-oneshot-0.contract.json | jq -r '.[] | select(.name == "OwnableIBCHandler") | .address'); \
	  if [ x$(ONCE) = x ]; then \
	    $(MAKE) -C relayer render-handshake-service IBC0_HANDLER=$${IBC0_HANDLER} IBC1_HANDLER=$${IBC1_HANDLER}; \
	  else \
	    $(MAKE) -C relayer once-render-handshake-service IBC0_HANDLER=$${IBC0_HANDLER} IBC1_HANDLER=$${IBC1_HANDLER}; \
	  fi
	test x$(SKIP_LOGS) = x && $(MAKE) -C relayer logs || true

.PHONY: oneshot-build-deploy-relay
oneshot-build-deploy-relay:
	$(MAKE) -C .. clean-artifacts
	$(MAKE) -C relayer stop
	$(MAKE) oneshot-deploy
	$(MAKE) oneshot-relay

.PHONY: clean
clean:
	$(MAKE) -C .. clean
	rm -rf $(CONTRACT_DEPLOY_CONFIG_DIR)/output
	$(MAKE) -C relayer clean

# avoid from setting up git auth in docker-in-docker
.PHONY: git
git:
	$(MAKE) -C .. submodule
	$(MAKE) toki-bridge-local
