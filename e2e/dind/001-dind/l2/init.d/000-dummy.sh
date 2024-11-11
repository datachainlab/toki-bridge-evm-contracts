#!/bin/sh -e

case "x$1" in
  xstart)
    date
    uname -a
    ;;
  xstop)
    date
    uname -a
    ;;
esac
