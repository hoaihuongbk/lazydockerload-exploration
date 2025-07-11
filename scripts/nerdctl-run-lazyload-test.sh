#!/bin/bash

# Generic run script for lazyload image testing
# Usage: ./scripts/nerdctl-run-lazyload-test.sh [suffix] [port] [entrypoint]
# Example: ./scripts/nerdctl-run-lazyload-test.sh airflow 8080 webserver
#          ./scripts/nerdctl-run-lazyload-test.sh spark-connect 15002 ""

set -e

SUFFIX="${1:-airflow}"
PORT="${2:-8080}"
ENTRYPOINT="${3:-webserver}"
REGISTRY="localhost:5000"
IMAGE_NAME="test-$SUFFIX"
ESTARGZ_IMAGE="$REGISTRY/$IMAGE_NAME:estargz"
RESULTS_DIR="results"

mkdir -p $RESULTS_DIR
> $RESULTS_DIR/${SUFFIX}-startup-times.txt

run_with_snapshotter() {
  local snapshotter=$1
  # Use snapshotter for container name and result label
  local cname="${IMAGE_NAME}-${snapshotter}"
  # Select the correct image tag based on snapshotter
  local image_tag=""
  if [ "$snapshotter" = "overlayfs" ]; then
    image_tag="$REGISTRY/$IMAGE_NAME:standard"
  elif [ "$snapshotter" = "stargz" ]; then
    image_tag="$REGISTRY/$IMAGE_NAME:estargz"
  else
    echo "[ERROR] Unknown snapshotter: $snapshotter"
    exit 1
  fi
  # By default, do NOT remove the image (warm start). Only remove for cold start if FORCE_RMI=1 is set.
  if [ -n "$FORCE_RMI" ]; then
    echo "[INFO] FORCE_RMI is set, removing local image $image_tag for cold start..."
    nerdctl rmi $image_tag > /dev/null 2>&1 || true
  else
    echo "[INFO] Not removing image (default: warm start mode)"
  fi
  # Remove any existing container with the same name
  echo "[INFO] Removing any existing container named $cname ..."
  nerdctl --snapshotter=$snapshotter rm -f $cname > /dev/null 2>&1 || true
  echo "[INFO] Running $snapshotter: $image_tag with snapshotter=$snapshotter ..."
  local start_time=$(python3 -c 'import time; print(int(time.time() * 1000))')
  if [ -z "$ENTRYPOINT" ]; then
    nerdctl --snapshotter=$snapshotter run -d --name $cname -p $PORT:$PORT $image_tag > /dev/null
  else
    nerdctl --snapshotter=$snapshotter run -d --name $cname -p $PORT:$PORT $image_tag $ENTRYPOINT > /dev/null
  fi

  local waited=0
  local max_wait=300
  local ready=0

  if [ "$SUFFIX" = "airflow" ]; then
    # For Airflow, check if the metadatabase is healthy using the /health endpoint
    echo "[INFO] Waiting for Airflow metadatabase to be healthy on port $PORT..."
    while ! curl -sf "http://localhost:$PORT/health" | grep -q '"metadatabase": *{"status": *"healthy"'; do
      sleep 1
      waited=$((waited+1))
      if [ $waited -ge $max_wait ]; then
        echo "[ERROR] Timeout waiting for Airflow metadatabase to be healthy on port $PORT"
        nerdctl --snapshotter=$snapshotter logs $cname || true
        nerdctl --snapshotter=$snapshotter rm -f $cname || true
        echo "$snapshotter:TIMEOUT" >> $RESULTS_DIR/${SUFFIX}-startup-times.txt
        return
      fi
    done
    ready=1
  elif [ "$SUFFIX" = "spark-connect" ]; then
    # For Spark Connect, use the Python client script to check readiness and measure time
    echo "[INFO] Waiting for Spark Connect server to be ready by running client script..."
    if ! command -v uv >/dev/null 2>&1; then
      echo "[ERROR] 'uv' is not installed. Please install it with 'pip install uv' or 'brew install uv'."
      nerdctl --snapshotter=$snapshotter logs $cname || true
      nerdctl --snapshotter=$snapshotter rm -f $cname || true
      echo "$snapshotter:UV_NOT_INSTALLED" >> $RESULTS_DIR/${SUFFIX}-startup-times.txt
      return
    fi
    # Use a unique virtual environment per snapshotter
    VENV_NAME=".venv-$snapshotter"
    uv venv $VENV_NAME
    . $VENV_NAME/bin/activate
    uv pip install -r requirements-client.txt
    # Try up to max_wait seconds to connect
    while true; do
      uv run scripts/test_spark_connect_client.py > .spark_connect_client.log 2>&1 && ready=1 && break
      sleep 1
      waited=$((waited+1))
      if [ $waited -ge $max_wait ]; then
        echo "[ERROR] Timeout waiting for Spark Connect server to be ready (client could not connect)"
        cat .spark_connect_client.log
        nerdctl --snapshotter=$snapshotter logs $cname || true
        nerdctl --snapshotter=$snapshotter rm -f $cname || true
        echo "$snapshotter:TIMEOUT" >> $RESULTS_DIR/${SUFFIX}-startup-times.txt
        deactivate
        return
      fi
    done
    # If ready, append the client log to the results file
    cat .spark_connect_client.log | tee -a $RESULTS_DIR/${SUFFIX}-startup-times.txt
    deactivate
  else
    echo "[ERROR] Unknown SUFFIX: $SUFFIX. Cannot determine startup check method."
    nerdctl --snapshotter=$snapshotter logs $cname || true
    nerdctl --snapshotter=$snapshotter rm -f $cname || true
    echo "$snapshotter:UNKNOWN_SUFFIX" >> $RESULTS_DIR/${SUFFIX}-startup-times.txt
    return
  fi

  if [ $ready -eq 1 ]; then
    local end_time=$(python3 -c 'import time; print(int(time.time() * 1000))')
    local startup_time_ms=$((end_time - start_time))
    local startup_time_sec=$(awk "BEGIN {printf \"%.3f\", ${startup_time_ms}/1000}")
    echo "$snapshotter:${startup_time_ms}ms (${startup_time_sec}s)" >> $RESULTS_DIR/${SUFFIX}-startup-times.txt
    echo "[SUCCESS] $snapshotter ($image_tag) service ready with $snapshotter: ${startup_time_ms}ms (${startup_time_sec}s)"
    nerdctl --snapshotter=$snapshotter stop $cname > /dev/null 2>&1 || true
  fi
}

echo "\n===== overlayfs + standard image (no lazy loading) ====="
run_with_snapshotter overlayfs

echo "\n===== stargz + estargz image (lazy loading) ====="
run_with_snapshotter stargz

echo "\n[INFO] Startup time results:"
cat $RESULTS_DIR/${SUFFIX}-startup-times.txt 

# Remove redundant Spark Connect client test after the main run_with_snapshotter loop 