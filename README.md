# Docker Image Lazy Loading Test Suite

This repository provides a generic framework to test and compare lazy loading performance for container images using [eStargz](https://github.com/containerd/stargz-snapshotter) and the stargz snapshotter in Colima/containerd. It supports any Dockerfile by simple parameterization.

## Project Structure

```
.
├── dockerfiles/           # Dockerfile.<name> definitions (e.g., Dockerfile.airflow, Dockerfile.spark)
├── scripts/               # Build and run scripts (generic, parameterized)
├── test-data/             # Test data and configurations
└── results/               # Test results and measurements
```

## Prerequisites
- [Colima](https://github.com/abiosoft/colima) (with containerd)
- [nerdctl](https://github.com/containerd/nerdctl)
- GNU Make
- (Optional) Docker, for building images locally

## Quick Start

```bash
# 1. Setup Colima with stargz snapshotter and local registry
make setup

# 2. Build and run a test image (default: airflow)
make build/airflow
make run/airflow

# 3. For another image (e.g., spark), add dockerfiles/Dockerfile.spark, then:
make build/spark
make run/spark

# 4. View results
make results

# 5. Clean up
make clean
```

## How It Works
- **Build**: Builds and converts the image to eStargz format, pushes to local registry.
- **Run**: Runs the image with both overlayfs and stargz snapshotters, measures startup time.
- **Results**: All results are saved in the `results/` directory and can be viewed with `make results`.

## Adding a New Test Case
1. Create a new Dockerfile: `dockerfiles/Dockerfile.<name>`
2. Run: `make build/<name> && make run/<name>`

## Results
- All results are stored in `results/` as `.txt` files.
- Use `make results` to view all results.

## Troubleshooting
- Ensure Colima is running with containerd and the stargz snapshotter is enabled.
- If you encounter issues, rerun `make setup`. 