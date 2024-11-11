#!/bin/sh -e

cd $(dirname $0)/init.d

case "x$1" in
  xstart )
    for f in $(find . -type f -executable -maxdepth 1 -name "*.sh" | sort); do
      date
      docker ps || true
      echo "--- L2 $f start ..."
      if [ ${f%-doas-root.sh} != $f ]; then
        doas $f start || exit 1
      else
        $f start || exit 1
      fi
      echo "--- L2 $f started"
    done
    ;;
  xstop )
    for f in $(find . -type f -executable -maxdepth 1 -name "*.sh" | sort -r ); do
      echo "--- L2 $f stop ..."
      if [ ${f%%-doas-root.sh} != $f ] ; then
        doas $f stop
      else
        $f stop
      fi
      echo "--- L2 $f stopped"
    done
    ;;
  * )
    echo "$0 <start | stop>"
    ;;
esac
