# How It Works

A technical deep-dive into qemu-devops-lab — every component, every QEMU flag, and why each decision was made.

---

## Overview

This project demonstrates the full lifecycle of QEMU-based virtualization from a DevOps perspective:

```
Download → Configure → Build Environment → Boot → Verify → Automate
```

Each stage maps to a Make target and a script. Nothing is magic.

---

## 1. Ubuntu Cloud Images

Ubuntu provides "cloud images" — pre-built, minimal VM disk images optimized for automated deployment. They differ from standard ISO installers:

| Feature | Cloud Image | ISO Installer |
|---|---|---|
| Size | ~600 MB | ~1.5 GB |
| First boot | Fast (cloud-init) | Manual install wizard |
| Automation | Fully scriptable | Requires human input |
| Format | `.img` (raw) or `.qcow2` | `.iso` (CD-ROM) |

We download the `.img` from `cloud-images.ubuntu.com` and convert it to `qcow2` format.

### Why qcow2?

`qcow2` (QEMU Copy-On-Write v2) is QEMU's native disk format. Key properties:

- **Sparse**: a 10 GB qcow2 file only uses as much disk space as its actual content
- **Copy-on-write**: writes go to a new location; original data stays intact
- **Snapshots**: you can snapshot the disk state and roll back (not used here, but available)
- **Compression**: blocks can be compressed, saving space

```bash
# See the difference:
qemu-img info artifacts/ubuntu-x86_64.qcow2
# disk size: ~1.1 GB  (actual data)
# virtual size: 10 GB (what the guest sees)
```

---

## 2. Cloud-Init

Cloud-init is the industry-standard first-boot configuration system used by AWS, GCP, Azure, and bare-metal provisioning systems. It reads configuration from multiple "datasources" — we use the **NoCloud** datasource, which reads from a local ISO.

### Seed ISO

The seed ISO is a small (< 1 MB) ISO 9660 image with volume label `cidata` containing exactly two files:

```
seed.iso/
  meta-data     # instance ID and hostname
  user-data     # configuration (YAML)
```

QEMU mounts this as a virtual CD-ROM. On first boot, cloud-init detects the volume label `cidata` and reads the configuration.

### user-data format

The `user-data` file begins with `#cloud-config` and contains YAML:

```yaml
#cloud-config
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    passwd: "<hashed-password>"
ssh_pwauth: true
packages:
  - curl
  - vim
runcmd:
  - growpart /dev/vda 1   # expand partition
  - resize2fs /dev/vda1   # expand filesystem
```

The `runcmd` entries run once on first boot. We use them to expand the filesystem to fill the 10 GB disk (since the original image is only ~2.2 GB).

---

## 3. QEMU Flags Explained

### x86_64 command

```bash
qemu-system-x86_64 \
  -machine q35 \                          # modern PCIe chipset (vs i440fx)
  -enable-kvm \                           # hardware acceleration (Linux)
  -cpu host \                             # expose host CPU features to guest
  -m 2048 \                              # 2048 MB RAM
  -smp 2 \                               # 2 virtual CPUs
  -drive file=ubuntu.qcow2,format=qcow2,if=virtio,cache=writeback \
  -drive file=seed.iso,format=raw,if=virtio,media=cdrom,readonly=on \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -nographic \
  -serial file:/artifacts/console.log
```

**Flag-by-flag:**

| Flag | Purpose |
|---|---|
| `-machine q35` | Q35 chipset — supports PCIe, more modern than default i440fx |
| `-enable-kvm` | Use Linux KVM for near-native CPU speed (requires `/dev/kvm`) |
| `-cpu host` | Pass through host CPU type so guest sees real CPU features |
| `-m 2048` | 2 GB RAM — enough for Ubuntu, not excessive |
| `-smp 2` | 2 vCPUs for faster boot and parallel cloud-init |
| `-drive ...,if=virtio` | VirtIO disk driver — much faster than emulated IDE/SATA |
| `cache=writeback` | Write cache mode: fast, safe for VM workloads |
| `media=cdrom,readonly=on` | Mount seed ISO as read-only CD-ROM |
| `-netdev user` | User-mode networking — no host root required, works everywhere |
| `hostfwd=tcp::2222-:22` | Forward host port 2222 to guest port 22 (SSH) |
| `-device virtio-net-pci` | VirtIO network driver — faster than emulated e1000 |
| `-nographic` | No graphical display — serial console only (perfect for CI) |
| `-serial file:...` | Redirect serial output to a log file for debugging |

### ARM64 command

ARM64 requires two additional flags:

```bash
qemu-system-aarch64 \
  -machine virt,highmem=off \   # 'virt' = generic ARM virtual platform
  -bios /path/to/QEMU_EFI.fd \ # UEFI firmware required for ARM64 boot
  -cpu cortex-a72 \             # emulate Cortex-A72 (no KVM on x86 host)
  ...
```

| Flag | Purpose |
|---|---|
| `-machine virt` | Generic ARM virtual machine — no specific hardware emulated |
| `highmem=off` | Disable high memory mapping — required for some ARM64 guests |
| `-bios QEMU_EFI.fd` | ARM64 has no BIOS legacy — requires UEFI firmware to boot |
| `-cpu cortex-a72` | Specific ARM CPU model to emulate |

---

## 4. Networking — User-Mode (SLIRP)

User-mode networking (`-netdev user`) uses QEMU's built-in TCP/IP stack. It requires no host-side configuration and works as a normal user (no root).

```
Guest VM
  eth0: 10.0.2.15/24 (auto-assigned by QEMU's DHCP)
  gateway: 10.0.2.2 (QEMU's virtual router)
  DNS: 10.0.2.3

Host
  Port 2222 → forwarded to guest port 22

Internet access: Yes (via host's network connection)
Host → Guest: Only via forwarded ports
Guest → Host: Via 10.0.2.2 (host appears at this address)
```

For more advanced networking (guest-to-guest, bridged, VLANs), you'd use `-netdev tap` with a TAP interface, which requires root. User-mode is the right choice for this demo.

---

## 5. Docker as Reproducibility Layer

The Dockerfile packages `qemu-system-x86_64`, `qemu-system-aarch64`, and all tools into a single image. This solves several real-world problems:

**Problem → Solution:**
- "Works on my machine" → everyone uses the same container
- QEMU version differences between Linux distros → pinned to Ubuntu 22.04 apt version
- Missing `cloud-localds` on macOS → always present in container
- Script path differences → fixed at `/scripts/`

Scripts are **bind-mounted** at runtime (`-v $(pwd)/scripts:/scripts:ro`) rather than baked into the image. This means you can edit scripts without rebuilding the image — a significant productivity win during development.

---

## 6. Acceleration: KVM vs HVF vs TCG

| Accelerator | Platform | Speed | Requires |
|---|---|---|---|
| KVM | Linux | Near-native | `/dev/kvm`, root or kvm group |
| HVF | macOS | Near-native | macOS 10.15+, Apple Hypervisor.framework |
| TCG | Any | ~5–20× slower | Nothing — pure software |

The `run-qemu.sh` script detects which accelerator to use:
1. If `/dev/kvm` exists → use KVM
2. If on macOS → use HVF (QEMU handles this with `-accel hvf`)
3. Otherwise → fall back to TCG

For ARM64 on x86 hosts, TCG is always used because KVM requires the host and guest CPU architectures to match.

---

## 7. SSH Port Forwarding and Verification

After QEMU starts:

1. Guest boots, cloud-init runs, sshd starts
2. Guest sshd listens on port 22
3. QEMU's user-mode networking forwards host port 2222 → guest port 22
4. `wait-for-ssh.sh` polls `localhost:2222` with `nc -z` every 5 seconds
5. Once port is open, `verify-guest.sh` SSHes in and runs diagnostics

The `nc -z` (zero I/O mode) trick is reliable — it tries a TCP connection without sending any data. If the port accepts the connection, SSH is up.

---

## 8. GitHub Actions — What CI Can and Cannot Do

GitHub-hosted runners are standard VMs. They **do not have KVM access** (nested virtualization is disabled on most cloud providers for security reasons).

What we can do in CI:
- ✅ Lint scripts (shellcheck)
- ✅ Validate YAML (cloud-init config)
- ✅ Build the Docker image
- ✅ Verify QEMU binaries exist and have correct versions
- ✅ Validate QEMU flag syntax (using `--version` as a parse test)
- ❌ Boot a guest OS (no KVM → too slow for CI timeout limits)

For full boot testing, the workflow includes a commented-out `full-boot-test` job that runs on a `[self-hosted, linux, kvm]` runner. On a proper Linux machine with KVM, this completes in under 3 minutes.

GitHub now offers ARM64-based runners (`ubuntu-22.04-arm`) which support KVM — useful for testing ARM64 guests natively.
