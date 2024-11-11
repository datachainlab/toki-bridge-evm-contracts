DOCKER_VOLUME_SIZE=5G
#DOCKER_DIR_MODE=indocker
DOCKER_DIR_MODE=loopback

.PHONY: help
help:
	echo "$(MAKE) <image | run | sh>"

RUN_OPTS=--privileged --add-host=host:host-gateway
include ../common.mk

TMP_IMAGE_NAME = tmp-$(IMAGE_NAME)

.PHONY: tmp-image
tmp-image:
	docker build -f ./l1/Dockerfile --target insecure -t $(TMP_IMAGE_NAME) \
	  --build-arg TOKIDIND_DOCKER_DIR_MODE=$(DOCKER_DIR_MODE) \
	  --build-arg TOKIDIND_DOCKER_VOLUME_SIZE=$(DOCKER_VOLUME_SIZE) \
	  .

.PHONY: image
image:
	$(MAKE) tmp-image
	$(MAKE) run-tmp-image
	$(MAKE) commit-tmp-image

check:
	@echo "-- L1 check $(PROJECT_NAME)--------------------------"
	@CID=$$(docker ps -q -f name=$(CONTAINER_NAME)) ; \
	if [ -z $$CID ]; then \
	  echo "no container $(CONTAINER_NAME)" ;\
	else \
	  docker exec $$CID sh -c '\
	  echo docker ps; \
	  docker ps; \
	  echo df -m; \
	  doas df -m | grep -e docker$$ ; \
	  '; \
	fi

.PHONY: clean
clean:
	find . -name "*~" -exec rm {} \;
