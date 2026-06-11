# Troubleshooting Guide

This guide covers every common failure mode when running qemu-devops-lab. Issues are organized by stage.

---

## Stage 1: Prerequisites

### QEMU not found

```
qemu-system-x86_64: command not found
```

**Linux:**
```bash
sudo apt-get install -y qemu-system-x86 qemu-system-arm qemu-utils
```

**macOS:**
```bash
brew install qemu
# Confirm QEMU is on your PATH:
echo $PATH
which qemu-system-x86_64
```

---

### Docker daemon not running

```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock
```

**Linux:**
```bash
sudo systemctl start docker
sudo systemctl enable docker
# Add yourself to the docker group (then log out/in):
sudo usermod -aG docker $USER
```

**macOS:**
Open Docker Desktop from your Applications folder. Wait for the whale icon in the menu bar to stop animating.

---

## Stage 2: Downloading the image

### Download fails midway

```bash
# Remove the partial file and retry:
rm -f artifacts/ubuntu-22.04-server-cloudimg-amd64.img
make download
```

### Checksum mismatch

```
ERROR: Checksum mismatch! Download may be corrupt.
```

This means the file was corrupted in transit. Remove it and try again. If it persists, check if your DNS or proxy is intercepting the connection.

```bash
rm -f artifacts/ubuntu-22.04-server-cloudimg-amd64.img
make download
```

### No space left on device

Cloud images are ~600 MB compressed, ~2.2 GB uncompressed, resized to 10 GB (sparse). You need at least 12 GB free.

```bash
df -h .
# Free space on the artifacts partition
```

---

## Stage 3: Building the Docker image

### Dockerfile build fails on apt-get

This is usually a transient network issue inside the Docker build.

```bash
# Retry the build (apt caches are often fixed by a second attempt)
make build

# If it persists, update the package lists
docker build --no-cache -f docker/Dockerfile .
```

### QEMU binary missing in container

After `make build`, verify:

```bash
docker run --rm qemu-devops-lab:latest qemu-system-x86_64 --version
docker run --rm qemu-devops-lab:latest qemu-system-aarch64 --version
```

If these fail, the apt install may have used a different package. Check the Dockerfile and update the package names for your Ubuntu version.

---

## Stage 4: Building the seed ISO

### cloud-localds not found

```
ERROR: No ISO builder found.
```

Inside the Docker container, `cloud-localds` comes from `cloud-image-utils`. Rebuild the image:

```bash
make build
```

On the host (if running outside Docker):

```bash
# Ubuntu/Debian:
sudo apt-get install -y cloud-image-utils

# macOS (genisoimage fallback):
brew install cdrtools
```

### Seed ISO is 0 bytes or missing

```bash
ls -la artifacts/seed.iso
# If missing or empty:
rm -f artifacts/seed.iso
make seed
```

---

## Stage 5: Booting the guest

### KVM not available (Linux)

```
qemu-system-x86_64: -enable-kvm: could not enable KVM
```

**Check CPU virtualization support:**
```bash
grep -E 'vmx|svm' /proc/cpuinfo | head -1
# vmx = Intel VT-x
# svm = AMD-V
# If empty: your CPU or BIOS has virtualization disabled
```

**Load the KVM module:**
```bash
sudo modprobe kvm_intel    # Intel
sudo modprobe kvm_amd      # AMD
ls -la /dev/kvm            # Should now exist
```

**Fix permissions:**
```bash
# Temporary:
sudo chmod 666 /dev/kvm

# Permanent (udev rule):
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666"' | \
  sudo tee /etc/udev/rules.d/99-kvm.rules
sudo udevadm control --reload-rules
sudo usermod -aG kvm $USER
# Log out and back in
```

**Running inside a VM (nested virtualization):**
KVM inside a VM requires the hypervisor to expose its virtualization extensions. On VMware, enable "Virtualize Intel VT-x/EPT" in VM Settings. On VirtualBox, enable "Enable Nested VT-x/AMD-V".

---

### macOS: QEMU process crashes immediately

**Apple Silicon (M1/M2/M3):**
You cannot run x86_64 guests with hardware acceleration on Apple Silicon. The scripts use TCG (software emulation) automatically, but if you've manually added `-accel hvf` to an x86_64 command on ARM, remove it.

```bash
# Check your host architecture:
uname -m
# arm64 = Apple Silicon → use ARM64 guests for speed
# x86_64 = Intel Mac → use x86_64 guests with HVF
```

**Intel Mac — HVF not available:**
```bash
# Check HVF support:
qemu-system-x86_64 -accel help
# Should list: hvf
# If missing: macOS version may be too old (need 10.15+)
```

---

### QEMU starts but guest never boots (no output in console.log)

```bash
# Watch the serial log in real time:
make logs

# Nothing there? Check if the QEMU process is running:
docker ps
docker logs qemu-guest

# If the container exited immediately:
docker run --rm \
  -v $(pwd)/artifacts:/artifacts \
  -v $(pwd)/scripts:/scripts:ro \
  qemu-devops-lab:latest \
  bash /scripts/run-qemu.sh x86_64
# This runs interactively so you see all QEMU output
```

---

### Guest boots but cloud-init hangs

Cloud-init sometimes waits for network before proceeding. Watch the log:

```bash
make logs
# Look for: "waiting for cloud-init..." or "Starting Network..."
```

If cloud-init is stuck waiting on network:

```bash
# SSH in (if SSH is already up, cloud-init may still be running)
make ssh

# Check cloud-init status:
cloud-init status --long

# Check for failing services:
sudo systemctl list-units --state=failed

# Check cloud-init log:
sudo cat /var/log/cloud-init.log | tail -50
```

---

### Guest boots but SSH is refused

**Port not forwarded:**
```bash
# Confirm QEMU port forwarding is active (inside the container):
docker exec qemu-guest ss -tlnp | grep 2222
# Or on host:
ss -tlnp | grep 2222   # Linux
lsof -i :2222          # macOS
```

**Guest SSH daemon not started:**
```bash
# SSH in via console (if accessible) or check serial log:
make logs
# Look for: "Started OpenSSH server daemon" or "sshd"
```

**Password auth disabled:**
The cloud-init `user-data` sets `ssh_pwauth: true`. If you've modified it, confirm this is present. If you want key-based auth, add your public key to `ssh_authorized_keys` in `user-data`, then rebuild the seed.

---

### Port 2222 already in use

```
Bind for 0.0.0.0:2222 failed: port is already allocated
```

```bash
# Find what's using port 2222:
lsof -i :2222     # macOS/Linux
ss -tlnp | grep 2222   # Linux

# Option 1: kill the conflicting process
kill <PID>

# Option 2: change the port in Makefile
# Edit Makefile: HOST_SSH_PORT := 2222  →  HOST_SSH_PORT := 2223
# Then:
make run
ssh -p 2223 ubuntu@localhost
```

---

## Stage 6: ARM64 specific issues

### ARM64 guest is extremely slow

Full software emulation (TCG) of ARM64 on an x86 host is expected to be slow — first boot can take 10–20 minutes. This is normal.

To speed it up:
- Use an Apple Silicon Mac (native ARM64 speed via HVF)
- Use a Linux ARM64 server with KVM (e.g., AWS Graviton, Ampere instances)
- For CI, use GitHub-hosted ARM64 runners (`runs-on: ubuntu-22.04-arm`)

### AAVMF firmware not found

```
qemu-system-aarch64: No bootable device
```

The ARM64 guest requires UEFI firmware (AAVMF). The `run-qemu.sh` script auto-installs it, but if running outside Docker:

```bash
# Ubuntu/Debian:
sudo apt-get install -y qemu-efi-aarch64

# Check it exists:
ls /usr/share/qemu-efi-aarch64/QEMU_EFI.fd
```

---

## Useful debugging commands

```bash
# Live serial console (guest boot output)
make logs

# Container logs (QEMU stdout/stderr)
docker logs -f qemu-guest

# Interactive shell in container (without starting QEMU)
docker run --rm -it \
  --device /dev/kvm \
  -v $(pwd)/artifacts:/artifacts \
  -v $(pwd)/scripts:/scripts:ro \
  qemu-devops-lab:latest bash

# Check QEMU disk image health
qemu-img check artifacts/ubuntu-x86_64.qcow2
qemu-img info  artifacts/ubuntu-x86_64.qcow2

# Re-download image from scratch
rm -f artifacts/ubuntu-x86_64.qcow2
make download

# Full reset (nuclear option)
make clean
make download
make build
make seed
make run
```

---

## Getting help

If you hit an issue not covered here:

1. Run `make logs` and capture the last 50 lines of the serial console
2. Run `docker logs qemu-guest` and capture the output
3. Note your host OS, architecture (`uname -sm`), and Docker version
4. Open an issue at the project repository with this information
