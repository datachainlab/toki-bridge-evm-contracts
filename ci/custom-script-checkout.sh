echo "-- running ${BASH_SOURCE:-$0}..."

date

make -C e2e git SKIP_SUBMODULE=1 GIT_HTTPS=1
