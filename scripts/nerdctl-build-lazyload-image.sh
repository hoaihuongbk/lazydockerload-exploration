#!/bin/bash

# Generic build script for lazyload image testing
# Usage: ./scripts/nerdctl-build-lazyload-image.sh [suffix]
# Example: ./scripts/nerdctl-build-lazyload-image.sh airflow
#          ./scripts/nerdctl-build-lazyload-image.sh foo

set -e

SUFFIX="${1:-airflow}"
REGISTRY="localhost:5000"
IMAGE_NAME="test-$SUFFIX"
STANDARD_IMAGE="$REGISTRY/$IMAGE_NAME:standard"
ESTARGZ_IMAGE="$REGISTRY/$IMAGE_NAME:estargz"
NYDUS_IMAGE="$REGISTRY/$IMAGE_NAME:nydus"
RESULTS_DIR="results"
DOCKERFILE="dockerfiles/Dockerfile.$SUFFIX"

mkdir -p $RESULTS_DIR

echo "[INFO] Building standard image $STANDARD_IMAGE using $DOCKERFILE ..."
colima ssh -- sudo nerdctl build -f $DOCKERFILE -t $STANDARD_IMAGE .

echo "[INFO] Converting standard image to eStargz format as $ESTARGZ_IMAGE ..."
colima ssh -- sudo nerdctl image convert --estargz --oci $STANDARD_IMAGE $ESTARGZ_IMAGE

echo "[INFO] Converting standard image to Nydus format as $NYDUS_IMAGE ..."
colima ssh -- sudo nerdctl image convert --nydus --oci $STANDARD_IMAGE $NYDUS_IMAGE

echo "[INFO] Pushing standard image $STANDARD_IMAGE to registry ..."
colima ssh -- sudo nerdctl push $STANDARD_IMAGE

echo "[INFO] Pushing eStargz image $ESTARGZ_IMAGE to registry ..."
colima ssh -- sudo nerdctl push $ESTARGZ_IMAGE

echo "[INFO] Pushing Nydus image $NYDUS_IMAGE to registry ..."
colima ssh -- sudo nerdctl push $NYDUS_IMAGE

# echo "[INFO] Verifying Nydus image with nydusify check ..."
# colima ssh -- sudo nydusify check --source $STANDARD_IMAGE --target $NYDUS_IMAGE || { echo "[ERROR] nydusify check failed"; exit 1; }

echo "[SUCCESS] All $STANDARD_IMAGE, $ESTARGZ_IMAGE, $NYDUS_IMAGE built and pushed." 