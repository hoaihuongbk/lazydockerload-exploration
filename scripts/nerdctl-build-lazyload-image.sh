#!/bin/bash

# Generic build script for lazyload image testing
# Usage: ./scripts/nerdctl-build-lazyload-image.sh [suffix]
# Example: ./scripts/nerdctl-build-lazyload-image.sh airflow
#          ./scripts/nerdctl-build-lazyload-image.sh foo

set -e

SUFFIX="${1:-airflow}"
REGISTRY="localhost:5000"
IMAGE_NAME="test-$SUFFIX"
ESTARGZ_IMAGE="$REGISTRY/$IMAGE_NAME:estargz"
RESULTS_DIR="results"
DOCKERFILE="dockerfiles/Dockerfile.$SUFFIX"

mkdir -p $RESULTS_DIR

echo "[INFO] Building image $ESTARGZ_IMAGE using $DOCKERFILE ..."
nerdctl build -f $DOCKERFILE -t $ESTARGZ_IMAGE .

echo "[INFO] Converting image to eStargz format ..."
nerdctl image convert --estargz --oci $ESTARGZ_IMAGE $ESTARGZ_IMAGE

echo "[INFO] Pushing image $ESTARGZ_IMAGE to registry ..."
nerdctl push $ESTARGZ_IMAGE

echo "[SUCCESS] Image $ESTARGZ_IMAGE built and pushed." 