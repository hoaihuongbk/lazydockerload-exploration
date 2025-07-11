#!/bin/bash
set -e

# Setup script for Colima + containerd + stargz snapshotter + local registry
# Reference: https://github.com/abiosoft/colima/issues/1202

COLIMA_PROFILE="default"
REGISTRY_NAME="registry"
REGISTRY_PORT=5000

info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

# 1. Start Colima with containerd if not running
if ! colima status | grep -q 'Running'; then
  info "Starting Colima with containerd..."
  colima start --runtime containerd --profile "$COLIMA_PROFILE"
  success "Colima started."
else
  info "Colima is already running."
fi

# 2. Install and configure stargz-snapshotter
info "Installing and configuring stargz-snapshotter in Colima VM..."
colima ssh -- bash -c '
  set -e
  ARCH=$(uname -m)
  [ "$ARCH" = "x86_64" ] && ARCH=amd64
  [ "$ARCH" = "aarch64" ] && ARCH=arm64
  if ! command -v containerd-stargz-grpc >/dev/null 2>&1; then
    if command -v jq >/dev/null 2>&1; then
      VERSION=$(curl -s https://api.github.com/repos/containerd/stargz-snapshotter/releases/latest | jq -r .tag_name)
    else
      VERSION=$(curl -s https://api.github.com/repos/containerd/stargz-snapshotter/releases/latest | grep tag_name | cut -d\" -f4)
    fi
    if [ -z "$VERSION" ]; then
      echo "Failed to fetch stargz-snapshotter version!" >&2
      exit 1
    fi
    echo "Installing stargz-snapshotter version: $VERSION"
    DOWNLOAD_URL="https://github.com/containerd/stargz-snapshotter/releases/download/${VERSION}/stargz-snapshotter-${VERSION#v}-linux-${ARCH}.tar.gz"
    echo "Download URL: $DOWNLOAD_URL"
    curl -L -o /tmp/stargz-snapshotter.tar.gz "$DOWNLOAD_URL"
    sudo tar -C /usr/local/bin -xzf /tmp/stargz-snapshotter.tar.gz
    rm /tmp/stargz-snapshotter.tar.gz
    sudo chmod +x /usr/local/bin/containerd-stargz-grpc
  fi
  sudo mkdir -p /etc/containerd-stargz-grpc
  sudo tee /etc/containerd-stargz-grpc/config.toml > /dev/null <<EOF
[grpc]
address = "/run/containerd-stargz-grpc/containerd-stargz-grpc.sock"
EOF
  sudo tee /etc/systemd/system/stargz-snapshotter.service > /dev/null <<EOF
[Unit]
Description=stargz-snapshotter
After=network.target

[Service]
Type=notify
ExecStart=/usr/local/bin/containerd-stargz-grpc --log-level=debug --config=/etc/containerd-stargz-grpc/config.toml
Restart=always
RestartSec=1
StandardOutput=append:/tmp/stargz.log
StandardError=append:/tmp/stargz.log

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now stargz-snapshotter
'
success "stargz-snapshotter installed, configured, and service started."

# 3. Install and configure nydus-snapshotter
info "Installing and configuring nydus-snapshotter in Colima VM..."
colima ssh -- bash -c '
  set -e
  ARCH=$(uname -m)
  [ "$ARCH" = "x86_64" ] && ARCH=amd64
  [ "$ARCH" = "aarch64" ] && ARCH=arm64
  VERSION="v0.15.2"
  if ! command -v containerd-nydus-grpc >/dev/null 2>&1; then
    echo "Installing nydus-snapshotter version: $VERSION"
    DOWNLOAD_URL="https://github.com/containerd/nydus-snapshotter/releases/download/${VERSION}/nydus-snapshotter-${VERSION}-linux-${ARCH}.tar.gz"
    echo "Download URL: $DOWNLOAD_URL"
    curl -L -o /tmp/nydus-snapshotter.tar.gz "$DOWNLOAD_URL"
    echo "[DEBUG] Listing tarball contents before extraction:"
    tar -tzf /tmp/nydus-snapshotter.tar.gz
    sudo tar -C /tmp -xzf /tmp/nydus-snapshotter.tar.gz bin/containerd-nydus-grpc
    rm /tmp/nydus-snapshotter.tar.gz
    echo "[DEBUG] Listing all files in /tmp/bin after extraction:"
    ls -l /tmp/bin
    if [ ! -f /tmp/bin/containerd-nydus-grpc ]; then
      echo "[ERROR] containerd-nydus-grpc binary not found after extraction!" >&2
      exit 1
    fi
    sudo mv /tmp/bin/containerd-nydus-grpc /usr/local/bin/containerd-nydus-grpc
    sudo chmod +x /usr/local/bin/containerd-nydus-grpc
    echo "[DEBUG] Listing all files in /usr/local/bin after moving binary:"
    ls -l /usr/local/bin
  fi

  # Write FUSE config for nydusd (used by nydus-snapshotter)
  sudo mkdir -p /etc/nydus/
  sudo tee /etc/nydus/nydusd-config.fusedev.json > /dev/null <<EOF
{
  "device": {
    "backend": {
      "type": "registry",
      "config": {
        "scheme": "",
        "skip_verify": true,
        "timeout": 5,
        "connect_timeout": 5,
        "retry_limit": 4,
        "auth": ""
      }
    },
    "cache": {
      "type": "blobcache",
      "config": {
        "work_dir": "cache"
      }
    }
  },
  "mode": "direct",
  "digest_validate": false,
  "iostats_files": false,
  "enable_xattr": true,
  "fs_prefetch": {
    "enable": true,
    "threads_count": 4
  }
}
EOF
  # Update systemd service to use TOML config
  sudo tee /etc/systemd/system/nydus-snapshotter.service > /dev/null <<EOF
[Unit]
Description=nydus-snapshotter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/containerd-nydus-grpc --nydusd-config /etc/nydus/nydusd-config.fusedev.json --address /run/containerd-nydus-grpc/containerd-nydus-grpc.sock --log-level=debug --log-to-stdout
Restart=always
RestartSec=1
StandardOutput=append:/tmp/nydus.log
StandardError=append:/tmp/nydus.log

[Install]
WantedBy=multi-user.target
EOF
  # Ensure required directories exist and are writable
  sudo mkdir -p /var/lib/nydus/cache
  sudo mkdir -p /var/lib/containerd-nydus-grpc
  sudo chown -R root:root /var/lib/nydus/cache /var/lib/containerd-nydus-grpc
  sudo chmod -R 755 /var/lib/nydus/cache /var/lib/containerd-nydus-grpc
  sudo systemctl daemon-reload
  sudo systemctl enable --now nydus-snapshotter
'
success "nydus-snapshotter installed, configured, and service started."

# 3b. Install additional Nydus tools (nydus-image, nydusd, nydusify, nydusctl, nydus-overlayfs)
info "Installing additional Nydus tools in Colima VM..."
colima ssh -- bash -c '
  set -e
  NYDUS_VERSION="v2.2.0"
  ARCH=$(uname -m)
  [ "$ARCH" = "x86_64" ] && ARCH=amd64
  [ "$ARCH" = "aarch64" ] && ARCH=arm64
  NYDUS_URL="https://github.com/dragonflyoss/nydus/releases/download/${NYDUS_VERSION}/nydus-static-${NYDUS_VERSION}-linux-${ARCH}.tgz"
  echo "Downloading Nydus static tools from $NYDUS_URL ..."
  curl -L -o /tmp/nydus-static.tgz "$NYDUS_URL"
  echo "[DEBUG] Listing tarball contents before extraction:"
  tar -tzf /tmp/nydus-static.tgz
  for bin in nydus-image nydusd nydusify nydusctl nydus-overlayfs; do
    sudo tar -C /usr/local/bin -xzf /tmp/nydus-static.tgz nydus-static/$bin --strip-components=1
    sudo chmod +x /usr/local/bin/$bin
  done
  rm /tmp/nydus-static.tgz
  echo "[DEBUG] Listing all Nydus tools in /usr/local/bin:"
  ls -l /usr/local/bin/nydus*
'
success "Nydus tools installed."

# 4. Configure containerd to use stargz and nydus snapshotters as proxy_plugins
info "Configuring containerd to register stargz and nydus snapshotters..."
colima ssh -- bash -c '
  sudo mkdir -p /etc/containerd
  sudo tee /etc/containerd/config.toml > /dev/null <<EOF
[plugins."io.containerd.grpc.v1.cri".containerd]
  snapshotter = "stargz"
  disable_snapshot_annotations = false

[proxy_plugins]
  [proxy_plugins.stargz]
    type = "snapshot"
    address = "/run/containerd-stargz-grpc/containerd-stargz-grpc.sock"
  [proxy_plugins.nydus]
    type = "snapshot"
    address = "/run/containerd-nydus-grpc/containerd-nydus-grpc.sock"
EOF
  sudo systemctl restart containerd
'
success "containerd configured to use stargz and nydus snapshotters."

# 5. Start local registry inside Colima if not running
info "Ensuring local registry is running inside Colima..."
if ! colima ssh -- sudo nerdctl ps | grep -q "$REGISTRY_NAME"; then
  colima ssh -- sudo nerdctl run -d --name "$REGISTRY_NAME" -p "$REGISTRY_PORT":5000 --restart=unless-stopped registry:2
  success "Local registry started on port $REGISTRY_PORT."
else
  info "Local registry is already running."
fi

success "Environment setup complete!" 