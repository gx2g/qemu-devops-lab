# =============================================================================
# qemu-devops-lab — Dockerfile
# Packages QEMU + tooling into a reproducible container for Linux and macOS.
# =============================================================================

FROM ubuntu:22.04

LABEL maintainer="qemu-devops-lab"
LABEL description="QEMU emulation environment — boots Ubuntu x86_64 and ARM64 cloud images"

# Prevent interactive prompts during apt installs
ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm-256color

# ── Install QEMU and supporting tools ────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # QEMU emulators
    qemu-system-x86 \
    qemu-system-arm \
    qemu-utils \
    # Cloud image tools
    cloud-image-utils \
    genisoimage \
    # Networking + verification
    openssh-client \
    netcat-openbsd \
    curl \
    wget \
    # Utilities
    ca-certificates \
    coreutils \
    bash \
    && rm -rf /var/lib/apt/lists/*

# ── Verify installed QEMU versions ───────────────────────────────────────────
RUN qemu-system-x86_64 --version \
    && qemu-system-aarch64 --version

# ── Create working directories ────────────────────────────────────────────────
RUN mkdir -p /artifacts /scripts

# ── Scripts are bind-mounted at runtime (see Makefile) ───────────────────────
# This keeps the image lean and lets you edit scripts without rebuilding.
# Volume: -v $(pwd)/scripts:/scripts:ro

# ── Expose the forwarded SSH port ────────────────────────────────────────────
EXPOSE 2222

# ── Default command ───────────────────────────────────────────────────────────
CMD ["/bin/bash"]
