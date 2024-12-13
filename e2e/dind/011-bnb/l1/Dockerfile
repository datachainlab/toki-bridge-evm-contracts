#FROM toki-e2e-001-dind
FROM tmp-toki-e2e-010-ethereum

ARG L2RUNDIR=/toki/run-bnb
ARG TMPDIR=

USER root
COPY l2/ /toki/
COPY ${TMPDIR}/pull-image.txt /toki/conf.d/011-bnb-01-pull-image.txt
COPY ${TMPDIR}/e2e/ ${L2RUNDIR}

RUN chmod 755 /toki/init.d/011-*.sh && \
    chown -R 1000:1000 ${L2RUNDIR}

USER 1000
