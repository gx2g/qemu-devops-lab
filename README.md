# qemu-devops-lab

> A production-quality DevOps reference project demonstrating QEMU hardware emulation — booting real Ubuntu cloud images on both **x86_64** and **ARM64**, with Docker-based reproducibility, SSH verification, and GitHub Actions CI.

[![QEMU](https://img.shields.io/badge/QEMU-8.x-orange.svg)](https://www.qemu.org/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04_LTS-E95420.svg)](https://cloud-images.ubuntu.com/)
[![Docker](https://img.shields.io/badge/Docker-20.x+-2496ED.svg)](https://www.docker.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![CI](https://github.com/gx2g/qemu-devops-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/gx2g/qemu-devops-lab/actions/workflows/ci.yml)
[![Arch: x86_64](https://img.shields.io/badge/arch-x86__64-blue.svg)]()
[![Arch: ARM64](https://img.shields.io/badge/arch-ARM64-blue.svg)]()
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25.svg)](https://www.gnu.org/software/bash/)
---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Targets & Commands](#targets--commands)
- [Architecture Targets](#architecture-targets)
- [Docker Usage](#docker-usage)
- [SSH Verification](#ssh-verification)
- [GitHub Actions CI](#github-actions-ci)
- [Project Structure](#project-structure)
- [How It Works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

---

## Overview

This repository exists to demonstrate end-to-end QEMU emulation in a DevOps-ready way:

| Capability | Details |
|---|---|
| Guest OS | Ubuntu 22.04 LTS cloud image |
| Architectures | x86\_64 and ARM64 (aarch64) |
| Networking | User-mode with host port forwarding |
| Verification | Automated SSH login after boot |
| Reproducibility | Fully Dockerized QEMU environment |
| CI | GitHub Actions — validates on every push |
| Host OS | Linux (KVM) and macOS (HVF) supported |

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Host Machine (Linux or macOS)                      │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │  Docker Container                           │   │
│  │  (qemu-devops-lab image)                    │   │
│  │                                             │   │
│  │  ┌──────────────────────────────────────┐  │   │
│  │  │  QEMU Process                        │  │   │
│  │  │  qemu-system-x86_64  (or aarch64)    │  │   │
│  │  │                                      │  │   │
│  │  │  ┌────────────────────────────────┐  │  │   │
│  │  │  │  Ubuntu 22.04 Guest            │  │  │   │
│  │  │  │  - cloud-init (auto-config)    │  │  │   │
│  │  │  │  - SSH on :22 → host :2222     │  │  │   │
│  │  │  └────────────────────────────────┘  │  │   │
│  │  └──────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  make verify → ssh -p 2222 ubuntu@localhost        │
└─────────────────────────────────────────────────────┘
```

---

## Prerequisites

### Linux

```bash
# Ubuntu / Debian
sudo apt-get update
sudo apt-get install -y qemu-system-x86 qemu-system-arm \
    qemu-utils cloud-image-utils docker.io make openssh-client

# Verify KVM access (for hardware acceleration)
ls -la /dev/kvm
# If missing: sudo modprobe kvm_intel  (or kvm_amd)
# Add yourself to kvm group: sudo usermod -aG kvm $USER
```

### macOS

```bash
# Install Homebrew if not present
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install QEMU and tooling
brew install qemu

# Docker Desktop for Mac
# https://docs.docker.com/desktop/install/mac-install/

# Verify QEMU
qemu-system-x86_64 --version
qemu-system-aarch64 --version
```

### Docker (both platforms)

Docker is required for the containerized workflow. Docker Desktop ≥ 4.0 recommended.

```bash
docker --version   # should be 20.x or later
docker info        # confirm daemon is running
```

---

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/YOUR_USERNAME/qemu-devops-lab.git
cd qemu-devops-lab

# 2. Download the Ubuntu cloud image (done once, ~600 MB)
make download

# 3. Build the Docker environment
make build

# 4. Boot Ubuntu in QEMU (runs in Docker, SSH on localhost:2222)
make run

# 5. In a second terminal — verify SSH access
make verify

# 6. SSH in manually (password: ubuntu)
ssh -o StrictHostKeyChecking=no -p 2222 ubuntu@localhost

# 7. Clean up
make clean
```

> **First boot takes 60–120 seconds** while cloud-init configures the guest. Subsequent boots are faster.

---

## Targets & Commands

| Command | Description |
|---|---|
| `make download` | Download Ubuntu 22.04 cloud image for x86\_64 |
| `make download-arm64` | Download Ubuntu 22.04 cloud image for ARM64 |
| `make build` | Build the Docker image |
| `make run` | Boot Ubuntu x86\_64 guest in Docker + QEMU |
| `make run-arm64` | Boot Ubuntu ARM64 guest (full emulation) |
| `make verify` | Wait for SSH and confirm guest is up |
| `make ssh` | Open an interactive SSH session to the guest |
| `make logs` | Tail the QEMU serial console log |
| `make stop` | Stop the running QEMU container |
| `make clean` | Remove containers, images, and disk files |
| `make status` | Show running container and port status |
| `make help` | Print all available targets |

---

## Architecture Targets

### x86\_64 (default)

Runs natively with KVM on Linux, or with HVF on macOS Apple Silicon (Rosetta) and x86 Macs.

```bash
make run         # boots Ubuntu 22.04 x86_64
make verify      # SSHes to port 2222
```

### ARM64 / aarch64

Runs via full software emulation on any host. Slower than x86\_64, but works on all platforms including Linux CI runners.

```bash
make download-arm64    # fetch the ARM64 cloud image
make run-arm64         # boot using qemu-system-aarch64
make verify            # same SSH verification
```

> On Apple Silicon Macs, ARM64 guests run near-native speed because the host CPU is also ARM64 and QEMU uses HVF.

---

## Docker Usage

The Docker image packages everything needed: QEMU binaries, cloud-image-utils, SSH client, and helper scripts. This guarantees the same behavior on any machine.

```bash
# Build image
make build

# Inspect the image
docker images qemu-devops-lab

# Run a shell inside the container (debug mode)
docker run --rm -it \
    --device /dev/kvm \
    -v $(pwd)/artifacts:/artifacts \
    qemu-devops-lab bash

# Run QEMU manually inside the container
docker run --rm -it \
    --device /dev/kvm \
    -p 2222:2222 \
    -v $(pwd)/artifacts:/artifacts \
    qemu-devops-lab /scripts/run-qemu.sh x86_64
```

### Without KVM (macOS or no KVM access)

The `--device /dev/kvm` flag is Linux-only. On macOS, the Docker container runs QEMU in software emulation mode (TCG). This works, but is slower.

```bash
# macOS: build without KVM flag (handled automatically by scripts)
make run   # scripts detect platform and omit --device /dev/kvm on macOS
```

---

## SSH Verification

After `make run`, the guest Ubuntu VM exposes SSH on `localhost:2222`.

```bash
# Automated wait + verify (used by CI)
make verify

# Manual SSH (password: ubuntu)
ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -p 2222 ubuntu@localhost

# Run a command non-interactively
ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -p 2222 ubuntu@localhost \
    "uname -a && df -h && uptime"
```

### Credentials

| Field | Value |
|---|---|
| Username | `ubuntu` |
| Password | `ubuntu` |
| SSH Key | Auto-generated at `artifacts/id_ed25519` (optional) |

Credentials are injected via **cloud-init** using the `user-data` file at `scripts/cloud-init/user-data`. You can customize this to inject your own SSH public key instead of a password.

---

## GitHub Actions CI

Every push triggers `.github/workflows/ci.yml` which:

1. Lints all shell scripts with `shellcheck`
2. Verifies the Dockerfile builds cleanly
3. Validates QEMU binary availability and flags
4. Checks that cloud-init `user-data` is valid YAML
5. Runs a **headless QEMU smoke test** (no KVM, TCG mode) confirming QEMU starts

Full boot + SSH verification is skipped in CI because GitHub-hosted runners do not support KVM nested virtualization. The workflow documents how to enable this on a self-hosted runner.

### Self-hosted runner with KVM

```yaml
# In your repo Settings → Actions → Runners
# Add a self-hosted runner on a Linux machine with KVM access, then:

runs-on: [self-hosted, linux, kvm]
```

Then uncomment the full boot test block in `ci.yml`.

---

## Project Structure

```
qemu-devops-lab/
├── README.md                    # This file
├── Makefile                     # All automation targets
├── .gitignore
│
├── docker/
│   └── Dockerfile               # QEMU + tooling container image
│
├── scripts/
│   ├── download-image.sh        # Fetch Ubuntu cloud image + verify checksum
│   ├── run-qemu.sh              # Launch QEMU with correct flags per arch
│   ├── make-seed.sh             # Build cloud-init seed ISO
│   ├── wait-for-ssh.sh          # Poll until SSH port is ready
│   ├── verify-guest.sh          # SSH in and run diagnostic commands
│   └── cloud-init/
│       ├── user-data            # Cloud-init user config (credentials, packages)
│       └── meta-data            # Cloud-init instance metadata
│
├── docs/
│   ├── how-it-works.md          # Deep-dive on QEMU flags and cloud-init
│   ├── architecture.md          # Diagrams and design decisions
│   └── troubleshooting.md       # Common issues and fixes
│
├── artifacts/                   # gitignored — downloaded images and built disks
│   └── .gitkeep
│
└── .github/
    └── workflows/
        └── ci.yml               # GitHub Actions pipeline
```

---

## How It Works

### 1. Image Download

`scripts/download-image.sh` fetches the official Ubuntu 22.04 cloud image from `cloud-images.ubuntu.com` and verifies the SHA256 checksum. The image is a `.qcow2` file — a sparse, copy-on-write disk format native to QEMU.

### 2. Cloud-Init Seed

`scripts/make-seed.sh` creates a small ISO image (the "seed") containing two files:
- `user-data` — sets the ubuntu user's password and SSH authorized keys
- `meta-data` — provides the instance ID and hostname

QEMU mounts this seed ISO as a CD-ROM drive. On first boot, cloud-init reads it and configures the system automatically.

### 3. QEMU Launch

`scripts/run-qemu.sh` starts QEMU with these key flags:

```bash
qemu-system-x86_64 \
  -enable-kvm \                          # hardware acceleration (Linux)
  -m 2048 \                              # 2 GB RAM
  -smp 2 \                               # 2 vCPUs
  -drive file=artifacts/ubuntu.qcow2,format=qcow2 \
  -drive file=artifacts/seed.iso,format=raw,media=cdrom \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \   # port-forward SSH
  -device virtio-net-pci,netdev=net0 \
  -nographic \                           # no GUI — serial console only
  -serial file:artifacts/console.log     # log boot output
```

### 4. SSH Verification

`scripts/wait-for-ssh.sh` polls `localhost:2222` every 5 seconds (up to 3 minutes) until SSH responds. Then `scripts/verify-guest.sh` SSHes in and runs `uname -a`, `uptime`, and `df -h` to confirm the guest is healthy.

---

## Troubleshooting

See [`docs/troubleshooting.md`](docs/troubleshooting.md) for the full guide. Quick reference below.

### QEMU won't start

```bash
# Check QEMU is installed
qemu-system-x86_64 --version

# Check the cloud image exists
ls -lh artifacts/ubuntu-22.04.qcow2

# Check the seed ISO was built
ls -lh artifacts/seed.iso

# View the serial console log
make logs
```

### KVM not available

```bash
# Check KVM module
lsmod | grep kvm

# Load it
sudo modprobe kvm_intel    # Intel CPUs
sudo modprobe kvm_amd      # AMD CPUs

# Check device node
ls -la /dev/kvm

# Add yourself to kvm group (then log out/in)
sudo usermod -aG kvm $USER
```

### SSH connection refused

```bash
# Confirm port 2222 is listening
ss -tlnp | grep 2222      # Linux
lsof -i :2222             # macOS

# Check guest boot progress
make logs
# Look for "cloud-init finished" or "Ubuntu 22.04" login prompt

# Boot may still be in progress — wait 2 more minutes
make verify   # this will retry automatically
```

### macOS: /dev/kvm missing

This is expected on macOS. QEMU uses the Hypervisor.framework (HVF) instead. The scripts automatically omit `-enable-kvm` on macOS and substitute `-accel hvf` for x86 hosts or `-accel hvf` for ARM64.

```bash
# Verify HVF acceleration
qemu-system-x86_64 -accel help
# Should list: hvf
```

### Docker: permission denied on /dev/kvm

```bash
# On Linux, pass the device explicitly
docker run --device /dev/kvm ...

# Or add the docker group access
sudo chmod 666 /dev/kvm    # temporary fix
# Permanent: add udev rule (see docs/troubleshooting.md)
```

### ARM64 guest is very slow

ARM64 on an x86 host uses full software emulation (TCG) — this is expected. It will be 10–20× slower than native. On Apple Silicon Macs, ARM64 guests run near-native speed.

```bash
# Monitor emulation performance
make ssh
# Inside guest:
cat /proc/cpuinfo | grep "model name"
```

### Cloud-init never finishes

```bash
# SSH into the guest
make ssh

# Check cloud-init status
cloud-init status --long

# View cloud-init logs
sudo journalctl -u cloud-init --no-pager
```

### Port 2222 already in use

```bash
# Find what's using it
lsof -i :2222       # macOS/Linux
ss -tlnp | grep 2222  # Linux

# Change the host port in Makefile or run-qemu.sh
# HOST_SSH_PORT ?= 2222  →  HOST_SSH_PORT ?= 2223
```

---

## Contributing

1. Fork the repo and create a feature branch
2. Run `make build && make run && make verify` to confirm everything works
3. Run `shellcheck scripts/*.sh` — all scripts must pass
4. Open a pull request with a clear description

Issues and pull requests are welcome. See [`docs/`](docs/) for design decisions.

---

## License

MIT — see [LICENSE](LICENSE).
