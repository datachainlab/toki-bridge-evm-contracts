RUN_OPTS=--privileged --add-host=host:host-gateway -p 8545:8545 -p 18545:18545

.PHONY: help
help:
	echo "$(MAKE) <image | run | sh>"

include ../common.mk

E2E_DIR=../..

.PHONY: tmp-image
tmp-image:
	@$(MAKE) -C ../020-relayer tmp-image
	docker build -f l1/Dockerfile -t $(TMP_IMAGE_NAME) .

pre-commit:
	$(MAKE) -C $(E2E_DIR) ../artifacts
	@echo "trying to deploy..."
	$(MAKE) check
	$(MAKE) -C $(E2E_DIR) oneshot-deploy
	CID=$$(docker ps -f name=$(TMP_CONTAINER_NAME) -q); \
	  docker cp $(E2E_DIR)/contract-deploy $$CID:/toki/run-relayer/contract-deploy
	CID=$$(docker ps -f name=$(TMP_CONTAINER_NAME) -q); \
	  for d in artifacts abi script e2e/test e2e/contract-deploy; do \
	    docker cp $(E2E_DIR)/../$$d $$CID:/toki/run-test/$$d ;\
	  done; \
	  docker exec $$CID make -C /toki/run-test/e2e/test setup show
	# for relayer
	CID=$$(docker ps -f name=$(TMP_CONTAINER_NAME) -q); \
	  for d in abi; do \
	    docker cp $(E2E_DIR)/../$$d $$CID:/toki/$$d ;\
	  done; \
	CID=$$(docker ps -f name=$(TMP_CONTAINER_NAME) -q); \
	  docker exec $$CID /toki/init.d/030-oneshot-02-run.sh start
	docker ps
	CID=$$(docker ps -f name=$(TMP_CONTAINER_NAME) -q); \
	  docker exec $$CID docker ps
	$(MAKE) -C $(E2E_DIR)/test deposit

copy-deploy-output:
	CID=$$(docker ps -f name=$(TMP_CONTAINER_NAME) -q); \
	  docker cp $$CID:/toki/run-relayer/contract-deploy/output $(E2E_DIR)/contract-deploy

image:
	@echo "-- L1 $(MAKE) tmp-image ---------------"
	@$(MAKE) tmp-image
	@echo "-- L1 $(MAKE) run-tmp-image ---------------"
	@$(MAKE) run-tmp-image
	@echo "-- L1 $(MAKE) pre-commit ---------------"
	@$(MAKE) pre-commit
	@echo "-- L1 $(MAKE) commit CONTAINER_NAME=$(TMP_CONTAINER_NAME) ---------------"
	@$(MAKE) commit CONTAINER_NAME=$(TMP_CONTAINER_NAME)

check:
	@$(MAKE) --no-print-directory -C ../020-relayer check CONTAINER_NAME=$(CONTAINER_NAME)
	@echo "-- L1 check $(PROJECT_NAME)--------------------------"

check-show:
	@$(MAKE) --no-print-directory -C $(E2E_DIR)/test show

clean:
	find . -name "*~" -exec rm {} \;
