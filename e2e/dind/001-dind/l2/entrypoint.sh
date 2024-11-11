#!/bin/sh -e

TOKI_DIR=$(dirname $0)
INIT_START_FILE=${TOKI_DIR}/status.d/entrypoint-init-start
INIT_STOP_FILE=${TOKI_DIR}/status.d/entrypoint-init-stop
rm -f ${INIT_START_FILE} ${INIT_STOP_FILE}

INIT=${TOKI_DIR}/init.sh

${INIT} start
touch $INIT_START_FILE

WAIT=1

stop_for_commit() {
  echo "SIGUSR1 received."
  ${INIT} stop
  echo "entrypoint init stop finished"
  touch $INIT_STOP_FILE
  ps
}

term() {
  # no need to graceful shutdown
  echo "SIGTERM received."
  #${INIT} stop
  WAIT=0
}

trap stop_for_commit USR1
trap term TERM

echo "entrypoint init start finished"
docker ps
while [ $WAIT -ne 0 ]; do
  sleep 1
done
