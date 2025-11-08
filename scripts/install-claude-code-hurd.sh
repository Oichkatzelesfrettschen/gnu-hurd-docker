#!/bin/bash
# Claude Code CLI Installation for Debian GNU/Hurd
# Attempts installation via native installer or npm fallback
# Version: 1.0

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
echo_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "================================================================"
echo "  Claude Code CLI Installation for Debian GNU/Hurd"
echo "================================================================"
echo ""

# Check for Node.js (required for npm method)
if ! command -v node >/dev/null 2>&1; then
    echo_error "Node.js not found!"
    echo_info "Claude Code requires Node.js 18+ for npm installation"
    echo_info "Install Node.js first with: ./scripts/install-nodejs-hurd.sh"
    echo ""
    read -p "Continue anyway and try native installer? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ============================================================================
# METHOD 1: Native Installer (Recommended)
# ============================================================================

echo_info "METHOD 1: Trying Native Installer..."
echo_warning "This may not work on GNU/Hurd (requires glibc, likely amd64)"
echo ""

read -p "Try native installer? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo_info "Downloading and running Claude Code installer..."

    # Download installer
    if curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh; then
        echo_success "Downloaded installer"

        # Make executable
        chmod +x /tmp/claude-install.sh

        # Run installer
        echo_info "Running installer (may fail on Hurd)..."
        if bash /tmp/claude-install.sh; then
            echo_success "Native installer succeeded!"

            # Verify installation
            if command -v claude >/dev/null 2>&1; then
                CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "unknown")
                echo_success "Claude Code installed: $CLAUDE_VERSION"

                echo ""
                echo_success "Installation complete!"
                echo_info "Initialize with: claude auth login"
                exit 0
            else
                echo_error "Installer succeeded but 'claude' command not found"
                echo_info "Check PATH or try npm method"
            fi
        else
            echo_error "Native installer failed (likely due to Hurd incompatibility)"
            echo_info "Falling back to npm method..."
        fi
    else
        echo_error "Failed to download installer"
        echo_info "Trying npm method..."
    fi
fi

# ============================================================================
# METHOD 2: NPM Installation
# ============================================================================

echo ""
echo_info "METHOD 2: NPM Installation..."

# Check Node.js version
if command -v node >/dev/null 2>&1; then
    NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1)
    echo_info "Node.js version: v$NODE_VERSION"

    if [ "$NODE_VERSION" -lt 18 ]; then
        echo_warning "Claude Code requires Node.js 18+, but v$NODE_VERSION found"
        echo_warning "Installation may fail. Consider upgrading Node.js"
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    echo_error "Node.js not found. Cannot use npm method"
    echo_info "Install Node.js first: ./scripts/install-nodejs-hurd.sh"
    exit 1
fi

# Configure npm for global install without sudo
echo_info "Configuring npm..."
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'

# Add to PATH if not already
if ! grep -q "npm-global" ~/.bashrc; then
    echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.bashrc
    echo_success "Added npm global bin to PATH"
fi

# Source to use new PATH immediately
export PATH=$HOME/.npm-global/bin:$PATH

echo_info "Installing Claude Code via npm..."
echo_warning "This may take several minutes..."

if npm install -g @anthropic-ai/claude-code; then
    echo_success "NPM installation succeeded!"

    # Verify
    if command -v claude >/dev/null 2>&1; then
        CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "unknown")
        echo_success "Claude Code installed: $CLAUDE_VERSION"

        echo ""
        echo "================================================================"
        echo "  Installation Complete!"
        echo "================================================================"
        echo ""
        echo_success "Claude Code CLI is installed"
        echo_info "Version: $CLAUDE_VERSION"
        echo ""
        echo_info "Next steps:"
        echo "  1. Reload PATH: source ~/.bashrc"
        echo "  2. Authenticate: claude auth login"
        echo "  3. Start using: claude"
        echo ""
        echo_info "Documentation: https://docs.claude.com/en/docs/claude-code/"
        echo ""
        exit 0
    else
        echo_error "Installation succeeded but 'claude' command not found"
        echo_info "Try: source ~/.bashrc"
        echo_info "Then: claude --version"
        exit 1
    fi
else
    echo_error "NPM installation failed"
    echo_info "This may be due to platform incompatibility with GNU/Hurd"
fi

# ============================================================================
# FAILURE - Provide Manual Instructions
# ============================================================================

echo ""
echo_error "All automated installation methods failed"
echo ""
echo_warning "Claude Code may not be compatible with GNU/Hurd i386"
echo ""
echo_info "Reasons:"
echo "  1. Native build is for glibc + amd64/arm64 (not Hurd)"
echo "  2. npm package may require platform-specific binaries"
echo "  3. GNU/Hurd is not officially supported by Claude Code"
echo ""
echo_info "Alternatives:"
echo "  1. Use Claude Code from the host machine (not inside VM)"
echo "  2. Use Claude via web interface: https://claude.ai"
echo "  3. Use Anthropic API directly with curl/python:"
echo "     https://docs.anthropic.com/en/api/"
echo ""
echo_info "Manual retry (if dependencies fixed):"
echo "  npm install -g @anthropic-ai/claude-code"
echo ""

exit 1
