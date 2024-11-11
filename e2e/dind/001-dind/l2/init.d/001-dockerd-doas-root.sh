#!/bin/sh -e

cd $(dirname $0)
. $(dirname $0)/common.shsrc

cd /
VOLUME_SIZE=${TOKIDIND_DOCKER_VOLUME_SIZE:-10G}
MY_DOCKER_DIR=/var-lib-docker
MY_DOCKER_FILE=${MY_DOCKER_DIR}.loopback.ext4

case "x$TOKIDIND_DOCKER_DIR_MODE" in
  xloopback | xindocker | xhost)
    echo "TOKIDIND_DOCKER_DIR_MODE=${TOKIDIND_DOCKER_DIR_MODE}"
    ;;
  *)
    echo "set TOKIDIND_DOCKER_DIR_MODE"
    exit 1
    ;;
esac

if [ $(id -u) != 0 ]; then
  echo "should run by root"
  exit 1
fi

use_indocker() {
  if [ ! -e ${MY_DOCKER_DIR}/here-is-raw-filesystem ]; then
    echo "${MY_DOCKER_DIR} is not setup correctly"
    exit 1
  fi
}
mount_loopback() {
  if [ ! -e ${MY_DOCKER_FILE} ]; then
    echo "creating ${VOLUME_SIZE} file for docker..."
    dd of=${MY_DOCKER_FILE} bs=1 seek=${VOLUME_SIZE} count=0
    /sbin/mkfs.ext4 -q ${MY_DOCKER_FILE}
  fi
  if [ -e ${MY_DOCKER_DIR}/here-is-raw-filesystem ]; then
    mount -t ext4 -o loop ${MY_DOCKER_FILE} ${MY_DOCKER_DIR}
  fi
  if [ -e ${MY_DOCKER_DIR}/here-is-raw-filesystem ]; then
    echo "fail to mount"
    exit 1
  fi
}
umount_loopback() {
  # ??? umount causes "fail to mount: read only file system" in next startup ???
  #umount -d ${MY_DOCKER_DIR}
  #echo "umount ${MY_DOCKER_DIR}"
  ls -l ${MY_DOCKER_DIR}
}
shrink_loopback() {
  SIZE=$1
  fsck.ext4 -y -f ${MY_DOCKER_FILE}
  resize2fs ${MY_DOCKER_FILE} ${SIZE}
  truncate -s ${SIZE} ${MY_DOCKER_FILE}
  rm -f /trim-ext4-on-next-start.txt
}

wait_docker_start() {
  n=0
  while true; do
    if docker info > /dev/null 2>&1; then
      break
    fi
    n=$(( $n + 1 ))
    if [ $n -gt 60  ]; then
      echo 'giving up docker daemon start...'
      exit 1
    fi
    echo 'waiting docker daemon start...'
    sleep 5
  done
  echo 'docker daemon has started.'
}

wait_docker_stop() {
  if [ -e /var/run/docker.pid ]; then
    kill $(cat /var/run/docker.pid)
    while true; do
      if [ ! -e /var/run/docker.pid ]; then
        break
      fi
      echo 'waiting docker daemon is stop...'
      sleep 5
    done
  fi
  echo 'docker daemon has stopped.'
}

case "x$1" in
  xstart)
    case "x$TOKIDIND_DOCKER_DIR_MODE" in
      xloopback)
        mount_loopback
        DIR_MODE_OPT="--data-root=${MY_DOCKER_DIR} --storage-driver=overlay2"
        ;;
      xindocker)
        use_indocker
        DIR_MODE_OPT="--data-root=${MY_DOCKER_DIR}"
        ;;
      xhost)
        DIR_MODE_OPT=""
        ;;
      *)
        echo "set TOKI_DOCKER_DIR_MODE"
        exit 1
        ;;
    esac
    LOGFILE=${STAT_DIR}/${INIT_SCRIPT_BASENAME}.log
    echo dockerd-entrypoint.sh $DIR_MODE_OPT
    nohup dockerd-entrypoint.sh $DIR_MODE_OPT >${LOGFILE} 2>&1 &
    sleep 3
    tail -f $LOGFILE &
    wait_docker_start
    ;;

  xstop)
    wait_docker_stop
    case "x$TOKI_DOCKER_DIR_MODE" in
      xloopback)
        umount_loopback
        if [ -e /trim-ext4-on-next-start.txt ]; then
          shrink_loopback "$(cat /trim-ext4-on-next-start.txt)G"
          rm -f /trim-ext4-on-next-start.txt
        fi
        ;;
    esac
    ps
    ;;
esac
