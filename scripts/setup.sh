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

# 2. Enable stargz snapshotter in Colima's Lima VM
info "Configuring stargz snapshotter in Colima VM..."
colima ssh -- bash -c '
  set -e
  sudo mkdir -p /etc/containerd
  sudo mkdir -p /etc/containerd-stargz-grpc/
  sudo sh -c "cat > /etc/containerd/config.toml" <<EOF
version = 2
[plugins."io.containerd.grpc.v1.cri".containerd]
  snapshotter = \"stargz\"
  disable_snapshot_annotations = false
[proxy_plugins]
  [proxy_plugins.stargz]
    type = \"snapshot\"
    address = \"/run/containerd-stargz-grpc/containerd-stargz-grpc.sock\"
EOF
  sudo sh -c "cat > /etc/systemd/system/stargz-snapshotter.service" <<EOF
[Unit]
Description=stargz snapshotter
After=network.target
Before=containerd.service

[Service]
Type=notify
Environment=HOME=/root
ExecStart=/usr/local/bin/containerd-stargz-grpc --log-level=debug --config=/etc/containerd-stargz-grpc/config.toml
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF
  sudo sh -c "cat > /etc/containerd-stargz-grpc/config.toml" <<EOF
[cri_keychain]
enable_keychain = true
image_service_path = \"/run/containerd/containerd.sock\"
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable stargz-snapshotter --now
  sudo systemctl restart containerd
'
success "stargz snapshotter enabled and containerd restarted."

# 3. Ensure nerdctl is installed
if ! command -v nerdctl &>/dev/null; then
  info "Installing nerdctl via colima..."
  colima nerdctl install
  success "nerdctl installed."
else
  info "nerdctl is already installed."
fi

# 4. Start local registry inside Colima if not running
info "Ensuring local registry is running inside Colima..."
if ! colima ssh -- nerdctl ps | grep -q "$REGISTRY_NAME"; then
  colima ssh -- nerdctl run -d --name $REGISTRY_NAME -p $REGISTRY_PORT:5000 --restart=unless-stopped registry:2
  success "Local registry started on port $REGISTRY_PORT."
else
  info "Local registry is already running."
fi

success "Environment setup complete!" 