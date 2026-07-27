.PHONY: help validate security lint topology overlay-lifecycle links runtime-info evidence-check guest-baseline-check hurd-archive-image hurd-closure hurd-build-closure hurd-build-closure-report hurd-closure-selftest hurd-closure-report smoke-host smoke-container smoke-guest ports screenshot monitor sendkey setup setup-latest setup-daily-installer rebuild-unattended-iso scripts-audit resolve-latest-image resolve-latest-daily-installer build build-podman compose-config up up-kvm up-vnc up-kvm-vnc up-volume up-volume-vnc up-latest up-installer up-podman up-podman-kvm up-podman-vnc up-podman-latest up-podman-installer qemu-fsm qemu-serial-fsm qemu-stall-probe qemu-full-auto qemu-auto-verify qemu-matrix vbox-doctor vbox-install-auto vbox-provision vbox-full-auto auto-fresh down ps logs shell

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
	@echo "  make topology                     - assert the service and port topology each Minty composition renders to"
	@echo "  make overlay-lifecycle            - exercise the disposable build overlay against a synthetic backing image"
	@echo "  make lint                         - shellcheck all scripts"
	@echo "  make links                        - scan docs for broken internal links"
	@echo "  make runtime-info                 - report the accelerator QEMU selected, plus host, declared, and guest facts"
	@echo "  make guest-baseline-check         - assert the committed guest baseline against itself"
	@echo "  make hurd-closure                 - classify a package set against the real hurd-amd64 or hurd-i386 archive (HURD_ARCH, HURD_SET)"
	@echo "  make hurd-build-closure           - report whether each rebuild candidate's build can start (HURD_ARCH)"
	@echo "  make hurd-closure-selftest        - run the resolver's offline fixture suite"
	@echo "  make hurd-closure-report          - write the closure report to evidence/hurd-archive/ (HURD_FOREIGN asks whether a foreign build coinstalls)"
	@echo "  make hurd-build-closure-report    - write the build-closure report to evidence/hurd-archive/ (HURD_ARCH)"
	@echo ""
	@echo "Minty Hurd profile (single QEMU service; overlays compose on top):"
	@echo "  make minty-up                     - start the Minty guest, letting the entrypoint select the accelerator"
	@echo "  make minty-up-tcg                 - start with DISABLE_KVM=1"
	@echo "  make minty-up-kvm                 - start with the KVM overlay and FORCE_KVM=1"
	@echo "  make minty-up-vnc                 - start with the VNC overlay and the noVNC sidecar"
	@echo "  make minty-up-kvm-vnc             - start with both overlays"
	@echo "  make minty-accel                  - print the accelerator decision record the entrypoint wrote"
	@echo "  make minty-export-state           - export the guest installed-package manifest to evidence/guest-state/"
	@echo "  make minty-collect-baseline       - collect the whole guest baseline from one running guest"
	@echo "  make minty-baseline-run-manifest  - derive the baseline run manifest from the artifacts it indexes"
	@echo "  make minty-down / minty-status / minty-logs / minty-ssh"
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
	@echo "  make setup-daily-installer        - fetch latest d-i mini.iso + build mini-auto.iso + create fresh qcow2 target disk"
	@echo "  make rebuild-unattended-iso       - rebuild mini-auto.iso from locally cached base ISO + current preseed"
	@echo "  make scripts-audit                - generate scripts inventory + synthesis report"
	@echo ""
	@echo "Operation (Docker defaults):"
	@echo "  make up                           - start bind-mode stack"
	@echo "  make up-kvm                       - start bind-mode + overlay exposing /dev/kvm (the entrypoint still selects the accelerator; run 'make runtime-info' to read which)"
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
	@echo "QEMU-First Unattended Flows:"
	@echo "  make qemu-fsm                     - run expect FSM controller against running QEMU monitor"
	@echo "  make qemu-serial-fsm              - run serial-log FSM controller against running unattended install"
	@echo "  make qemu-stall-probe             - execute active stall probe against a running stalled installer"
	@echo "  make qemu-full-auto               - unattended installer -> SSH -> provisioning via standalone QEMU"
	@echo "  make qemu-auto-verify             - run repeated unattended verification attempts (ATTEMPTS=3 default)"
	@echo "  make qemu-matrix                  - run bus/disk/cpu unattended matrix with per-run evidence"
	@echo ""
	@echo "Unattended Fresh Installer Flows:"
	@echo "  make auto-fresh                   - default qemu-first unattended flow (override BACKEND=...)"
	@echo "  make vbox-doctor                  - conceptual stub (VBox non-operational in this phase)"
	@echo "  make vbox-install-auto            - conceptual stub (use qemu-* targets)"
	@echo "  make vbox-provision               - conceptual stub (use qemu-* targets)"
	@echo "  make vbox-full-auto               - conceptual stub (use qemu-* targets)"
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

# An overlay declaring a service the base file does not adds a service
# rather than overriding one, and its own text reads as correct. The
# rendered configuration is where a second QEMU container becomes visible.
topology:
	CONTAINER_RUNTIME="$(CONTAINER_RUNTIME)" python3 scripts/check-compose-topology.py

# The archive fixtures cover the resolver and say nothing about the entrypoint,
# so this drives the real overlay mechanism in a real container and reads the
# filesystem afterwards. It reports itself not run when the image is absent.
overlay-lifecycle:
	$(CONTAINER_RUNTIME) build -q -t gnu-hurd-docker:overlay-lifecycle . >/dev/null
	CONTAINER_RUNTIME="$(CONTAINER_RUNTIME)" ./tests/overlay-lifecycle/run.sh

# error is the enforced level: every maintained script passes it. Warning-level
# findings are real work that is tracked as roadmap item 43, so raising the
# default here without clearing them first would make `make lint` fail on a
# clean tree. Run `make lint SHELLCHECK_SEVERITY=warning` to see them.
SHELLCHECK_SEVERITY ?= error

lint:
	SHELLCHECK_SEVERITY="$(SHELLCHECK_SEVERITY)" ./scripts/check-maintained-shell.sh

# link-scanner.py reports its findings and exits 0 whatever it finds, so every
# caller of this target got a pass regardless. check-link-scan-result.py reads
# the broken-link count out of the JSON report and supplies the exit status.
LINK_SCAN_JSON ?= $(CURDIR)/link-scan.json

links:
	python3 scripts/utils/link-scanner.py --docs-root docs --json "$(LINK_SCAN_JSON)"
	python3 scripts/check-link-scan-result.py "$(LINK_SCAN_JSON)"

# The accelerator QEMU selected reaches an operator only from the argv and the
# monitor: /dev/kvm being present, FORCE_KVM being set, and a target named
# up-kvm each state a request.  capture-runtime-evidence.py binds every field to
# one QEMU instance it selected by finding the process, and labels the request
# and the outcome separately.
runtime-info:
	@capture=$$(python3 scripts/capture-runtime-evidence.py) && \
		python3 scripts/report-runtime-evidence.py "$$capture" && \
		echo "Capture: $$capture"

# The schema constrains a capture document; it cannot see whether the streams a
# probe advertises exist or whether their digests describe the bytes on disk.
# The negative fixtures assert what the contract rejects, because a schema
# exercised only by documents it accepts states nothing about its exclusions.
#
# The producer suite runs first and calls the instrument itself.  Fixtures that
# hand-build documents exercise the checker alone, so a redaction pass that
# corrupts the JSON a probe returns passes them while destroying every capture.
evidence-check:
	python3 tests/runtime-evidence/test-capture-producer.py
	python3 tests/runtime-evidence/test-runtime-evidence-contract.py
	@set -e; captures=$$(git ls-files 'evidence/runtime/*/capture.json' \
		'evidence/runtime/*/*/capture.json' | xargs -r -n1 dirname | sort -u); \
	if [ -n "$$captures" ]; then \
		python3 scripts/check-runtime-evidence.py --require-redacted $$captures; \
	else \
		echo "evidence-check: no committed captures to validate"; \
	fi

# A committed baseline degrades quietly: a probe whose command stopped working
# leaves a marker that reads as a guest fact, and a digest stops matching the
# file beside it.  None of that is visible in review, because a broken artifact
# looks exactly like a correct one.  This asserts the package against itself.
#
# The fixture suite runs first and drives the checker against baselines whose
# defect is known, because a checker exercised only by packages it accepts
# states nothing about its exclusions.
guest-baseline-check:
	python3 tests/guest-baseline/selftest.py
	@set -e; roots=$$(git ls-files 'evidence/guest-state/probes.json' \
		'evidence/guest-state/*/probes.json' | xargs -r -n1 dirname | sort -u); \
	if [ -n "$$roots" ]; then \
		for root in $$roots; do \
			python3 scripts/check-guest-baseline.py "$$root"; \
		done; \
	else \
		echo "guest-baseline-check: no committed baseline to validate"; \
	fi

# Availability and dependency facts are archive facts, so they are read on the
# host in seconds rather than from a guest that takes minutes to boot and holds
# one mutable qcow2. Hurd binaries cannot execute here; the boundary probe is in
# docs/audits/hurd-execution-boundary-and-archive-layer.md.
HURD_ARCH ?= hurd-amd64
HURD_SET ?= mate-bootstrap
HURD_CLOSURE_DIR ?= evidence/hurd-archive
# Setting this asks whether a foreign build installs into a native tree, the way
# dpkg --add-architecture would. It answers a packaging question and says
# nothing about whether a foreign process runs, which is a guest fact.
# A closure that schedules a build is pinned to one archive state, because sid
# and unreleased move and an unpinned report carries a verdict the build cannot
# reproduce. Exploratory reports may stay unpinned; their provenance says so.
HURD_ARCHIVE_SNAPSHOT ?=
HURD_SNAPSHOT_FLAG = $(if $(HURD_ARCHIVE_SNAPSHOT),--archive-snapshot "$(HURD_ARCHIVE_SNAPSHOT)",)

# Without a baseline every verdict describes an empty system, so a removal list
# is empty by construction rather than by observation. Point this at a status
# file exported from the guest to ask what this image would accept.
HURD_INSTALLED_STATUS ?=
HURD_STATUS_FLAG = $(if $(HURD_INSTALLED_STATUS),--installed-status "/status",)
HURD_STATUS_MOUNT = $(if $(HURD_INSTALLED_STATUS),-v "$(CURDIR)/$(HURD_INSTALLED_STATUS):/status:ro",)

HURD_FOREIGN ?=

hurd-archive-image:
	$(CONTAINER_RUNTIME) build -f Dockerfile.hurd-archive -t gnu-hurd-archive:local .

# The self-test runs offline against fixture archives and never compares against
# the committed reports, because sid, unreleased, and the LMDE suite move daily
# and such a comparison would turn someone else's upload into a red gate.
hurd-closure-selftest: hurd-archive-image
	$(CONTAINER_RUNTIME) run --rm gnu-hurd-archive:local --self-test

# Whether a binary exists and whether it can be produced are different archive
# questions. This asks the second: the build closure for each named source
# package against the target port's binaries plus main-archive source.
hurd-build-closure: hurd-archive-image
	$(CONTAINER_RUNTIME) run --rm gnu-hurd-archive:local \
		--architecture "$(HURD_ARCH)" --set rebuild-candidates \
		--build-dependencies --no-lmde $(HURD_SNAPSHOT_FLAG)

hurd-closure: hurd-archive-image
	$(CONTAINER_RUNTIME) run --rm gnu-hurd-archive:local \
		--architecture "$(HURD_ARCH)" --set "$(HURD_SET)" \
		--foreign-architecture "$(HURD_FOREIGN)" $(HURD_SNAPSHOT_FLAG)

# The report is written through a bind mount, because a report that stays inside
# a --rm container is a number in a terminal rather than an artifact.
hurd-closure-report: hurd-archive-image
	mkdir -p "$(HURD_CLOSURE_DIR)"
	$(CONTAINER_RUNTIME) run --rm \
		--user "$$(id -u):$$(id -g)" \
		-v "$(CURDIR)/$(HURD_CLOSURE_DIR):/out" $(HURD_STATUS_MOUNT) \
		gnu-hurd-archive:local \
		--architecture "$(HURD_ARCH)" --set "$(HURD_SET)" $(HURD_STATUS_FLAG) \
		--foreign-architecture "$(HURD_FOREIGN)" $(HURD_SNAPSHOT_FLAG) \
		--json "/out/$(HURD_ARCH)$(if $(HURD_FOREIGN),-foreign-$(HURD_FOREIGN),)-$(HURD_SET).json"

# The build reports are committed evidence, so the command that produced them is
# a target rather than an invocation someone reconstructs from the report.
hurd-build-closure-report: hurd-archive-image
	mkdir -p "$(HURD_CLOSURE_DIR)"
	$(CONTAINER_RUNTIME) run --rm \
		--user "$$(id -u):$$(id -g)" \
		-v "$(CURDIR)/$(HURD_CLOSURE_DIR):/out" $(HURD_STATUS_MOUNT) \
		gnu-hurd-archive:local \
		--architecture "$(HURD_ARCH)" --set rebuild-candidates $(HURD_STATUS_FLAG) \
		--build-dependencies --no-lmde $(HURD_SNAPSHOT_FLAG) \
		--json "/out/$(HURD_ARCH)-build-closure-rebuild-candidates.json"

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

rebuild-unattended-iso:
	./scripts/rebuild-hurd-unattended-iso.sh

scripts-audit:
	./scripts/scripts-inventory-audit.sh

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
	QEMU_CDROM="$${QEMU_CDROM:-/opt/hurd-installer/debian-hurd-amd64-installer.latest-mini-auto.iso}" QEMU_BOOT_ORDER="$${QEMU_BOOT_ORDER:-d}" HURD_IMAGE_BASENAME="$${HURD_IMAGE_BASENAME:-debian-hurd-amd64.fresh.qcow2}" $(MAKE) up

up-podman: CONTAINER_RUNTIME=podman
up-podman:
	PODMAN_COMPOSE_PROVIDER="$${PODMAN_COMPOSE_PROVIDER:-podman-compose}" COMPOSE_FILE="$${COMPOSE_FILE:-$(COMPOSE_PODMAN_FILES)}" "$${PODMAN_COMPOSE_PROVIDER}" up -d

up-podman-kvm: CONTAINER_RUNTIME=podman
up-podman-kvm:
	PODMAN_COMPOSE_PROVIDER="$${PODMAN_COMPOSE_PROVIDER:-podman-compose}" COMPOSE_FILE="$${COMPOSE_FILE:-$(COMPOSE_PODMAN_KVM_FILES)}" "$${PODMAN_COMPOSE_PROVIDER}" up -d

up-podman-vnc: CONTAINER_RUNTIME=podman
up-podman-vnc:
	PODMAN_COMPOSE_PROVIDER="$${PODMAN_COMPOSE_PROVIDER:-podman-compose}" COMPOSE_FILE="$${COMPOSE_FILE:-$(COMPOSE_PODMAN_VNC_FILES)}" "$${PODMAN_COMPOSE_PROVIDER}" --profile "$${COMPOSE_PROFILES:-vnc}" up -d

up-podman-latest: CONTAINER_RUNTIME=podman
up-podman-latest:
	HURD_IMAGE_BASENAME="$${HURD_IMAGE_BASENAME:-debian-hurd-amd64.latest.qcow2}" PODMAN_COMPOSE_PROVIDER="$${PODMAN_COMPOSE_PROVIDER:-podman-compose}" COMPOSE_FILE="$${COMPOSE_FILE:-$(COMPOSE_PODMAN_FILES)}" "$${PODMAN_COMPOSE_PROVIDER}" up -d

up-podman-installer: CONTAINER_RUNTIME=podman
up-podman-installer:
	QEMU_CDROM="$${QEMU_CDROM:-/opt/hurd-installer/debian-hurd-amd64-installer.latest-mini-auto.iso}" QEMU_BOOT_ORDER="$${QEMU_BOOT_ORDER:-d}" HURD_IMAGE_BASENAME="$${HURD_IMAGE_BASENAME:-debian-hurd-amd64.fresh.qcow2}" PODMAN_COMPOSE_PROVIDER="$${PODMAN_COMPOSE_PROVIDER:-podman-compose}" COMPOSE_FILE="$${COMPOSE_FILE:-$(COMPOSE_PODMAN_FILES)}" "$${PODMAN_COMPOSE_PROVIDER}" up -d

qemu-fsm:
	MONITOR_HOST="$${MONITOR_HOST:-127.0.0.1}" MONITOR_PORT="$${MONITOR_PORT:-9998}" SSH_HOST="$${SSH_HOST:-127.0.0.1}" SSH_PORT="$${SSH_PORT:-2226}" ./scripts/qemu-install-fsm.expect

qemu-serial-fsm:
	SSH_HOST="$${SSH_HOST:-127.0.0.1}" SSH_PORT="$${SSH_PORT:-2226}" MONITOR_HOST="$${MONITOR_HOST:-127.0.0.1}" MONITOR_PORT="$${MONITOR_PORT:-9998}" SERIAL_LOG="$${SERIAL_LOG:-logs/serial-install.log}" FSM_TIMEOUT_SEC="$${FSM_TIMEOUT_SEC:-3600}" FSM_POLL_MS="$${FSM_POLL_MS:-2500}" STALL_TIMEOUT_SEC="$${STALL_TIMEOUT_SEC:-420}" STALL_PROBE_MODE="$${STALL_PROBE_MODE:-deep_retry}" STALL_PROBE_RETRY_COUNT="$${STALL_PROBE_RETRY_COUNT:-3}" STALL_PROBE_RETRY_TIMEOUT_SEC="$${STALL_PROBE_RETRY_TIMEOUT_SEC:-90}" STALL_CAPTURE_MAX_PAGES="$${STALL_CAPTURE_MAX_PAGES:-12}" FSM_STATE_LOG="$${FSM_STATE_LOG:-logs/fsm-serial-state.log}" ./scripts/qemu-install-serial-fsm.sh

qemu-stall-probe:
	MONITOR_HOST="$${MONITOR_HOST:-127.0.0.1}" MONITOR_PORT="$${MONITOR_PORT:-9998}" SERIAL_LOG="$${SERIAL_LOG:-logs/serial-install.log}" PROBE_MODE="$${PROBE_MODE:-deep_retry}" RETRY_COUNT="$${RETRY_COUNT:-3}" RETRY_TIMEOUT_SEC="$${RETRY_TIMEOUT_SEC:-90}" CAPTURE_MAX_PAGES="$${CAPTURE_MAX_PAGES:-12}" PROBE_DIR="$${PROBE_DIR:-logs/stall-probe}" ./scripts/qemu-stall-probe.sh

qemu-full-auto:
	./scripts/install-hurd-unattended.sh --backend qemu --profile "$${PROFILE:-x11}"

qemu-auto-verify:
	ATTEMPTS="$${ATTEMPTS:-3}" PROFILE="$${PROFILE:-x11}" SKIP_SETUP="$${SKIP_SETUP:-1}" QEMU_DISK_BUS="$${QEMU_DISK_BUS:-ide}" QEMU_CPUS="$${QEMU_CPUS:-1}" QEMU_INSTALL_DISK_SIZE="$${QEMU_INSTALL_DISK_SIZE:-20G}" FSM_BACKEND="$${FSM_BACKEND:-serial}" STALL_TIMEOUT_SEC="$${STALL_TIMEOUT_SEC:-420}" STALL_PROBE_MODE="$${STALL_PROBE_MODE:-deep_retry}" STALL_PROBE_RETRY_COUNT="$${STALL_PROBE_RETRY_COUNT:-3}" STALL_PROBE_RETRY_TIMEOUT_SEC="$${STALL_PROBE_RETRY_TIMEOUT_SEC:-90}" STALL_CAPTURE_MAX_PAGES="$${STALL_CAPTURE_MAX_PAGES:-12}" INSTALL_TIMEOUT_SEC="$${INSTALL_TIMEOUT_SEC:-3600}" BOOT_TIMEOUT_SEC="$${BOOT_TIMEOUT_SEC:-900}" ./scripts/qemu-auto-verify.sh

qemu-matrix:
	PROFILE="$${PROFILE:-x11}" SKIP_SETUP="$${SKIP_SETUP:-1}" MATRIX_ATTEMPTS="$${MATRIX_ATTEMPTS:-2}" MATRIX_BUSES="$${MATRIX_BUSES:-ide,ahci,virtio-blk}" MATRIX_DISK_SIZES="$${MATRIX_DISK_SIZES:-4G,20G}" MATRIX_CPUS="$${MATRIX_CPUS:-1,2}" FSM_BACKEND="$${FSM_BACKEND:-serial}" STALL_TIMEOUT_SEC="$${STALL_TIMEOUT_SEC:-420}" STALL_PROBE_MODE="$${STALL_PROBE_MODE:-deep_retry}" STALL_PROBE_RETRY_COUNT="$${STALL_PROBE_RETRY_COUNT:-3}" STALL_PROBE_RETRY_TIMEOUT_SEC="$${STALL_PROBE_RETRY_TIMEOUT_SEC:-90}" STALL_CAPTURE_MAX_PAGES="$${STALL_CAPTURE_MAX_PAGES:-12}" INSTALL_TIMEOUT_SEC="$${INSTALL_TIMEOUT_SEC:-2400}" BOOT_TIMEOUT_SEC="$${BOOT_TIMEOUT_SEC:-600}" ./scripts/qemu-matrix-runner.sh

vbox-doctor:
	./scripts/vboxmanage-hurd.sh doctor

vbox-install-auto:
	./scripts/vboxmanage-hurd.sh install-auto

vbox-provision:
	./scripts/vboxmanage-hurd.sh provision

vbox-full-auto:
	./scripts/vboxmanage-hurd.sh full-auto

auto-fresh:
	./scripts/install-hurd-unattended.sh --backend "$${BACKEND:-qemu}" --profile "$${PROFILE:-x11}"

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

# ===== Minty Hurd targets =====
.PHONY: minty-up minty-up-tcg minty-up-kvm minty-up-vnc minty-up-kvm-vnc \
	minty-down minty-status minty-logs minty-container-shell minty-accel \
	minty-ssh minty-shell minty-export-state minty-collect-baseline \
	minty-baseline-run-manifest \
	minty-image-check oobe

# Stage the out-of-box experience on the RUNNING guest: sets the documented
# generic passwords (user/user, root/root) and expires them so the first
# interactive login forces a password change. Run as the last step before
# shutting the guest down to publish its image.
OOBE_SSH_KEY ?= ssh-test-keys/hurd_test_key
OOBE_SSH_PORT ?= 2222

oobe:
	@ssh -i $(OOBE_SSH_KEY) -p $(OOBE_SSH_PORT) \
		-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		root@127.0.0.1 'sh -s' < scripts/oobe-first-login.sh

# compose.minty.yaml overlays the canonical gnu-hurd-dev service, so the image
# bind, the KVM device, and the VNC surface come from the overlays that own
# them. Each target names the composition it wants rather than restating the
# service, and `up`, `down`, `ps`, and `logs` share one file set so a target
# cannot address a different stack than the one it started.
MINTY_CONTAINER_IMAGE ?= gnu-hurd-docker:latest
# compose.minty.yaml reads this from the environment, so the tag the guard
# checked and the tag Compose selects are the same value.
export MINTY_CONTAINER_IMAGE
MINTY_FILES ?= compose.yaml:compose.bind.yaml:compose.minty.yaml
MINTY_KVM_FILES ?= $(MINTY_FILES):compose.kvm.yaml
MINTY_VNC_FILES ?= $(MINTY_FILES):compose.vnc.yaml
MINTY_KVM_VNC_FILES ?= $(MINTY_FILES):compose.kvm.yaml:compose.vnc.yaml

MINTY_SSH_KEY ?= ssh-test-keys/hurd_test_key
MINTY_SSH_PORT ?= $(SSH_PORT)
SSH_PORT ?= 2222

# The accelerator is the entrypoint's decision, so a target selects the inputs
# and reads the outcome back from the decision record rather than claiming one.
# The base file pulls a GHCR tag that does resolve, and that is the problem: it
# was last published 2026-01-11 and every push run since has failed before the
# push step, so a bare pull silently supplies a stale image rather than failing.
# The Minty overlay selects the tag docker-bake.hcl produces locally, and this
# check names the build command instead of letting the run fall through to a
# registry.
minty-image-check:
	@$(CONTAINER_RUNTIME) image inspect "$(MINTY_CONTAINER_IMAGE)" >/dev/null 2>&1 \
		|| { echo "The Minty profile needs the local image $(MINTY_CONTAINER_IMAGE)."; \
		     echo "Build it with:  make build"; \
		     echo "Or select another with:  make minty-up MINTY_CONTAINER_IMAGE=<tag>"; \
		     exit 1; }

minty-up: minty-image-check
	COMPOSE_FILE="$(MINTY_FILES)" $(COMPOSE) up -d $(SERVICE_NAME)

minty-up-tcg: minty-image-check
	DISABLE_KVM=1 COMPOSE_FILE="$(MINTY_FILES)" $(COMPOSE) up -d $(SERVICE_NAME)

minty-up-kvm: minty-image-check
	FORCE_KVM=1 COMPOSE_FILE="$(MINTY_KVM_FILES)" $(COMPOSE) up -d $(SERVICE_NAME)

# The noVNC sidecar sits behind a Compose profile, so it is named explicitly.
minty-up-vnc: minty-image-check
	COMPOSE_FILE="$(MINTY_VNC_FILES)" $(COMPOSE) --profile vnc up -d

minty-up-kvm-vnc: minty-image-check
	FORCE_KVM=1 COMPOSE_FILE="$(MINTY_KVM_VNC_FILES)" $(COMPOSE) --profile vnc up -d

minty-down:
	COMPOSE_FILE="$(MINTY_KVM_VNC_FILES)" $(COMPOSE) --profile vnc down --remove-orphans

minty-status:
	COMPOSE_FILE="$(MINTY_FILES)" $(COMPOSE) ps

minty-logs:
	COMPOSE_FILE="$(MINTY_FILES)" $(COMPOSE) logs -f $(SERVICE_NAME)

minty-container-shell:
	COMPOSE_FILE="$(MINTY_FILES)" $(COMPOSE) exec $(SERVICE_NAME) bash

# The accelerator the entrypoint selected, read from the record it wrote.
minty-accel:
	COMPOSE_FILE="$(MINTY_FILES)" $(COMPOSE) exec -T $(SERVICE_NAME) \
		cat /run/hurd/accelerator-decision.json

# Every closure verdict is resolved against an empty dpkg status file, so a
# transaction has no installed package to displace. This is what seeds a
# resolver run with the real guest, and it reports itself not run when the
# guest does not answer.
minty-export-state:
	./scripts/export-guest-package-state.sh

# A boot is expensive enough that collecting one artifact from it wastes the
# other dozen, so the baseline collection is one target over one running guest.
#
# The image digest reaches the status export from here, because a status file
# that names no image is a package list from somewhere: the collector reads the
# guest and the host is what knows which qcow2 the guest was booted from.
MINTY_GUEST_IMAGE ?= images/hurd-working.qcow2

minty-collect-baseline:
	GUEST_SSH_PORT="$(MINTY_SSH_PORT)" \
		GUEST_IMAGE_SHA256="$$(sha256sum "$(MINTY_GUEST_IMAGE)" | cut -d' ' -f1)" \
		./scripts/collect-guest-baseline.sh

# The probe records come from the guest; the run-level facts sit outside it and
# outside the collector's reach.  A manifest typed by hand drifts from the
# artifacts it indexes, so it is derived from them the way the build lock is.
# The measurements the host alone holds are named on the command line and
# refused when absent, and the container has to still be running for its image
# and QEMU version to be readable.
MINTY_BASELINE_ACCEL ?= tcg
MINTY_BASELINE_REASON ?= disable_kvm_requested
MINTY_BASELINE_FSCK ?= not run
MINTY_BASELINE_BEFORE ?=
MINTY_BASELINE_CONTAINER ?=

minty-baseline-run-manifest:
	python3 scripts/write-guest-baseline-run.py \
		--backing-image "$(MINTY_GUEST_IMAGE)" \
		--backing-sha256-before "$(MINTY_BASELINE_BEFORE)" \
		--accelerator "$(MINTY_BASELINE_ACCEL)" \
		--accelerator-reason-code "$(MINTY_BASELINE_REASON)" \
		--offline-fsck "$(MINTY_BASELINE_FSCK)" \
		--container "$(MINTY_BASELINE_CONTAINER)" \
		$(MINTY_BASELINE_EXTRA)

minty-ssh:
	@ssh -i $(MINTY_SSH_KEY) -p $(MINTY_SSH_PORT) user@127.0.0.1

minty-shell: minty-ssh
