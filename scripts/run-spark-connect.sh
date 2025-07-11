#!/bin/bash
set -e

REGISTRY="localhost:5000"
IMAGE_NAME="test-spark-connect"
SNAPSHOTTER="${1:-overlayfs}"  # or stargz
PORT="${2:-15002}"
TAG="standard"
if [ "$SNAPSHOTTER" = "stargz" ]; then
  TAG="estargz"
fi

IMAGE="$REGISTRY/$IMAGE_NAME:$TAG"
CNAME="${IMAGE_NAME}-${SNAPSHOTTER}"
RESULTS_DIR="results"
RESULT_FILE="$RESULTS_DIR/spark-connect-startup-times.txt"

mkdir -p $RESULTS_DIR

# Remove any existing container
colima ssh -- sudo nerdctl rm -f $CNAME > /dev/null 2>&1 || true

# Force remove the image from local cache for a true cold start
colima ssh -- sudo nerdctl rmi -f $IMAGE > /dev/null 2>&1 || true

# Run the container
START_TIME=$(python3 -c 'import time; print(int(time.time() * 1000))')
colima ssh -- sudo nerdctl --storage-driver=$SNAPSHOTTER run -d --name $CNAME -p $PORT:$PORT $IMAGE > /dev/null

waited=0
max_wait=300
ready=0

# Use a unique virtual environment per snapshotter
VENV_NAME=".venv-$SNAPSHOTTER"
uv venv $VENV_NAME
. $VENV_NAME/bin/activate
uv pip install -r requirements-client.txt

# Try up to max_wait seconds to connect
while true; do
  uv run scripts/test_spark_connect_client.py > .spark_connect_client.log 2>&1 && ready=1 && break
  sleep 1
  waited=$((waited+1))
  if [ $waited -ge $max_wait ]; then
    echo "[ERROR] Timeout waiting for Spark Connect server to be ready (client could not connect)" | tee -a $RESULT_FILE
    cat .spark_connect_client.log
    colima ssh -- sudo nerdctl logs $CNAME || true
    colima ssh -- sudo nerdctl rm -f $CNAME || true
    echo "$SNAPSHOTTER:TIMEOUT" | tee -a $RESULT_FILE
    deactivate
    exit 1
  fi
done

cat .spark_connect_client.log

deactivate

if [ $ready -eq 1 ]; then
  END_TIME=$(python3 -c 'import time; print(int(time.time() * 1000))')
  STARTUP_TIME_MS=$((END_TIME - START_TIME))
  STARTUP_TIME_SEC=$(awk "BEGIN {printf \"%.3f\", ${STARTUP_TIME_MS}/1000}")
  echo "$SNAPSHOTTER:${STARTUP_TIME_MS}ms (${STARTUP_TIME_SEC}s)" | tee -a $RESULT_FILE
  colima ssh -- sudo nerdctl stop $CNAME > /dev/null 2>&1 || true
fi 