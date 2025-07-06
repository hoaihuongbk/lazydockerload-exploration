# Docker Image Compression Comparison Test

This repository tests and compares different compression methods for Docker images to determine which provides the best balance of image size, build time, and load time.

## What We're Testing

We compare four compression scenarios:
1. **No compression** - Standard Docker image format
2. **Gzip** - Traditional compression used by Docker
3. **Zstd** - Modern compression algorithm with better compression ratios
4. **Pigz** - Parallel gzip for faster compression/decompression

## Project Structure

```
.
├── dockerfiles/           # Dockerfile definitions
├── scripts/              # Test and measurement scripts
├── k8s/                  # Kubernetes manifests for testing
├── test-data/            # Test data and configurations
└── results/              # Test results and measurements
```

## Prerequisites

1. **Docker**: Latest version with multi-platform support
2. **Docker Buildx**: For advanced build features
3. **Kubernetes cluster** (Minikube/Docker Desktop): For deployment testing
4. **Benchmarking tools**: For accurate measurements

## Quick Start

1. **Build images with different compression methods**:
   ```bash
   ./scripts/build-compression-test-images.sh
   ```

2. **Run comprehensive comparison tests**:
   ```bash
   ./scripts/run-compression-comparison.sh
   ```

3. **View results**:
   ```bash
   cat results/compression-comparison-results.txt
   ```

## Testing Methodology

### 1. Image Size Analysis
- Build identical images with different compression methods
- Compare total image size and layer sizes
- Analyze compression ratios

### 2. Build Time Measurement
- Measure time to build images with each compression method
- Account for compression overhead
- Test on different hardware configurations

### 3. Load Time Testing
- Measure time from `docker pull` to image ready
- Test in Kubernetes environment
- Measure memory usage during image loading

### 4. Runtime Performance
- Deploy to Kubernetes and measure startup time
- Monitor resource usage during container initialization
- Test with actual application workload (Airflow)

## Compression Methods Compared

### No Compression
- **Pros**: Fastest build time, no compression overhead
- **Cons**: Largest image size, slower network transfers

### Gzip
- **Pros**: Widely supported, good compression ratio
- **Cons**: Slower compression/decompression, single-threaded

### Zstd
- **Pros**: Excellent compression ratio, fast decompression
- **Cons**: Newer format, may not be supported everywhere

### Pigz
- **Pros**: Parallel compression, faster than gzip
- **Cons**: Still gzip format limitations, parallel overhead

## Expected Benefits

- **Optimized image sizes**: Choose best compression for your use case
- **Faster deployments**: Balance compression vs. load time
- **Cost savings**: Reduced storage and bandwidth costs
- **Better CI/CD**: Faster builds and deployments

## Monitoring and Metrics

The test suite measures:
- Image build time
- Image size (compressed and uncompressed)
- Image pull time
- Container startup time
- Memory usage during loading
- CPU usage during compression/decompression

## Results Interpretation

Results are stored in `results/` directory with:
- Timing measurements for each compression method
- Size comparisons and compression ratios
- Performance graphs and charts
- Recommendations for different use cases

## Use Cases

- **Development**: No compression for fastest builds
- **CI/CD**: Zstd for good balance of size and speed
- **Production**: Zstd or Pigz depending on infrastructure support
- **Edge deployments**: Gzip for maximum compatibility

## Troubleshooting

See `TROUBLESHOOTING.md` for common issues and solutions. 