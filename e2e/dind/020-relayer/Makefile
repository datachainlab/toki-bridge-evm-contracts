RUN_OPTS=--privileged --add-host=host:host-gateway -p 8545:8545 -p 18545:18545

.PHONY: help
help:
	echo "$(MAKE) <image | run | sh>"

include ../common.mk

E2E_DIR=../..

.PHONY: tmp-image
tmp-image:
	@$(MAKE) -C ../011-bnb tmp-image
	@$(MAKE) -C $(E2E_DIR) image-relayer

	@rm -rf l1/tmp; mkdir -p l1/tmp
	$(MAKE) --no-print-directory -sC $(E2E_DIR) image-name-relayer > l1/tmp/pull-image.txt
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
	@$(MAKE) --no-print-directory -C ../011-bnb check CONTAINER_NAME=$(CONTAINER_NAME)
	@echo "-- L1 check $(PROJECT_NAME)--------------------------"

logs:
	docker exec $$(docker ps -q -f name=$(CONTAINER_NAME)) make -C /toki/run-relayer/relayer logs

clean:
	find . -name "*~" -exec rm {} \;
	rm -rf l1/tmp
