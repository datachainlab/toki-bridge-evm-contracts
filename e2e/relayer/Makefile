#  for reference,
#  - check version of related software:
#    https://github.com/datachainlab/toki-bridge-local/blob/<version>/README.md
#  - check initializing code
#    https://github.com/datachainlab/toki-bridge-relayer/blob/main/main.go
#  to use the latest version, check the following:
#    https://github.com/datachainlab/cosmos-ethereum-ibc-lcp/blob/main/README.md#supported-versions
RELAYER_VERSION ?= v0.5.8
IBC_ETH_VERSION ?= v0.3.10
IBC_HD_SIGNER_VERSION ?= v0.1.0

CONTAINER := toki-relayer-eth-mock
IMAGE := $(CONTAINER):$(RELAYER_VERSION)-$(IBC_ETH_VERSION)

IBC0_HANDLER ?=
IBC1_HANDLER ?=

.PHONY: image image-name
image-name:
	@echo $(IMAGE)

image:
	docker rmi $(IMAGE) || true
	docker build --progress=plain -f Dockerfile --target runner --build-arg RELAYER_VERSION=$(RELAYER_VERSION) --build-arg IBC_ETH_VERSION=$(IBC_ETH_VERSION) --build-arg IBC_HD_SIGNER_VERSION=$(IBC_HD_SIGNER_VERSION) -t $(IMAGE) .

.PHONY: render-handshake-service once-render-handshake-service volume render handshake service
render-handshake-service:
	$(MAKE) volume
	$(MAKE) render-handshake IBC0_HANDLER=$(IBC0_HANDLER) IBC1_HANDLER=$(IBC1_HANDLER); \
	$(MAKE) service

once-render-handshake-service:
	if [ -z $$( docker volume ls -q -f name=$(CONTAINER) ) ]; then \
	  $(MAKE) render-handshake-service IBC0_HANDLER=$(IBC0_HANDLER) IBC1_HANDLER=$(IBC1_HANDLER); \
	else \
	  $(MAKE) service ;\
	fi

volume:
	@docker volume rm -f $(CONTAINER)
	@docker volume create $(CONTAINER)

render-handshake: abi
	ip=host-gateway && \
	   docker run --name $(CONTAINER)-handshake --add-host=host:$$ip --rm -v $(CONTAINER):/root/.yui-relayer -v $$(pwd)/scripts/config:/scripts/config -v $$(pwd)/abi:/abi --entrypoint sh ${IMAGE} /scripts/render-handshake.sh $(IBC0_HANDLER) $(IBC1_HANDLER)

abi:
	mkdir -p abi
	for f in ../../abi/*.json; do cat $$f | jq '.abi' > abi/$$(basename $$f); done

service: abi
	@echo RELAYER_VERSION=$(RELAYER_VERSION) IBC_ETH_VERSION=$(IBC_ETH_VERSION)
	@echo $(IMAGE)
	pwd
	ip=host-gateway && \
	  docker run --rm -v $(CONTAINER):/root/.yui-relayer --entrypoint sh ${IMAGE} -c 'cat /root/.yui-relayer/config/config.json'
	ip=host-gateway && \
	   docker run -d --name $(CONTAINER)-service --add-host=host:$$ip --rm -v $(CONTAINER):/root/.yui-relayer  -v $$(pwd)/abi:/abi ${IMAGE} service start ibc01

.PHONY: stop
stop:
	CID=$$(docker ps -f name=$(CONTAINER)-service -q) && \
	  if [ "x$$CID" != "x" ]; then docker stop $$CID; fi

.PHONY: logs
logs:
	CID=$$(docker ps -f name=$(CONTAINER)-service -q) && \
	  docker logs -tf $$CID --tail=100

.PHONY: logsN
logsN:
	CID=$$(docker ps -f name=$(CONTAINER)-service -q) && \
	  docker logs -t $$CID --tail=$(N)

.PHONY: clean
clean:
	find . -name "*~" -exec rm {} \;
	rm -f scripts/config/generated-chains/*
	rm -rf abi


