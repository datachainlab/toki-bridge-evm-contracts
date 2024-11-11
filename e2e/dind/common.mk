THIS_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
include $(THIS_DIR)/common-params.mk

.PHONY: project-name image-name
project-name:
	@echo "$(PROJECT_NAME)"
image-name:
	@echo "$(IMAGE_NAME)"

.PHONY: run sh stop commit
run:
	docker run -d --rm --name $(CONTAINER_NAME) $(RUN_OPTS) $(IMAGE_NAME)
	@sleep 3
	docker ps
	sh -e -c 'CID=$$(docker ps -f name=$(CONTAINER_NAME) -q); \
	  test -z $$CID && (echo "fail to run $(IMAGE_NAME)"; exit 1); \
	  docker logs -f $$CID & \
	  docker exec $$CID /toki/wait-entrypoint-init-start.sh \
	'

run-sh:
	docker run --entrypoint sh -it --rm --name $(CONTAINER_NAME) $(RUN_OPTS) -it $(IMAGE_NAME)

sh:
	docker exec -it $$(docker ps -f name=$(CONTAINER_NAME) -q) sh

stop:
	docker stop $$(docker ps -f name=$(CONTAINER_NAME) -q)

commit:
	@CID=$$(docker ps -f name=$(CONTAINER_NAME) -q); \
	  docker exec   $$CID /toki/wait-entrypoint-init-start.sh && \
	  docker exec   $$CID kill -USR1 1 && \
	  docker exec   $$CID /toki/wait-entrypoint-init-stop.sh && \
	  echo "waiting docker commit $$CID $(IMAGE_NAME)..." && \
	  docker commit $$CID $(IMAGE_NAME) && \
	  docker stop   $$CID && \
	  while test $$(docker ps -q -f id=$$CID | wc -l) -gt 0; do sleep 3; done
	docker image ls|awk '$$1=="$(IMAGE_NAME)"{print $$0}'

# typically process: build tmp-image, run-tmp-image, exec on tmp image, then commit-tmp-image
.PHONY: pull-images run-tmp-images commit-tmp-image
pull-images:
	# set PULL_IMAGES to run this target
	../l1-pull-image.sh "$(REMOTE_IMAGE_REGISTRY)" $(PULL_IMAGES)

run-tmp-image:
	@CID=$$(docker ps -f name=$(TMP_IMAGE_NAME) -q); \
	  test -z $$CID || (docker stop $$CID; sleep 5) ;
	$(MAKE) run CONTAINER_NAME=$(TMP_CONTAINER_NAME) IMAGE_NAME=$(TMP_IMAGE_NAME)

run-tmp-image-sh:
	@CID=$$(docker ps -f name=$(TMP_IMAGE_NAME) -q); \
	  test -z $$CID || (docker stop $$CID; sleep 5) ;
	$(MAKE) run-sh CONTAINER_NAME=$(TMP_CONTAINER_NAME) IMAGE_NAME=$(TMP_IMAGE_NAME)

commit-tmp-image:
	$(MAKE) commit CONTAINER_NAME=$(TMP_CONTAINER_NAME)
