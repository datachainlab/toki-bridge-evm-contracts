#FROM toki-e2e-001-dind
FROM tmp-toki-e2e-001-dind

ARG NAME=blockchain
#ARG GETH_IMAGE=

#ENV TOKIDIND_ETHEREUM_GETH_IMAGE=${GETH_IMAGE}

USER root
COPY l2/ /toki/

RUN chmod 755 /toki/init.d/010-ethereum-*.sh && \
    chown -R 1000:1000 /toki/run-ethereum

USER 1000
