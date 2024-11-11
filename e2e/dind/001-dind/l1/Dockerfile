#-----------------------------------------
# avoid "VOLUME /var/lib/docker" written in dind's Dockerfile
# https://github.com/docker/for-linux/issues/506
FROM mirror.gcr.io/docker:dind AS volume-in-docker

# custom-dind
RUN mkdir -p /var-lib-docker && touch /var-lib-docker/here-is-raw-filesystem

#-----------------------------------------
FROM volume-in-docker AS base

ARG TOKIDIND_DOCKER_DIR_MODE
ARG TOKIDIND_DOCKER_VOLUME_SIZE

# You can override these env before first run
ENV TOKIDIND_DOCKER_DIR_MODE=${TOKIDIND_DOCKER_DIR_MODE}
ENV TOKIDIND_DOCKER_VOLUME_SIZE=${TOKIDIND_DOCKER_VOLUME_SIZE}

RUN apk --no-cache add make git npm jq curl doas

# :wheel is now work?
#RUN echo 'permit nopass keepenv :wheel' >> /etc/doas.conf

RUN mkdir -p /etc/docker && printf '\
{ \n\
  "insecure-registries":[ "http://host:5000" ] \n\
}' > /etc/docker/daemon.json
# registry-mirros is not work?
#  ,"registry-mirrors": ["http://host:5000" ]

WORKDIR /toki
COPY l2/ /toki/
RUN mkdir -p /toki /toki/init.d /toki/conf.d /toki/status.d && \
    chmod a+w /toki/status.d && \
    find /toki -name "*.sh" | xargs chmod a+x

RUN /toki/createuser.sh dind 1000 1000

USER 1000
ENTRYPOINT /toki/entrypoint.sh
CMD []

#-----------------------------------------
FROM base AS insecure

ENV DOCKER_TLS_CERTDIR=""
ENV DOCKER_HOST=tcp://127.0.0.1:2375

#-----------------------------------------
FROM base AS tls

ENV DOCKER_TLS_VERIFY=1
ENV DOCKER_CERT_PATH=/certs/client/
ENV DOCKER_HOST=tcp://127.0.0.1:2376
