.PHONY: help validate security lint links smoke-host smoke-container smoke-guest ports screenshot monitor sendkey setup build up up-kvm up-vnc up-kvm-vnc up-volume up-volume-vnc down logs shell

help:
	@echo "Targets:"
	@echo "  make validate         - validate repo invariants"
	@echo "  make security         - validate compose security posture"
	@echo "  make lint             - shellcheck scripts"
	@echo "  make links            - scan docs internal links"
	@echo "  make smoke-host       - host-side quick sanity"
	@echo "  make smoke-container  - container/QEMU process sanity (no guest assumptions)"
	@echo "  make smoke-guest      - guest readiness via SSH/serial (best-effort)"
	@echo "  make setup            - download+convert QCOW2 into ./images"
	@echo "  make build            - docker build via compose"
	@echo "  make screenshot       - capture QEMU screendump to logs/"
	@echo "  make monitor CMD=...  - run a QEMU monitor command"
	@echo "  make sendkey KEY=...  - send a QEMU monitor sendkey"
	@echo "  make ports            - check host port collisions"
	@echo "  make up|up-kvm|up-vnc|up-kvm-vnc|up-volume|up-volume-vnc|down|logs|shell"

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

build:
	docker compose build

up:
	./scripts/docker-orchestration.sh up

up-kvm:
	./scripts/docker-orchestration.sh up-kvm

up-vnc:
	./scripts/docker-orchestration.sh up-vnc

up-kvm-vnc:
	./scripts/docker-orchestration.sh up-kvm-vnc

up-volume:
	AUTO_DOWNLOAD_IMAGE=1 ./scripts/docker-orchestration.sh up-volume

up-volume-vnc:
	AUTO_DOWNLOAD_IMAGE=1 ./scripts/docker-orchestration.sh up-volume-vnc

down:
	./scripts/docker-orchestration.sh down

logs:
	./scripts/docker-orchestration.sh logs

shell:
	./scripts/docker-orchestration.sh shell
