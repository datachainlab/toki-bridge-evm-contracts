FROM tmp-toki-e2e-020-relayer

ARG L2RELAYERDIR=/toki/run-relayer
ARG L2TESTDIR=/toki/run-test
ARG TMPDIR=

USER root
COPY l2/ /toki/

ENV L2RELAYERDIR=${L2RELAYERDIR} L2TESTDIR=${L2TESTDIR}

RUN chmod 755 /toki/init.d/030-*.sh && \
    mkdir -p ${L2TESTDIR}/e2e && \
    chown -R 1000.1000 ${L2TESTDIR}

USER 1000
