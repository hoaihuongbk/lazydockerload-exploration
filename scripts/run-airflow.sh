#!/bin/bash
set -e

REGISTRY="localhost:5000"
IMAGE_NAME="test-airflow"
SNAPSHOTTER="${1:-overlayfs}"  # or stargz
PORT="${2:-8080}"
TAG="standard"
if [ "$SNAPSHOTTER" = "stargz" ]; then
  TAG="estargz"
elif [ "$SNAPSHOTTER" = "nydus" ]; then
  TAG="nydus"
fi

IMAGE="$REGISTRY/$IMAGE_NAME:$TAG"
CNAME="${IMAGE_NAME}-${SNAPSHOTTER}"
RESULTS_DIR="results"
RESULT_FILE="$RESULTS_DIR/airflow-startup-times.txt"

mkdir -p $RESULTS_DIR

# Remove any existing container
colima ssh -- sudo nerdctl rm -f $CNAME > /dev/null 2>&1 || true

# Force remove the image from local cache for a true cold start
colima ssh -- sudo nerdctl rmi -f $IMAGE > /dev/null 2>&1 || true

# Run the container and measure time for 'airflow version'
START_TIME=$(python3 -c 'import time; print(int(time.time() * 1000))')
case "$SNAPSHOTTER" in
  overlayfs) HOST_PORT=8080 ;;
  stargz)    HOST_PORT=8081 ;;
  nydus)     HOST_PORT=8082 ;;
  *)         HOST_PORT=8080 ;;
esac
colima ssh -- sudo nerdctl --storage-driver=$SNAPSHOTTER run -d --name $CNAME -p $HOST_PORT:8080 $IMAGE > /dev/null
END_TIME=$(python3 -c 'import time; print(int(time.time() * 1000))')
STARTUP_TIME_MS=$((END_TIME - START_TIME))
STARTUP_TIME_SEC=$(awk "BEGIN {printf \"%.3f\", ${STARTUP_TIME_MS}/1000}")
echo "$IMAGE_NAME:$TAG:${STARTUP_TIME_MS}ms (${STARTUP_TIME_SEC}s)" | tee -a $RESULT_FILE 