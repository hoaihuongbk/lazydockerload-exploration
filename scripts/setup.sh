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
  colima start --runtime containerd --profile $COLIMA_PROFILE
  success "Colima started."
else
  info "Colima is already running."
fi

# 2. Download and install the latest stargz-snapshotter, configure, and enable service
info "Installing and configuring stargz-snapshotter in Colima VM..."
colima ssh -- bash -c '
  set -e
  ARCH=$(uname -m)
  if [ "$ARCH" = "x86_64" ]; then ARCH=amd64; fi
  if [ "$ARCH" = "aarch64" ]; then ARCH=arm64; fi
  VERSION=$(curl -s https://api.github.com/repos/containerd/stargz-snapshotter/releases/latest | grep tag_name | cut -d" -f4)
  curl -L -o /tmp/stargz-snapshotter.tar.gz https://github.com/containerd/stargz-snapshotter/releases/download/${VERSION}/stargz-snapshotter-${VERSION#v}-linux-${ARCH}.tar.gz
  sudo tar -C /usr/local/bin -xzf /tmp/stargz-snapshotter.tar.gz
  rm /tmp/stargz-snapshotter.tar.gz
  sudo chmod +x /usr/local/bin/containerd-stargz-grpc

  # Minimal config for stargz-snapshotter
  sudo mkdir -p /etc/containerd-stargz-grpc
  sudo tee /etc/containerd-stargz-grpc/config.toml > /dev/null <<EOF
[grpc]
address = "/run/containerd-stargz-grpc/containerd-stargz-grpc.sock"
EOF

  # Minimal systemd service for stargz-snapshotter with log redirection
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

  # Configure containerd to use stargz snapshotter
  sudo tee /etc/containerd/config.toml > /dev/null <<EOF
[plugins."io.containerd.grpc.v1.cri".containerd]
  snapshotter = "stargz"
  disable_snapshot_annotations = false

[proxy_plugins]
  [proxy_plugins.stargz]
    type = "snapshot"
    address = "/run/containerd-stargz-grpc/containerd-stargz-grpc.sock"
EOF

  sudo systemctl restart containerd
'
success "stargz-snapshotter installed, configured, and service started. Containerd configured."

# 3. Start local registry inside Colima if not running
info "Ensuring local registry is running inside Colima..."
if ! colima ssh -- sudo nerdctl ps | grep -q "$REGISTRY_NAME"; then
  colima ssh -- sudo nerdctl run -d --name $REGISTRY_NAME -p $REGISTRY_PORT:5000 --restart=unless-stopped registry:2
  success "Local registry started on port $REGISTRY_PORT."
else
  info "Local registry is already running."
fi

success "Environment setup complete!" 