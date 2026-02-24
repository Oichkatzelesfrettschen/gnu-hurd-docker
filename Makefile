.PHONY: help validate security lint links smoke-host smoke-container smoke-guest ports screenshot monitor sendkey setup setup-latest setup-daily-installer resolve-latest-image resolve-latest-daily-installer build build-podman compose-config up up-kvm up-vnc up-kvm-vnc up-volume up-volume-vnc up-latest up-installer up-podman up-podman-kvm up-podman-vnc up-podman-latest up-podman-installer down ps logs shell

CONTAINER_RUNTIME ?= docker
COMPOSE ?= $(CONTAINER_RUNTIME) compose
SERVICE_NAME ?= gnu-hurd-dev

COMPOSE_BASE_FILES ?= compose.yaml
COMPOSE_DEV_FILES ?= compose.yaml:compose.bind.yaml
COMPOSE_DEV_KVM_FILES ?= compose.yaml:compose.bind.yaml:compose.kvm.yaml
COMPOSE_DEV_VNC_FILES ?= compose.yaml:compose.bind.yaml:compose.vnc.yaml
COMPOSE_DEV_KVM_VNC_FILES ?= compose.yaml:compose.bind.yaml:compose.kvm.yaml:compose.vnc.yaml
COMPOSE_VOLUME_FILES ?= compose.yaml
COMPOSE_VOLUME_VNC_FILES ?= compose.yaml:compose.vnc.yaml
COMPOSE_PODMAN_FILES ?= compose.podman.yaml
COMPOSE_PODMAN_KVM_FILES ?= compose.podman.yaml:compose.kvm.yaml
COMPOSE_PODMAN_VNC_FILES ?= compose.podman.yaml:compose.vnc.yaml
COMPOSE_ALL_DOCKER_FILES ?= compose.yaml:compose.bind.yaml:compose.kvm.yaml:compose.vnc.yaml
COMPOSE_ALL_PODMAN_FILES ?= compose.podman.yaml:compose.kvm.yaml:compose.vnc.yaml

help:
	@echo "GNU Hurd Compose/Bake Control Plane"
	@echo ""
	@echo "Validation & Testing:"
	@echo "  make validate                     - validate repo invariants"
	@echo "  make security                     - validate compose security posture"
	@echo "  make lint                         - shellcheck all scripts"
	@echo "  make links                        - scan docs for broken internal links"
	@echo "  make smoke-host                   - host-side quick sanity check"
	@echo "  make smoke-container              - container/QEMU process sanity (no guest assumptions)"
	@echo "  make smoke-guest                  - guest readiness via SSH/serial (best-effort)"
	@echo ""
	@echo "Build:"
	@echo "  make build                        - docker buildx bake image"
	@echo "  make build-podman                 - podman build -t gnu-hurd-docker:latest ."
	@echo "  make compose-config               - render effective compose config"
	@echo "  make resolve-latest-image         - resolve latest upstream hurd-amd64 dated artifact"
	@echo "  make resolve-latest-daily-installer - resolve latest d-i daily installer build (hurd-amd64)"
	@echo "  make setup-latest                 - download latest upstream image to images/debian-hurd-amd64.latest.qcow2"
	@echo "  make setup-daily-installer        - fetch latest d-i mini.iso + create fresh qcow2 target disk"
	@echo ""
	@echo "Operation (Docker defaults):"
	@echo "  make up                           - start bind-mode stack"
	@echo "  make up-kvm                       - start bind-mode + KVM overlay"
	@echo "  make up-vnc                       - start bind-mode + VNC/noVNC overlay"
	@echo "  make up-kvm-vnc                   - start bind-mode + KVM + VNC/noVNC"
	@echo "  make up-volume                    - start volume mode (AUTO_DOWNLOAD_IMAGE=1)"
	@echo "  make up-volume-vnc                - start volume mode + VNC/noVNC"
	@echo "  make up-latest                    - start bind-mode using images/debian-hurd-amd64.latest.qcow2"
	@echo "  make up-installer                 - boot installer ISO with fresh qcow2 target"
	@echo "  make down                         - stop and remove current runtime stack"
	@echo "  make ps                           - show service status"
	@echo "  make logs                         - follow logs for SERVICE_NAME"
	@echo "  make shell                        - shell into SERVICE_NAME"
	@echo ""
	@echo "Operation (Podman shortcuts):"
	@echo "  make up-podman                    - start Podman stack (PODMAN_COMPOSE_PROVIDER defaults to podman-compose)"
	@echo "  make up-podman-kvm                - start Podman stack + KVM overlay"
	@echo "  make up-podman-vnc                - start Podman stack + VNC/noVNC overlay"
	@echo "  make up-podman-latest             - start Podman stack with latest image alias"
	@echo "  make up-podman-installer          - boot installer ISO on Podman stack with fresh qcow2 target"
	@echo ""
	@echo "Debugging:"
	@echo "  make screenshot                   - capture QEMU screendump to logs/"
	@echo "  make monitor CMD='info status'    - run a QEMU monitor command"
	@echo "  make sendkey KEY=esc              - send a QEMU monitor sendkey"
	@echo "  make ports                        - check for host port collisions"
	@echo ""
	@echo "Runtime selection:"
	@echo "  CONTAINER_RUNTIME=docker|podman"
	@echo "  PODMAN_COMPOSE_PROVIDER=podman-compose|docker-compose"

validate:
	./scripts/validate-config.sh

security:
	./scripts/validate-security-config.sh

lint:
	shellcheck -S warning entrypoint.sh scripts/*.sh scripts/lib/*.sh scripts/test-phases/*.sh

links:
	python3 scripts/utils/link-scanner.py --docs-root docs

smoke-host:
	./scripts/smoke-host.sh

smoke-container:
	./scripts/smoke-container.sh

smoke-guest:
	./scripts/smoke-guest.sh

screenshot:
	MONITOR_PORT=$${MONITOR_PORT:-9999} SERVICE_NAME=$${SERVICE_NAME:-gnu-hurd-dev} ./scripts/qemu-screenshot.sh

monitor:
	@if [ -z "$${CMD:-}" ]; then echo "Usage: make monitor CMD='info status' [MONITOR_PORT=9999]"; exit 2; fi
	MONITOR_PORT=$${MONITOR_PORT:-9999} ./scripts/qemu-monitor-command.sh "$${CMD}"

sendkey:
	@if [ -z "$${KEY:-}" ]; then echo "Usage: make sendkey KEY='esc' [MONITOR_PORT=9999]"; exit 2; fi
	MONITOR_PORT=$${MONITOR_PORT:-9999} ./scripts/qemu-sendkey.sh "$${KEY}"

ports:
	./scripts/check-ports.sh

setup:
	./scripts/setup-hurd-amd64.sh

setup-latest:
	./scripts/setup-hurd-amd64-latest.sh

resolve-latest-image:
	./scripts/resolve-latest-hurd-amd64.sh report

resolve-latest-daily-installer:
	./scripts/resolve-latest-hurd-amd64-daily-installer.sh report

setup-daily-installer:
	./scripts/setup-hurd-amd64-daily-installer.sh

build:
	docker buildx bake image

build-podman:
	podman build -t gnu-hurd-docker:latest .

compose-config:
	@runtime="$${CONTAINER_RUNTIME:-$(CONTAINER_RUNTIME)}"; \
	if [ "$$runtime" = "podman" ]; then \
		compose_files="$${COMPOSE_FILE:-$(COMPOSE_PODMAN_FILES)}"; \
		compose_cmd="$${PODMAN_COMPOSE_PROVIDER:-podman-compose}"; \
		COMPOSE_FILE="$$compose_files" "$$compose_cmd" config; \
	else \
		compose_files="$${COMPOSE_FILE:-$(COMPOSE_DEV_FILES)}"; \
		COMPOSE_FILE="$$compose_files" "$$runtime" compose config; \
	fi

up:
	COMPOSE_FILE="$${COMPOSE_FILE:-$(COMPOSE_DEV_FILES)}" $(COMPOSE) up -d

up-kvm:
	COMPOSE_FILE="$${COMPOSE_FILE:-$(COMPOSE_DEV_KVM_FILES)}" $(COMPOSE) up -d

up-vnc:
	COMPOSE_FILE="$${COMPOSE_FILE:-$(COMPOSE_DEV_VNC_FILES)}" COMPOSE_PROFILES="$${COMPOSE_PROFILES:-vnc}" $(COMPOSE) up -d

up-kvm-vnc:
	COMPOSE_FILE="$${COMPOSE_FILE:-$(COMPOSE_DEV_KVM_VNC_FILES)}" COMPOSE_PROFILES="$${COMPOSE_PROFILES:-vnc}" $(COMPOSE) up -d

up-volume:
	AUTO_DOWNLOAD_IMAGE=1 COMPOSE_FILE="$${COMPOSE_FILE:-$(COMPOSE_VOLUME_FILES)}" $(COMPOSE) up -d

up-volume-vnc:
	AUTO_DOWNLOAD_IMAGE=1 COMPOSE_FILE="$${COMPOSE_FILE:-$(COMPOSE_VOLUME_VNC_FILES)}" COMPOSE_PROFILES="$${COMPOSE_PROFILES:-vnc}" $(COMPOSE) up -d

up-latest:
	HURD_IMAGE_BASENAME="$${HURD_IMAGE_BASENAME:-debian-hurd-amd64.latest.qcow2}" $(MAKE) up

up-installer:
	QEMU_CDROM="$${QEMU_CDROM:-/opt/hurd-installer/debian-hurd-amd64-installer.latest-mini.iso}" QEMU_BOOT_ORDER="$${QEMU_BOOT_ORDER:-d}" HURD_IMAGE_BASENAME="$${HURD_IMAGE_BASENAME:-debian-hurd-amd64.fresh.qcow2}" $(MAKE) up

up-podman: CONTAINER_RUNTIME=podman
up-podman:
	PODMAN_COMPOSE_PROVIDER="$${PODMAN_COMPOSE_PROVIDER:-podman-compose}" COMPOSE_FILE="$${COMPOSE_FILE:-$(COMPOSE_PODMAN_FILES)}" "$${PODMAN_COMPOSE_PROVIDER}" up -d

up-podman-kvm: CONTAINER_RUNTIME=podman
up-podman-kvm:
	PODMAN_COMPOSE_PROVIDER="$${PODMAN_COMPOSE_PROVIDER:-podman-compose}" COMPOSE_FILE="$${COMPOSE_FILE:-$(COMPOSE_PODMAN_KVM_FILES)}" "$${PODMAN_COMPOSE_PROVIDER}" up -d

up-podman-vnc: CONTAINER_RUNTIME=podman
up-podman-vnc:
	PODMAN_COMPOSE_PROVIDER="$${PODMAN_COMPOSE_PROVIDER:-podman-compose}" COMPOSE_FILE="$${COMPOSE_FILE:-$(COMPOSE_PODMAN_VNC_FILES)}" COMPOSE_PROFILES="$${COMPOSE_PROFILES:-vnc}" "$${PODMAN_COMPOSE_PROVIDER}" up -d

up-podman-latest: CONTAINER_RUNTIME=podman
up-podman-latest:
	HURD_IMAGE_BASENAME="$${HURD_IMAGE_BASENAME:-debian-hurd-amd64.latest.qcow2}" PODMAN_COMPOSE_PROVIDER="$${PODMAN_COMPOSE_PROVIDER:-podman-compose}" COMPOSE_FILE="$${COMPOSE_FILE:-$(COMPOSE_PODMAN_FILES)}" "$${PODMAN_COMPOSE_PROVIDER}" up -d

up-podman-installer: CONTAINER_RUNTIME=podman
up-podman-installer:
	QEMU_CDROM="$${QEMU_CDROM:-/opt/hurd-installer/debian-hurd-amd64-installer.latest-mini.iso}" QEMU_BOOT_ORDER="$${QEMU_BOOT_ORDER:-d}" HURD_IMAGE_BASENAME="$${HURD_IMAGE_BASENAME:-debian-hurd-amd64.fresh.qcow2}" PODMAN_COMPOSE_PROVIDER="$${PODMAN_COMPOSE_PROVIDER:-podman-compose}" COMPOSE_FILE="$${COMPOSE_FILE:-$(COMPOSE_PODMAN_FILES)}" "$${PODMAN_COMPOSE_PROVIDER}" up -d

down:
	@runtime="$${CONTAINER_RUNTIME:-$(CONTAINER_RUNTIME)}"; \
	if [ "$$runtime" = "podman" ]; then \
		compose_files="$${COMPOSE_FILE:-$(COMPOSE_PODMAN_FILES)}"; \
		compose_cmd="$${PODMAN_COMPOSE_PROVIDER:-podman-compose}"; \
		COMPOSE_FILE="$$compose_files" "$$compose_cmd" down --remove-orphans; \
	else \
		compose_files="$${COMPOSE_FILE:-$(COMPOSE_DEV_FILES)}"; \
		COMPOSE_FILE="$$compose_files" "$$runtime" compose down --remove-orphans; \
	fi

ps:
	@runtime="$${CONTAINER_RUNTIME:-$(CONTAINER_RUNTIME)}"; \
	if [ "$$runtime" = "podman" ]; then \
		compose_files="$${COMPOSE_FILE:-$(COMPOSE_PODMAN_FILES)}"; \
		compose_cmd="$${PODMAN_COMPOSE_PROVIDER:-podman-compose}"; \
		COMPOSE_FILE="$$compose_files" "$$compose_cmd" ps; \
	else \
		compose_files="$${COMPOSE_FILE:-$(COMPOSE_BASE_FILES)}"; \
		COMPOSE_FILE="$$compose_files" "$$runtime" compose ps; \
	fi

logs:
	@runtime="$${CONTAINER_RUNTIME:-$(CONTAINER_RUNTIME)}"; \
	if [ "$$runtime" = "podman" ]; then \
		compose_files="$${COMPOSE_FILE:-$(COMPOSE_PODMAN_FILES)}"; \
		service_name="$${SERVICE_NAME:-gnu-hurd-dev}"; \
		compose_cmd="$${PODMAN_COMPOSE_PROVIDER:-podman-compose}"; \
		COMPOSE_FILE="$$compose_files" "$$compose_cmd" logs -f "$$service_name"; \
	else \
		compose_files="$${COMPOSE_FILE:-$(COMPOSE_BASE_FILES)}"; \
		service_name="$${SERVICE_NAME:-$(SERVICE_NAME)}"; \
		COMPOSE_FILE="$$compose_files" "$$runtime" compose logs -f "$$service_name"; \
	fi

shell:
	@runtime="$${CONTAINER_RUNTIME:-$(CONTAINER_RUNTIME)}"; \
	if [ "$$runtime" = "podman" ]; then \
		compose_files="$${COMPOSE_FILE:-$(COMPOSE_PODMAN_FILES)}"; \
		service_name="$${SERVICE_NAME:-gnu-hurd-dev}"; \
		compose_cmd="$${PODMAN_COMPOSE_PROVIDER:-podman-compose}"; \
		COMPOSE_FILE="$$compose_files" "$$compose_cmd" exec "$$service_name" bash; \
	else \
		compose_files="$${COMPOSE_FILE:-$(COMPOSE_BASE_FILES)}"; \
		service_name="$${SERVICE_NAME:-$(SERVICE_NAME)}"; \
		COMPOSE_FILE="$$compose_files" "$$runtime" compose exec "$$service_name" bash; \
	fi
