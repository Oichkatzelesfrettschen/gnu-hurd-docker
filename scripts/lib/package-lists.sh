#!/bin/bash
# lib/package-lists.sh - Categorized package arrays for Debian GNU/Hurd
#
# WHY: Eliminate duplication of package lists across install-essentials-hurd.sh,
#      install-hurd-packages.sh, and setup-hurd-dev.sh (75% overlap reduction)
# WHAT: Provides categorized package arrays (MINIMAL_PKGS, DEV_PKGS, HURD_PKGS,
#       GUI_PKGS, NETTOOLS_PKGS, COMPILERS_PKGS, LANGUAGES_PKGS, SYS_UTILS_PKGS,
#       BROWSERS_PKGS, DEBUG_PKGS, BUILD_SYSTEMS_PKGS, DOC_TOOLS_PKGS)
# HOW: Source this file and use arrays in install_packages():
#      source "$(dirname "$0")/lib/package-lists.sh"
#      install_packages "Phase Name" "${ARRAY[@]}"

# ============================================================================
# MINIMAL PACKAGES - SSH, networking, basic tools (essential for VM access)
# ============================================================================
MINIMAL_PKGS="
    openssh-server
    openssh-client
    curl
    wget
    netcat-openbsd
    vim
    nano
    git
    ca-certificates
"

# ============================================================================
# CORE NETWORKING TOOLS
# ============================================================================
NETTOOLS_PKGS="
    net-tools
    dnsutils
    telnet
    netcat-openbsd
    iputils-ping
    traceroute
    iproute2
    ca-certificates
    htop
    screen
    tmux
    rsync
"

# ============================================================================
# WEB BROWSERS - Text-based and GUI
# ============================================================================
BROWSERS_PKGS="
    lynx
    w3m
    links
    elinks
    firefox-esr
"

# ============================================================================
# CORE DEVELOPMENT TOOLS - Compilers, build systems, version control
# ============================================================================
DEV_PKGS="
    build-essential
    gcc
    g++
    make
    cmake
    autoconf
    automake
    libtool
    pkg-config
    flex
    bison
    texinfo
    git
    vim
    emacs-nox
    nano
    gdb
    dpkg-dev
    manpages-dev
"

# ============================================================================
# COMPILERS AND TOOLCHAINS - Additional compilers beyond GCC
# ============================================================================
COMPILERS_PKGS="
    clang
    llvm
    lld
    binutils-dev
    libelf-dev
"

# ============================================================================
# PROGRAMMING LANGUAGES - Interpreters and language-specific tools
# ============================================================================
LANGUAGES_PKGS="
    python3
    python3-pip
    python3-dev
    perl
    libperl-dev
    ruby-full
    golang
    openjdk-17-jdk
"

# ============================================================================
# MACH/HURD SPECIFIC PACKAGES - GNU Mach and Hurd development
# ============================================================================
HURD_PKGS="
    gnumach-dev
    hurd-dev
    mig
    hurd-doc
"

# ============================================================================
# DEBUGGING AND PROFILING TOOLS
# ============================================================================
DEBUG_PKGS="
    gdb
    strace
    ltrace
    sysstat
    valgrind
"

# ============================================================================
# BUILD SYSTEMS - Alternative build tools (Meson, Ninja, Scons)
# ============================================================================
BUILD_SYSTEMS_PKGS="
    ninja-build
    meson
    scons
"

# ============================================================================
# DOCUMENTATION AND ANALYSIS TOOLS
# ============================================================================
DOC_TOOLS_PKGS="
    doxygen
    graphviz
    man-db
    manpages-dev
"

# ============================================================================
# GUI/X11 PACKAGES - Desktop environment
# ============================================================================
X11_PKGS="
    xorg
    x11-xserver-utils
    xterm
    xinit
"

X11_DESKTOP_PKGS="
    xfce4
    xfce4-goodies
    xfce4-terminal
    thunar
    mousepad
"

GUI_DEV_TOOLS_PKGS="
    emacs
    geany
"

GUI_APPS_PKGS="
    firefox-esr
    gimp
"

# ============================================================================
# SYSTEM UTILITIES
# ============================================================================
SYS_UTILS_PKGS="
    curl
    wget
    zip
    unzip
    tree
    less
    htop
    screen
    tmux
    rsync
    ca-certificates
"

# ============================================================================
# ENTROPY DAEMON (Hurd-specific, for SSH entropy)
# ============================================================================
ENTROPY_PKGS="
    random-egd
"

# ============================================================================
# UTILITY: Convert package strings to arrays for processing
# Usage: pkglist_to_array "$PACKAGE_STRING"
# Sets global variable: PKGS_ARRAY
# Note: Uses eval to convert whitespace-separated strings to space-separated values
# ============================================================================
pkglist_to_array() {
    # This function converts whitespace-separated strings to variables
    # Usage in functions: eval "PKGS_ARRAY=\"$1\""
    # Then reference as: $PKGS_ARRAY
    eval "PKGS_ARRAY=\"$1\""
}

# Export for subshells if needed (optional)
export MINIMAL_PKGS NETTOOLS_PKGS BROWSERS_PKGS DEV_PKGS COMPILERS_PKGS
export LANGUAGES_PKGS HURD_PKGS DEBUG_PKGS BUILD_SYSTEMS_PKGS DOC_TOOLS_PKGS
export X11_PKGS X11_DESKTOP_PKGS GUI_DEV_TOOLS_PKGS GUI_APPS_PKGS SYS_UTILS_PKGS
export ENTROPY_PKGS
