#GETH_IMAGE=ethereum/client-go:v1.12.2
RUN_OPTS=--privileged --add-host=host:host-gateway -p 18545:18545

.PHONY: help
help:
	echo "$(MAKE) <image | run | sh>"

include ../common.mk

.PHONY: tmp-image
tmp-image:
	@$(MAKE) -C ../001-dind tmp-image
	#$(MAKE) pull-images PULL_IMAGES=$(GETH_IMAGE)
	docker build -f l1/Dockerfile -t $(TMP_IMAGE_NAME) \
	  --build-arg TMPDIR=l1/tmp \
	  --build-arg GETH_IMAGE="$(GETH_IMAGE)" \
	  .

image:
	$(MAKE) tmp-image
	$(MAKE) run-tmp-image
	$(MAKE) commit-tmp-image

check:
	@$(MAKE) --no-print-directory -C ../001-dind check CONTAINER_NAME=$(CONTAINER_NAME)
	@echo "-- L1 check $(PROJECT_NAME)--------------------------"
	curl -sH 'content-type: application/json' --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' http://localhost:18545/ || true
	curl -sH 'content-type: application/json' --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' http://localhost:18545/ || true
	curl -sH 'content-type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' http://127.0.0.1:18545

logs:
	docker exec $$(docker ps -q -f name=$(CONTAINER_NAME)) docker logs toki-eth-geth --tail=100 -f

clean:
	find . -name "*~" -exec rm {} \;
