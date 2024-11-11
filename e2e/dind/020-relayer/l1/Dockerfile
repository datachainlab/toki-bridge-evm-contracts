FROM tmp-toki-e2e-011-bnb

ARG L2RUNDIR=/toki/run-relayer
ARG TMPDIR=

USER root
COPY l2/ /toki/
COPY ${TMPDIR}/pull-image.txt /toki/conf.d/020-relayer-01-pull-image.txt
COPY ${TMPDIR}/e2e/ ${L2RUNDIR}

RUN chmod 755 /toki/init.d/020-*.sh && \
    chown -R 1000.1000 ${L2RUNDIR}

USER 1000
