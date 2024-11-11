RUN_OPTS=--privileged --add-host=host:host-gateway -p 8545:8545 -p 18545:18545

.PHONY: help
help:
	echo "$(MAKE) <image | run | sh>"

include ../common.mk

E2E_DIR=../..

.PHONY: tmp-image
tmp-image:
	@$(MAKE) -C ../010-ethereum tmp-image
	@$(MAKE) -C $(E2E_DIR) image-bsc

	@rm -rf l1/tmp; mkdir -p l1/tmp
	$(MAKE) --no-print-directory -sC $(E2E_DIR) image-name-bsc > l1/tmp/pull-image.txt
	./l1/copy-files.sh $(E2E_DIR) l1/tmp/e2e

	@for i in $$(cat l1/tmp/pull-image.txt); do ../l1-pull-image.sh "" $$i; done
	docker build -f l1/Dockerfile -t $(TMP_IMAGE_NAME) \
	  --build-arg TMPDIR=l1/tmp \
	  .

image:
	$(MAKE) tmp-image
	$(MAKE) run-tmp-image
	$(MAKE) commit CONTAINER_NAME=$(TMP_CONTAINER_NAME)

check:
	@$(MAKE) --no-print-directory -C ../010-ethereum check CONTAINER_NAME=$(CONTAINER_NAME)
	@echo "-- L1 check $(PROJECT_NAME)--------------------------"
	curl -sH 'content-type: application/json' --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' http://localhost:8545/ || true
	curl -sH 'content-type: application/json' --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' http://localhost:8545/ || true
	curl -sH 'content-type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' http://127.0.0.1:8545

logs:
	docker exec $$(docker ps -q -f name=$(CONTAINER_NAME)) docker logs toki-bsc-rpc --tail=100 -f

clean:
	find . -name "*~" -exec rm {} \;
