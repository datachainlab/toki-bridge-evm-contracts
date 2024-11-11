#!/bin/sh -ex

if [ "x$3" = "x" ]; then
  echo "$0 <user name> <user id> <group id>"
  exit 1
fi

USER_NAME=$1
USER_ID=$2
GROUP_ID=$3

if [ ! id ${USER_NAME} ]; then
  exit 1
fi

addgroup -g ${GROUP_ID} ${USER_NAME}
adduser  -u ${USER_ID} -G ${USER_NAME} -D -h "/home/${USER_NAME}" ${USER_NAME}
addgroup ${USER_NAME} docker
# addgroup ${USER_NAME} wheel # :wheel is not working in doas.conf?
echo "permit nopass keepenv ${USER_NAME}" >> /etc/doas.conf
