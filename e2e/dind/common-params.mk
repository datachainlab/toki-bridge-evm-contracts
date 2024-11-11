REMOTE_IMAGE_REGISTRY ?=

PROJECT_NAME   ?= $(shell basename `pwd`)
IMAGE_NAME     ?= toki-e2e-$(PROJECT_NAME)
TMP_IMAGE_NAME ?= tmp-$(IMAGE_NAME)
CONTAINER_NAME ?= toki-e2e-dind
TMP_CONTAINER_NAME ?= toki-e2e-dind

RUN_OPTS ?= --privileged --add-host=host:host-gateway
