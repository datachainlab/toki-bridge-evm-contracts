DIR=$(cd $(dirname ${BASH_SOURCE:-$0})/..; pwd)
ARCH=$(source $DIR/ci/arch.shsrc)
WORKDIR=/working # /working-<arch> volume is mounted on /working
echo "-- running ${BASH_SOURCE:-$0} on ${ARCH}..."

date

# Wait the dind (Docker in Docker) sidecar
until docker images
do
  sleep 3
done

cd $WORKDIR/e2e/dind
time docker load -i $WORKDIR/${tag}.tar
make run IMAGE_NAME=${tag}
docker ps

cd $WORKDIR/e2e/test
make setup

make citest

echo "-- done ${BASH_SOURCE:-$0} on ${ARCH}..."
