# Docker Image Snapshotter Comparison Makefile

PORT ?= 8080

.PHONY: help setup clean build run/airflow run/spark-connect run/sample results

help:
	@echo "Nerdctl Snapshotter Comparison"
	@echo "==============================="
	@echo ""
	@echo "Available commands:"
	@echo "  setup    - Setup environment (start registry in Colima, install nerdctl if needed)"
	@echo "  build    - Build the image with nerdctl (default: SUFFIX=airflow)"
	@echo "  build/<name> - Build the image for <name> (e.g., make build/airflow)"
	@echo "  run/airflow       - Run Airflow image with overlayfs, stargz, and nydus snapshotters"
	@echo "  run/spark-connect - Run Spark Connect image with overlayfs, stargz, and nydus snapshotters"
	@echo "  run/sample        - Run Sample image with overlayfs, stargz, and nydus snapshotters"
	@echo "  results  - Show test results"
	@echo "  clean    - Clean up test images, containers, and results"
	@echo "  help     - Show this help message"
	@echo ""
	@echo "Quick start:"
	@echo "  make setup"
	@echo "  make build/airflow && make run/airflow"
	@echo "  make results"
	@echo ""
	@echo "To use a different Dockerfile and image, use e.g. make build/foo, make run/spark, etc."
	@echo "To override the port, use e.g. make run/spark-connect PORT=15002"

setup:
	@echo "Setting up environment..."
	sh scripts/setup.sh
	@echo "Setup complete."

build:
	@echo "Building the image with nerdctl (default compression)..."
	./scripts/nerdctl-build-lazyload-image.sh $(SUFFIX)

build/%:
	$(MAKE) build SUFFIX=$*

run/airflow:
	@echo "Running Airflow image with overlayfs, stargz, and nydus snapshotters..."
	@rm -f results/airflow-startup-times.txt
	@touch results/airflow-startup-times.txt
	bash scripts/run-airflow.sh overlayfs 8080
	bash scripts/run-airflow.sh stargz 8080
	bash scripts/run-airflow.sh nydus 8080

run/spark-connect:
	@echo "Running Spark Connect image with overlayfs, stargz, and nydus snapshotters..."
	@rm -f results/spark-connect-startup-times.txt
	@touch results/spark-connect-startup-times.txt
	uv venv .venv-spark-connect
	. .venv-spark-connect/bin/activate && uv pip install -r requirements-client.txt
	bash scripts/run-spark-connect.sh overlayfs 15002
	bash scripts/run-spark-connect.sh stargz 15012
	# bash scripts/run-spark-connect.sh nydus 15022

run/sample:
	@echo "Running Sample image with overlayfs, stargz, and nydus snapshotters..."
	@rm -f results/sample-startup-times.txt
	@touch results/sample-startup-times.txt
	bash scripts/run-sample.sh overlayfs
	bash scripts/run-sample.sh stargz
	bash scripts/run-sample.sh nydus

results:
	@echo "=== Results Directory Contents ==="
	@ls -1 results/*.txt 2>/dev/null || echo "No result files found."
	@echo ""
	@for file in results/*.txt; do \
	  [ -f "$$file" ] && echo "=== $$(basename $$file) ===" && cat "$$file" && echo ""; \
	done

clean:
	@echo "Cleaning up test images, containers, and results..."
	nerdctl ps -a --format '{{.Names}}' | grep '^test-' | xargs -r nerdctl rm -f 2>/dev/null || true
	nerdctl images --format '{{.Repository}}:{{.Tag}}' | grep '^localhost:5000/test-' | xargs -r nerdctl rmi -f 2>/dev/null || true
	@rm -f results/*.txt
	@echo "Cleanup completed" 