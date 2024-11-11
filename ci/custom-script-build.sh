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

export HOME=/tmp #npm install uses git
git config --global --add safe.directory $WORKDIR

cd $WORKDIR/e2e/dind
make prepare SKIP_GIT=1
make container-image-registry
make image

docker tag toki-e2e-030-oneshot ${tag}
docker save -o $WORKDIR/${tag}.tar ${tag}
