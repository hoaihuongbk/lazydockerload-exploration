#!/bin/bash

# Generic run script for lazyload image testing
# Usage: ./scripts/nerdctl-run-lazyload-test.sh [suffix]
# Example: ./scripts/nerdctl-run-lazyload-test.sh airflow
#          ./scripts/nerdctl-run-lazyload-test.sh foo

set -e

SUFFIX="${1:-airflow}"
REGISTRY="localhost:5000"
IMAGE_NAME="test-$SUFFIX"
ESTARGZ_IMAGE="$REGISTRY/$IMAGE_NAME:estargz"
RESULTS_DIR="results"
PORT=8080

mkdir -p $RESULTS_DIR
> $RESULTS_DIR/startup-times.txt

run_with_snapshotter() {
  local snapshotter=$1
  local label=$2
  local cname="${IMAGE_NAME}-$(echo $label | tr ':' '-')"
  echo "[INFO] Removing local image $ESTARGZ_IMAGE for cold start..."
  nerdctl rmi $ESTARGZ_IMAGE > /dev/null 2>&1 || true
  echo "[INFO] Running $label: $ESTARGZ_IMAGE with snapshotter=$snapshotter and webserver ..."
  nerdctl --snapshotter=$snapshotter rm -f $cname > /dev/null 2>&1 || true
  local start_time=$(python3 -c 'import time; print(int(time.time() * 1000))')
  nerdctl --snapshotter=$snapshotter run -d --name $cname -p $PORT:8080 $ESTARGZ_IMAGE webserver > /dev/null

  local waited=0
  local max_wait=300
  while ! nc -z localhost $PORT; do
    sleep 1
    waited=$((waited+1))
    if [ $waited -ge $max_wait ]; then
      echo "[ERROR] Timeout waiting for webserver to start on port $PORT"
      nerdctl --snapshotter=$snapshotter logs $cname || true
      nerdctl --snapshotter=$snapshotter rm -f $cname || true
      echo "$label:TIMEOUT" >> $RESULTS_DIR/startup-times.txt
      return
    fi
  done

  local end_time=$(python3 -c 'import time; print(int(time.time() * 1000))')
  local startup_time_ms=$((end_time - start_time))
  local startup_time_sec=$(awk "BEGIN {printf \"%.3f\", ${startup_time_ms}/1000}")
  echo "$label:${startup_time_ms}ms (${startup_time_sec}s)" >> $RESULTS_DIR/startup-times.txt
  echo "[SUCCESS] $label ($ESTARGZ_IMAGE) webserver ready with $snapshotter: ${startup_time_ms}ms (${startup_time_sec}s)"
  nerdctl --snapshotter=$snapshotter stop $cname > /dev/null 2>&1 || true
}

echo "\n===== overlayfs + estargz image (no lazy loading) ====="
run_with_snapshotter overlayfs "overlayfs:estargz"

echo "\n===== stargz + estargz image (lazy loading) ====="
run_with_snapshotter stargz "stargz:estargz"

echo "\n[INFO] Startup time results:"
cat $RESULTS_DIR/startup-times.txt 