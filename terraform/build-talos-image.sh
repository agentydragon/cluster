#!/bin/bash
set -euo pipefail

# Talos version - should match variables.tf
TALOS_VERSION="1.11.2"

# Extension versions compatible with Talos 1.11.2
TALOS_QEMU_GUEST_AGENT_TAG="10.0.2@sha256:9720300de00544eca155bc19369dfd7789d39a0e23d72837a7188f199e13dc6c"

echo "Building Talos image with qemu-guest-agent extension only..."

# Create tmp directory
rm -rf tmp/talos
mkdir -p tmp/talos

# Create Talos image profile (without Tailscale for now)
cat > "tmp/talos/talos-${TALOS_VERSION}.yml" <<EOF
arch: amd64
platform: nocloud
secureboot: false
version: v${TALOS_VERSION}
customization:
  extraKernelArgs:
    - net.ifnames=0
input:
  kernel:
    path: /usr/install/amd64/vmlinuz
  initramfs:
    path: /usr/install/amd64/initramfs.xz
  baseInstaller:
    imageRef: ghcr.io/siderolabs/installer:v${TALOS_VERSION}
  systemExtensions:
    - imageRef: ghcr.io/siderolabs/qemu-guest-agent:${TALOS_QEMU_GUEST_AGENT_TAG}
output:
  kind: image
  imageOptions:
    diskSize: $((2*1024*1024*1024))
    diskFormat: raw
  outFormat: raw
EOF

echo "Running Talos imager..."
docker run --rm -i \
  -v $PWD/tmp/talos:/secureboot:ro \
  -v $PWD/tmp/talos:/out \
  -v /dev:/dev \
  --privileged \
  "ghcr.io/siderolabs/imager:v${TALOS_VERSION}" \
  - < "tmp/talos/talos-${TALOS_VERSION}.yml"

echo "Converting to qcow2..."
qemu-img convert -O qcow2 tmp/talos/nocloud-amd64.raw "tmp/talos/talos-${TALOS_VERSION}.qcow2"

echo "Image info:"
qemu-img info "tmp/talos/talos-${TALOS_VERSION}.qcow2"

echo "Talos image built successfully: tmp/talos/talos-${TALOS_VERSION}.qcow2"