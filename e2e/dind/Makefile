TARGETS = 001-dind 010-ethereum 011-bnb 020-relayer 030-oneshot
DEFAULT_TARGET = 030-oneshot

IMAGE_TARGETS = $(addprefix image-,$(TARGETS))
RUN_TARGETS   = $(addprefix run-,$(TARGETS))
STOP_TARGETS  = $(addprefix stop-,$(TARGETS))
CHECK_TARGETS  = $(addprefix check-,$(TARGETS))

.PHONY: help
help:
	@echo "make prepare"
	@echo "make container-image-registry"
	@echo "make <command>-<target>"
	@echo "  targets are:  $(TARGETS)"
	@echo "  commands are: image run stop"

.PHONY: container-image-registry
container-image-registry:
	docker run -d -p 5000:5000 --restart always --name registry mirror.gcr.io/registry:2.8.3

.PHONY: prepare
prepare:
	test x$(SKIP_GIT) = x && $(MAKE) -C .. git || true
	test x$(SKIP_IMAGE) = x && $(MAKE) -C .. image-bsc image-relayer || true
	$(MAKE) -C .. ../artifacts
	$(MAKE) -C ../test setup

.PHONY: $(IMAGE_TARGETS) $(RUN_TARGETS) $(STOP_TARGETS) $(CHECK_TARGETS)
$(IMAGE_TARGETS) $(RUN_TARGETS) $(STOP_TARGETS) $(CHECK_TARGETS):
	@echo $(MAKE) -C $$(echo $@ | cut -d - -f 2-) $$(echo $@ | cut -d - -f 1)
	@$(MAKE) -C $$(echo $@ | cut -d - -f 2-) $$(echo $@ | cut -d - -f 1)

.PHONY: image run stop
image run stop check:
	@$(MAKE) $@-$(DEFAULT_TARGET)

clean:
	find . -name "*~" -exec rm {} \;
	for t in $(TARGETS); do $(MAKE) -C $$t clean; done

include ./common-params.mk #CONTAINER_NAME
.PHONY: relayer-logs eth-logs bnb-logs
relayer-logs:
	@$(MAKE) -C 020-relayer logs CONTAINER_NAME=$(CONTAINER_NAME)
eth-logs:
	@$(MAKE) -C 010-ethereum logs CONTAINER_NAME=$(CONTAINER_NAME)
bnb-logs:
	@$(MAKE) -C 011-bnb logs CONTAINER_NAME=$(CONTAINER_NAME)

.PHONY: copy-deploy-result
copy-deploy-result:
	docker cp $$(docker ps -f name=$(CONTAINER_NAME) -q):/toki/run-relayer/contract-deploy ..


.PHONY: acr
ACR_TAG=features-lo-3207-ci-dind-image
ACR_IMAGE=toki-bridge-evm-contracts
ACR_NAME=tokitestnetcommon
acr:
	az acr login --name ${ACR_NAME}
	docker pull $(ACR_NAME).azurecr.io/$(ACR_IMAGE):$(ACR_TAG)
	$(MAKE) run IMAGE_NAME=$(ACR_NAME).azurecr.io/$(ACR_IMAGE):$(ACR_TAG)
