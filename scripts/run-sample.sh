#!/bin/bash
set -e

REGISTRY="localhost:5000"
IMAGE_NAME="test-sample"
SNAPSHOTTER="${1:-overlayfs}"  # or stargz
TAG="standard"
if [ "$SNAPSHOTTER" = "stargz" ]; then
  TAG="estargz"
fi

IMAGE="$REGISTRY/$IMAGE_NAME:$TAG"
CNAME="${IMAGE_NAME}-${SNAPSHOTTER}"
RESULTS_DIR="results"
RESULT_FILE="$RESULTS_DIR/sample-startup-times.txt"

mkdir -p $RESULTS_DIR

# Remove any existing container
colima ssh -- sudo nerdctl rm -f $CNAME > /dev/null 2>&1 || true

# Force remove the image from local cache for a true cold start
colima ssh -- sudo nerdctl rmi -f $IMAGE > /dev/null 2>&1 || true

# Run the container (explicitly run cat /hello.txt)
START_TIME=$(python3 -c 'import time; print(int(time.time() * 1000))')
OUTPUT=$(colima ssh -- sudo nerdctl --storage-driver=$SNAPSHOTTER run --rm --name $CNAME $IMAGE cat /hello.txt)
END_TIME=$(python3 -c 'import time; print(int(time.time() * 1000))')
STARTUP_TIME_MS=$((END_TIME - START_TIME))
STARTUP_TIME_SEC=$(awk "BEGIN {printf \"%.3f\", ${STARTUP_TIME_MS}/1000}")
echo "[INFO] Output from container:"
echo "$OUTPUT"
echo "$SNAPSHOTTER:${STARTUP_TIME_MS}ms (${STARTUP_TIME_SEC}s)"
echo "$SNAPSHOTTER:${STARTUP_TIME_MS}ms (${STARTUP_TIME_SEC}s)" >> $RESULT_FILE 