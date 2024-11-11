#!/bin/sh -e

cd $(dirname $0)
. ./common.shsrc

CONF_FILE=${CONF_DIR}/$(basename $0 .sh).txt

case "x$1" in
  xstart)
    for i in $(cat $CONF_FILE); do
      /toki/pull-image.sh $i
    done
    ;;

  xstop)
    ;;
esac
