# Docker Image Snapshotter Comparison Makefile

.PHONY: help setup clean build run test results

help:
	@echo "Nerdctl Snapshotter Comparison"
	@echo "==============================="
	@echo ""
	@echo "Available commands:"
	@echo "  setup    - Setup environment (start registry in Colima, install nerdctl if needed)"
	@echo "  build    - Build the image with nerdctl (default: SUFFIX=airflow)"
	@echo "  run      - Run the image with overlayfs and stargz snapshotters (default: SUFFIX=airflow)"
	@echo "  build/<name> - Build the image for <name> (e.g., make build/airflow)"
	@echo "  run/<name>   - Run the image for <name> (e.g., make run/spark)"
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

setup:
	@echo "Setting up environment..."
	./scripts/setup.sh
	@echo "Setup complete."

build:
	@echo "Building the image with nerdctl (default compression)..."
	./scripts/nerdctl-build-lazyload-image.sh $(SUFFIX)

run:
	@echo "Running the image with overlayfs and stargz snapshotters..."
	./scripts/nerdctl-run-lazyload-test.sh $(SUFFIX)

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

build/%:
	$(MAKE) build SUFFIX=$*

run/%:
	$(MAKE) run SUFFIX=$*

test:
	@echo "[DEPRECATED] Use 'make build/<name>' and 'make run/<name>' instead."

results:
	@echo "=== Results Directory Contents ==="
	@ls -1 results/*.txt 2>/dev/null || echo "No result files found."
	@echo ""
	@for file in results/*.txt; do \
	  [ -f "$$file" ] && echo "=== $$(basename $$file) ===" && cat "$$file" && echo ""; \
	done 