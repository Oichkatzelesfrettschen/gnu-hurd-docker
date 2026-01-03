# =============================================================================
# GNU/Hurd Docker - Comprehensive Build System
# =============================================================================
# Platform-agnostic build orchestration for Docker/Podman environments
# Supports: Linux, macOS, Windows (WSL), BSD
# =============================================================================

.PHONY: help all clean test build up down logs shell \
        lint lint-shell lint-yaml lint-python lint-docker \
        test-unit test-integration test-system \
        coverage profile benchmark \
        security security-scan security-audit \
        docs docs-serve docs-build \
        install install-deps install-runtime \
        validate validate-config validate-security \
        snapshot snapshot-list snapshot-restore \
        podman-setup podman-test \
        platform-check

# Default target
.DEFAULT_GOAL := help

# =============================================================================
# Configuration
# =============================================================================

# Detect container runtime (docker or podman)
CONTAINER_RUNTIME ?= $(shell command -v docker 2>/dev/null || command -v podman 2>/dev/null || echo "none")
RUNTIME_NAME := $(notdir $(CONTAINER_RUNTIME))

# Compose command
ifeq ($(RUNTIME_NAME),docker)
    COMPOSE_CMD := $(shell docker compose version >/dev/null 2>&1 && echo "docker compose" || echo "docker-compose")
else ifeq ($(RUNTIME_NAME),podman)
    COMPOSE_CMD := podman-compose
else
    COMPOSE_CMD := echo "No container runtime found"
endif

# Project metadata
PROJECT_NAME := gnu-hurd-docker
IMAGE_NAME := ghcr.io/oichkatzelesfrettschen/$(PROJECT_NAME)
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")

# Directories
SCRIPTS_DIR := scripts
DOCS_DIR := docs
BUILD_DIR := build
COVERAGE_DIR := $(BUILD_DIR)/coverage
REPORTS_DIR := $(BUILD_DIR)/reports

# Platform detection
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)
ifeq ($(UNAME_S),Linux)
    PLATFORM := linux
    KVM_AVAILABLE := $(shell test -e /dev/kvm && echo "yes" || echo "no")
else ifeq ($(UNAME_S),Darwin)
    PLATFORM := macos
    KVM_AVAILABLE := no
else ifeq ($(findstring MINGW,$(UNAME_S)),MINGW)
    PLATFORM := windows
    KVM_AVAILABLE := no
else ifeq ($(findstring BSD,$(UNAME_S)),BSD)
    PLATFORM := bsd
    KVM_AVAILABLE := no
else
    PLATFORM := unknown
    KVM_AVAILABLE := no
endif

# Colors for output
RESET := \033[0m
BOLD := \033[1m
RED := \033[31m
GREEN := \033[32m
YELLOW := \033[33m
BLUE := \033[34m

# =============================================================================
# Help
# =============================================================================

help: ## Show this help message
	@echo "$(BOLD)$(PROJECT_NAME) - Build System$(RESET)"
	@echo "$(BLUE)Runtime: $(RUNTIME_NAME) | Platform: $(PLATFORM) | Arch: $(UNAME_M) | KVM: $(KVM_AVAILABLE)$(RESET)"
	@echo ""
	@echo "$(BOLD)Common Targets:$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}' | \
		grep -E "(up|down|build|test|clean|help)"
	@echo ""
	@echo "$(BOLD)All Targets:$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'

# =============================================================================
# Platform & Runtime Check
# =============================================================================

platform-check: ## Display platform and runtime information
	@echo "$(BOLD)Platform Information:$(RESET)"
	@echo "  OS: $(UNAME_S)"
	@echo "  Architecture: $(UNAME_M)"
	@echo "  Platform: $(PLATFORM)"
	@echo "  Container Runtime: $(RUNTIME_NAME)"
	@echo "  Compose Command: $(COMPOSE_CMD)"
	@echo "  KVM Available: $(KVM_AVAILABLE)"
	@if [ "$(RUNTIME_NAME)" = "none" ]; then \
		echo "$(RED)ERROR: No container runtime found!$(RESET)"; \
		echo "Install Docker: https://docs.docker.com/get-docker/"; \
		echo "Install Podman: https://podman.io/getting-started/installation"; \
		exit 1; \
	fi

# =============================================================================
# Container Operations
# =============================================================================

up: platform-check ## Start the Hurd container (auto-detects runtime)
	@echo "$(GREEN)Starting GNU/Hurd container with $(RUNTIME_NAME)...$(RESET)"
	$(COMPOSE_CMD) up -d
	@echo "$(GREEN)Container started. Waiting for boot (2-5 minutes)...$(RESET)"
	@echo "Monitor logs: make logs"
	@echo "Connect via SSH: ssh -p 2222 root@localhost"

down: ## Stop the Hurd container
	@echo "$(YELLOW)Stopping GNU/Hurd container...$(RESET)"
	$(COMPOSE_CMD) down

restart: down up ## Restart the Hurd container

logs: ## Show container logs (follow mode)
	$(COMPOSE_CMD) logs -f

status: ## Show container status
	$(COMPOSE_CMD) ps

shell: ## Open shell in running container
	@$(COMPOSE_CMD) exec hurd-x86_64 /bin/bash || \
		echo "$(RED)Container not running. Start with 'make up'$(RESET)"

# =============================================================================
# Build Operations
# =============================================================================

build: ## Build container image
	@echo "$(GREEN)Building $(IMAGE_NAME):$(VERSION)...$(RESET)"
	$(RUNTIME_NAME) build -t $(IMAGE_NAME):$(VERSION) -t $(IMAGE_NAME):latest .

build-no-cache: ## Build container image without cache
	@echo "$(GREEN)Building $(IMAGE_NAME):$(VERSION) (no cache)...$(RESET)"
	$(RUNTIME_NAME) build --no-cache -t $(IMAGE_NAME):$(VERSION) -t $(IMAGE_NAME):latest .

push: ## Push image to registry
	@echo "$(GREEN)Pushing $(IMAGE_NAME):$(VERSION)...$(RESET)"
	$(RUNTIME_NAME) push $(IMAGE_NAME):$(VERSION)
	$(RUNTIME_NAME) push $(IMAGE_NAME):latest

# =============================================================================
# Linting & Code Quality
# =============================================================================

lint: lint-shell lint-yaml lint-docker ## Run all linters

lint-shell: ## Run ShellCheck on all shell scripts
	@echo "$(BLUE)Running ShellCheck...$(RESET)"
	@find . -name "*.sh" -type f ! -path "./.git/*" -exec shellcheck -S warning {} + || \
		(echo "$(RED)ShellCheck failed!$(RESET)" && exit 1)
	@echo "$(GREEN)ShellCheck passed!$(RESET)"

lint-yaml: ## Run yamllint on YAML files
	@echo "$(BLUE)Running yamllint...$(RESET)"
	@yamllint -c .yamllint docker-compose*.yml .github/workflows/*.yml mkdocs.yml || \
		(echo "$(RED)yamllint failed!$(RESET)" && exit 1)
	@echo "$(GREEN)yamllint passed!$(RESET)"

lint-python: ## Run Python linters (black, flake8)
	@echo "$(BLUE)Running Python linters...$(RESET)"
	@find $(SCRIPTS_DIR) -name "*.py" -exec black --check {} + || true
	@find $(SCRIPTS_DIR) -name "*.py" -exec flake8 --max-line-length=100 {} + || true
	@echo "$(GREEN)Python linting complete!$(RESET)"

lint-docker: ## Run Hadolint on Dockerfile
	@echo "$(BLUE)Running Hadolint...$(RESET)"
	@hadolint Dockerfile || (echo "$(RED)Hadolint failed!$(RESET)" && exit 1)
	@echo "$(GREEN)Hadolint passed!$(RESET)"

# =============================================================================
# Testing
# =============================================================================

test: test-system test-integration ## Run all tests

test-unit: ## Run unit tests
	@echo "$(BLUE)Running unit tests...$(RESET)"
	@bash $(SCRIPTS_DIR)/lib/test-package-libs.sh || true

test-integration: ## Run integration tests
	@echo "$(BLUE)Running integration tests...$(RESET)"
	@bash $(SCRIPTS_DIR)/test-docker.sh || true

test-system: ## Run system tests (requires running container)
	@echo "$(BLUE)Running system tests...$(RESET)"
	@bash $(SCRIPTS_DIR)/test-hurd-system.sh || true

# =============================================================================
# Coverage & Profiling
# =============================================================================

coverage: ## Generate code coverage report
	@echo "$(BLUE)Generating coverage report...$(RESET)"
	@mkdir -p $(COVERAGE_DIR)
	@echo "Coverage analysis requires instrumentation - see docs for details"
	@echo "$(YELLOW)Coverage tooling: lcov/gcov, kcov for bash$(RESET)"

profile: ## Profile QEMU performance
	@echo "$(BLUE)Profiling QEMU...$(RESET)"
	@mkdir -p $(REPORTS_DIR)
	@bash $(SCRIPTS_DIR)/monitor-qemu.sh || true

benchmark: ## Run performance benchmarks
	@echo "$(BLUE)Running benchmarks...$(RESET)"
	@echo "Benchmark suite requires running Hurd instance"

# =============================================================================
# Security
# =============================================================================

security: security-scan security-audit ## Run all security checks

security-scan: ## Scan for vulnerabilities with Trivy
	@echo "$(BLUE)Running Trivy security scan...$(RESET)"
	@command -v trivy >/dev/null 2>&1 || \
		(echo "$(YELLOW)Trivy not found. Install: https://aquasecurity.github.io/trivy/$(RESET)" && exit 1)
	@trivy filesystem --severity CRITICAL,HIGH,MEDIUM .
	@trivy config Dockerfile

security-audit: ## Audit scripts and configuration
	@echo "$(BLUE)Running security audit...$(RESET)"
	@bash $(SCRIPTS_DIR)/validate-security-config.sh || true

# =============================================================================
# Documentation
# =============================================================================

docs: docs-build ## Build documentation with MkDocs

docs-build: ## Build static documentation site
	@echo "$(BLUE)Building documentation...$(RESET)"
	@command -v mkdocs >/dev/null 2>&1 || \
		(echo "$(YELLOW)mkdocs not found. Install: pip install mkdocs-material$(RESET)" && exit 1)
	@mkdocs build

docs-serve: ## Serve documentation locally
	@echo "$(BLUE)Serving documentation at http://localhost:8000$(RESET)"
	@mkdocs serve

# =============================================================================
# Validation
# =============================================================================

validate: validate-config validate-security lint ## Run all validation checks

validate-config: ## Validate configuration files
	@echo "$(BLUE)Validating configuration...$(RESET)"
	@bash $(SCRIPTS_DIR)/validate-config.sh || true

validate-security: ## Validate security configuration
	@echo "$(BLUE)Validating security configuration...$(RESET)"
	@bash $(SCRIPTS_DIR)/validate-security-config.sh || true

# =============================================================================
# Snapshots
# =============================================================================

snapshot: ## Create QCOW2 snapshot (usage: make snapshot NAME=snapshot-name)
	@if [ -z "$(NAME)" ]; then \
		echo "$(RED)ERROR: NAME required. Usage: make snapshot NAME=my-snapshot$(RESET)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Creating snapshot: $(NAME)$(RESET)"
	@bash $(SCRIPTS_DIR)/manage-snapshots.sh create "$(NAME)"

snapshot-list: ## List all snapshots
	@bash $(SCRIPTS_DIR)/manage-snapshots.sh list

snapshot-restore: ## Restore snapshot (usage: make snapshot-restore NAME=snapshot-name)
	@if [ -z "$(NAME)" ]; then \
		echo "$(RED)ERROR: NAME required. Usage: make snapshot-restore NAME=my-snapshot$(RESET)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Restoring snapshot: $(NAME)$(RESET)"
	@bash $(SCRIPTS_DIR)/manage-snapshots.sh restore "$(NAME)"

# =============================================================================
# Podman-Specific Targets
# =============================================================================

podman-setup: ## Setup Podman environment (install if needed)
	@echo "$(BLUE)Setting up Podman environment...$(RESET)"
	@if [ "$(RUNTIME_NAME)" != "podman" ]; then \
		echo "$(YELLOW)Current runtime is $(RUNTIME_NAME), not podman$(RESET)"; \
		echo "Install Podman: https://podman.io/getting-started/installation"; \
	else \
		echo "$(GREEN)Podman detected: $(shell podman --version)$(RESET)"; \
		command -v podman-compose >/dev/null 2>&1 || \
			(echo "Installing podman-compose..." && pip3 install podman-compose); \
	fi

podman-test: ## Test with Podman specifically
	@echo "$(BLUE)Testing with Podman...$(RESET)"
	@CONTAINER_RUNTIME=podman $(MAKE) up

# =============================================================================
# Installation
# =============================================================================

install-deps: ## Install development dependencies
	@echo "$(BLUE)Installing development dependencies...$(RESET)"
	@echo "Platform: $(PLATFORM)"
	@case "$(PLATFORM)" in \
		linux) \
			echo "Installing Linux dependencies..."; \
			sudo apt-get update || true; \
			sudo apt-get install -y shellcheck yamllint python3-pip hadolint || true; \
			;; \
		macos) \
			echo "Installing macOS dependencies..."; \
			brew install shellcheck yamllint hadolint || true; \
			;; \
		*) \
			echo "$(YELLOW)Manual installation required for $(PLATFORM)$(RESET)"; \
			echo "Required: shellcheck, yamllint, hadolint"; \
			;; \
	esac
	@pip3 install --user black flake8 pylint mypy mkdocs-material || true

install-runtime: ## Install container runtime (prompts for choice)
	@echo "$(BOLD)Container Runtime Installation$(RESET)"
	@echo "Choose runtime:"
	@echo "  1) Docker"
	@echo "  2) Podman"
	@read -p "Enter choice [1-2]: " choice; \
	case $$choice in \
		1) echo "Visit: https://docs.docker.com/get-docker/"; ;; \
		2) echo "Visit: https://podman.io/getting-started/installation"; ;; \
		*) echo "Invalid choice"; ;; \
	esac

# =============================================================================
# Cleanup
# =============================================================================

clean: ## Clean build artifacts and temporary files
	@echo "$(YELLOW)Cleaning build artifacts...$(RESET)"
	@rm -rf $(BUILD_DIR)
	@rm -rf $(COVERAGE_DIR)
	@rm -rf $(REPORTS_DIR)
	@find . -type f -name "*.pyc" -delete
	@find . -type d -name "__pycache__" -delete
	@echo "$(GREEN)Cleanup complete!$(RESET)"

clean-all: clean down ## Clean everything including containers
	@echo "$(YELLOW)Removing all containers and volumes...$(RESET)"
	$(COMPOSE_CMD) down -v
	@echo "$(GREEN)Complete cleanup done!$(RESET)"

# =============================================================================
# CI/CD
# =============================================================================

ci: lint test security validate ## Run full CI pipeline locally
	@echo "$(GREEN)CI pipeline complete!$(RESET)"

# =============================================================================
# Development
# =============================================================================

dev-setup: install-deps platform-check ## Setup development environment
	@echo "$(GREEN)Development environment ready!$(RESET)"
	@echo "Next steps:"
	@echo "  1. make build      # Build container image"
	@echo "  2. make up         # Start Hurd container"
	@echo "  3. make logs       # Monitor boot process"
	@echo "  4. make shell      # Access container"

# =============================================================================
# Utility Functions
# =============================================================================

.PHONY: version
version: ## Show version information
	@echo "$(BOLD)$(PROJECT_NAME) v$(VERSION)$(RESET)"
	@echo "Runtime: $(RUNTIME_NAME) $(shell $(CONTAINER_RUNTIME) --version 2>/dev/null | head -1 || echo 'N/A')"
	@echo "Platform: $(PLATFORM) ($(UNAME_M))"
	@echo "KVM: $(KVM_AVAILABLE)"
