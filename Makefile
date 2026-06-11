# =============================================================================
# qemu-devops-lab — Makefile
# Boots Ubuntu 22.04 cloud images on x86_64 and ARM64 via QEMU + Docker
# =============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# ── Configuration ─────────────────────────────────────────────────────────────
DOCKER_IMAGE    := qemu-devops-lab
DOCKER_TAG      := latest
ARTIFACTS_DIR   := $(PWD)/artifacts
HOST_SSH_PORT   := 2222
CONTAINER_NAME  := qemu-guest

UBUNTU_VERSION  := 22.04
UBUNTU_RELEASE  := jammy

# Ubuntu cloud image URLs
X86_IMAGE_NAME  := ubuntu-$(UBUNTU_VERSION)-server-cloudimg-amd64.img
ARM_IMAGE_NAME  := ubuntu-$(UBUNTU_VERSION)-server-cloudimg-arm64.img
CLOUD_BASE_URL  := https://cloud-images.ubuntu.com/$(UBUNTU_RELEASE)/current

# ── Platform detection ────────────────────────────────────────────────────────
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_S),Linux)
  KVM_FLAG := --device /dev/kvm
  PLATFORM := linux
else ifeq ($(UNAME_S),Darwin)
  KVM_FLAG :=
  PLATFORM := macos
else
  KVM_FLAG :=
  PLATFORM := unknown
endif

# ── Color output ──────────────────────────────────────────────────────────────
BOLD  := \033[1m
GREEN := \033[32m
CYAN  := \033[36m
RESET := \033[0m

# =============================================================================
# Phony targets
# =============================================================================
.PHONY: help download download-arm64 build run run-arm64 verify ssh \
        logs stop clean status seed

# ── help ──────────────────────────────────────────────────────────────────────
help: ## Show this help message
	@echo ""
	@printf "$(BOLD)qemu-devops-lab$(RESET) — QEMU emulation reference project\n"
	@echo ""
	@printf "$(CYAN)Usage:$(RESET)  make [target]\n"
	@echo ""
	@printf "$(BOLD)Setup$(RESET)\n"
	@grep -E '^(download|build).*:.*##' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*##"} {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@printf "$(BOLD)Run$(RESET)\n"
	@grep -E '^(run|run-arm64|stop).*:.*##' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*##"} {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@printf "$(BOLD)Verify$(RESET)\n"
	@grep -E '^(verify|ssh|logs|status).*:.*##' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*##"} {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@printf "$(BOLD)Cleanup$(RESET)\n"
	@grep -E '^clean.*:.*##' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*##"} {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@printf "$(CYAN)Platform detected:$(RESET) $(PLATFORM) / $(UNAME_M)\n"
	@echo ""

# =============================================================================
# Setup targets
# =============================================================================

## download: Download Ubuntu 22.04 x86_64 cloud image and verify checksum
download: ## Download Ubuntu 22.04 x86_64 cloud image
	@mkdir -p $(ARTIFACTS_DIR)
	@bash scripts/download-image.sh x86_64 $(ARTIFACTS_DIR) \
		$(CLOUD_BASE_URL)/$(X86_IMAGE_NAME) \
		$(X86_IMAGE_NAME)

## download-arm64: Download Ubuntu 22.04 ARM64 cloud image
download-arm64: ## Download Ubuntu 22.04 ARM64 cloud image
	@mkdir -p $(ARTIFACTS_DIR)
	@bash scripts/download-image.sh arm64 $(ARTIFACTS_DIR) \
		$(CLOUD_BASE_URL)/$(ARM_IMAGE_NAME) \
		$(ARM_IMAGE_NAME)

## build: Build the Docker image with QEMU and tools
build: ## Build the Docker image
	@printf "$(BOLD)Building Docker image: $(DOCKER_IMAGE):$(DOCKER_TAG)$(RESET)\n"
	docker build \
		--tag $(DOCKER_IMAGE):$(DOCKER_TAG) \
		--file docker/Dockerfile \
		.
	@printf "$(GREEN)✓ Docker image built successfully$(RESET)\n"

# =============================================================================
# Run targets
# =============================================================================

## run: Boot Ubuntu x86_64 guest in Docker + QEMU (SSH on localhost:2222)
run: _check-image-x86 seed ## Boot Ubuntu x86_64 guest
	@printf "$(BOLD)Starting Ubuntu 22.04 x86_64 guest...$(RESET)\n"
	@printf "  SSH will be available at: $(CYAN)localhost:$(HOST_SSH_PORT)$(RESET)\n"
	@printf "  Credentials: $(CYAN)ubuntu / ubuntu$(RESET)\n"
	@printf "  Serial log:  $(CYAN)artifacts/console.log$(RESET)\n"
	@printf "  Waiting for boot (60–120 seconds)...\n\n"
	@docker rm -f $(CONTAINER_NAME) 2>/dev/null || true
	docker run \
		--name $(CONTAINER_NAME) \
		--detach \
		$(KVM_FLAG) \
		--publish $(HOST_SSH_PORT):2222 \
		--volume $(ARTIFACTS_DIR):/artifacts \
		--volume $(PWD)/scripts:/scripts:ro \
		$(DOCKER_IMAGE):$(DOCKER_TAG) \
		bash /scripts/run-qemu.sh x86_64
	@printf "$(GREEN)✓ Container started. Run 'make verify' to confirm boot.$(RESET)\n"

## run-arm64: Boot Ubuntu ARM64 guest (full emulation)
run-arm64: _check-image-arm seed ## Boot Ubuntu ARM64 guest (full emulation)
	@printf "$(BOLD)Starting Ubuntu 22.04 ARM64 guest (software emulation)...$(RESET)\n"
	@printf "  $(CYAN)Note: ARM64 on x86 host uses TCG — expect slow first boot$(RESET)\n"
	@printf "  SSH will be available at: $(CYAN)localhost:$(HOST_SSH_PORT)$(RESET)\n"
	@docker rm -f $(CONTAINER_NAME) 2>/dev/null || true
	docker run \
		--name $(CONTAINER_NAME) \
		--detach \
		--publish $(HOST_SSH_PORT):2222 \
		--volume $(ARTIFACTS_DIR):/artifacts \
		--volume $(PWD)/scripts:/scripts:ro \
		$(DOCKER_IMAGE):$(DOCKER_TAG) \
		bash /scripts/run-qemu.sh arm64
	@printf "$(GREEN)✓ Container started. Run 'make verify' to confirm boot.$(RESET)\n"

## stop: Stop the running QEMU container
stop: ## Stop the running QEMU container
	@printf "Stopping container: $(CONTAINER_NAME)\n"
	@docker stop $(CONTAINER_NAME) 2>/dev/null || printf "  (container not running)\n"
	@docker rm   $(CONTAINER_NAME) 2>/dev/null || true
	@printf "$(GREEN)✓ Stopped$(RESET)\n"

# =============================================================================
# Verify targets
# =============================================================================

## verify: Wait for SSH and confirm the guest OS is healthy
verify: ## Wait for SSH and verify guest is up
	@printf "$(BOLD)Waiting for guest to become reachable via SSH...$(RESET)\n"
	@bash scripts/wait-for-ssh.sh localhost $(HOST_SSH_PORT) 180
	@printf "$(GREEN)✓ SSH is up — running diagnostics$(RESET)\n"
	@bash scripts/verify-guest.sh localhost $(HOST_SSH_PORT)

## ssh: Open an interactive SSH session to the guest
ssh: ## Interactive SSH into the running guest
	@printf "$(BOLD)Connecting to guest (password: ubuntu)$(RESET)\n"
	ssh \
		-o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null \
		-o LogLevel=ERROR \
		-p $(HOST_SSH_PORT) \
		ubuntu@localhost

## logs: Tail the QEMU serial console log
logs: ## Tail the QEMU serial console log
	@if [ -f $(ARTIFACTS_DIR)/console.log ]; then \
		tail -f $(ARTIFACTS_DIR)/console.log; \
	else \
		printf "No console.log yet. Start the guest with 'make run' first.\n"; \
	fi

## status: Show running container and port status
status: ## Show container and port status
	@printf "$(BOLD)Container status:$(RESET)\n"
	@docker ps --filter name=$(CONTAINER_NAME) --format "  {{.Names}}\t{{.Status}}\t{{.Ports}}" \
		|| printf "  (docker not available)\n"
	@printf "\n$(BOLD)Port status:$(RESET)\n"
	@if command -v ss &>/dev/null; then \
		ss -tlnp | grep :$(HOST_SSH_PORT) || printf "  Port $(HOST_SSH_PORT) not listening\n"; \
	elif command -v lsof &>/dev/null; then \
		lsof -i :$(HOST_SSH_PORT) || printf "  Port $(HOST_SSH_PORT) not listening\n"; \
	fi

# =============================================================================
# Internal helpers
# =============================================================================

## seed: Build the cloud-init seed ISO
seed: ## Build cloud-init seed ISO
	@bash scripts/make-seed.sh $(ARTIFACTS_DIR)

_check-image-x86:
	@if [ ! -f "$(ARTIFACTS_DIR)/ubuntu-x86_64.qcow2" ]; then \
		printf "$(BOLD)Ubuntu x86_64 image not found. Run: make download$(RESET)\n"; \
		exit 1; \
	fi

_check-image-arm:
	@if [ ! -f "$(ARTIFACTS_DIR)/ubuntu-arm64.qcow2" ]; then \
		printf "$(BOLD)Ubuntu ARM64 image not found. Run: make download-arm64$(RESET)\n"; \
		exit 1; \
	fi

# =============================================================================
# Cleanup
# =============================================================================

## clean: Remove all containers, the Docker image, and downloaded artifacts
clean: ## Remove containers, image, and artifacts
	@printf "$(BOLD)Cleaning up...$(RESET)\n"
	@docker stop $(CONTAINER_NAME) 2>/dev/null || true
	@docker rm   $(CONTAINER_NAME) 2>/dev/null || true
	@docker rmi  $(DOCKER_IMAGE):$(DOCKER_TAG) 2>/dev/null || true
	@rm -f $(ARTIFACTS_DIR)/ubuntu-x86_64.qcow2
	@rm -f $(ARTIFACTS_DIR)/ubuntu-arm64.qcow2
	@rm -f $(ARTIFACTS_DIR)/seed.iso
	@rm -f $(ARTIFACTS_DIR)/console.log
	@printf "$(GREEN)✓ Clean complete$(RESET)\n"
