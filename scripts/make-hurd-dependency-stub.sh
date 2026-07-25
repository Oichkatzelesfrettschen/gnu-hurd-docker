#!/usr/bin/env bash
# Build an equivs stub that satisfies a dependency the Hurd cannot provide.
#
# This is the pinch path, and it is a claim about the system rather than a fix.
# polkitd is the case it exists for: upstream polkit tracks sessions through
# logind, the Hurd has no logind and no elogind build, and mate-polkit depends on
# polkitd. On a single-user VM whose console user is the only user, the
# authority polkit would arbitrate has one answer, so a stub lets the desktop
# assemble while the mechanism stays absent.
#
# What a stub does not do is supply behavior. Anything that actually calls the
# service fails at run time, and it fails later and less legibly than an install
# that refused. Every stub therefore writes its rationale into the package
# description, so `dpkg -s` on the guest reports why it is there and what is
# missing, and the roadmap entry stays the real work.
#
# Prefer a rebuild when the source already builds for the other Hurd port:
# scripts/build-hurd-package-in-guest.sh closes a build gap without pretending.

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: make-hurd-dependency-stub.sh --provides NAME --reason TEXT [options]

  --provides NAME    dependency the stub satisfies; required
  --reason TEXT      why the Hurd cannot provide it; required, recorded in the package
  --version VERSION  version to claim (default 999:0-hurd-stub1)
  --output DIR       where to write the .deb (default ./stubs)
  --print-control    write the control file to stdout and stop
EOF
    exit 2
}

PROVIDES=""
REASON=""
VERSION="999:0-hurd-stub1"
OUTPUT="stubs"
PRINT_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --provides) PROVIDES="${2:-}"; shift 2 ;;
        --reason) REASON="${2:-}"; shift 2 ;;
        --version) VERSION="${2:-}"; shift 2 ;;
        --output) OUTPUT="${2:-}"; shift 2 ;;
        --print-control) PRINT_ONLY=1; shift ;;
        -h|--help) usage ;;
        *) printf 'unknown option: %s\n' "$1" >&2; usage ;;
    esac
done

[ -n "$PROVIDES" ] || { printf 'a dependency name is required\n' >&2; usage; }
[ -n "$REASON" ] || { printf 'a reason is required: the stub records why it exists\n' >&2; usage; }

control() {
    cat <<EOF
Section: metapackages
Priority: optional
Standards-Version: 4.6.2

Package: hurd-stub-${PROVIDES}
Version: ${VERSION}
Maintainer: gnu-hurd-docker <root@localhost>
Architecture: all
Provides: ${PROVIDES}
Description: stub satisfying ${PROVIDES} on the Hurd
 This package provides the name ${PROVIDES} and none of its behavior. It exists
 so a desktop can assemble on a port where the real package is unavailable.
 .
 Reason recorded at build time:
 ${REASON}
 .
 Anything that calls ${PROVIDES} at run time fails, and it fails later than an
 install that refused would have. Removing this stub and installing the real
 package is the outstanding work.
EOF
}

if [ "$PRINT_ONLY" -eq 1 ]; then
    control
    exit 0
fi

command -v equivs-build >/dev/null 2>&1 || {
    printf 'equivs-build is absent; install the equivs package\n' >&2
    exit 1
}

mkdir -p "$OUTPUT"
control > "${OUTPUT}/hurd-stub-${PROVIDES}.control"
(cd "$OUTPUT" && equivs-build "hurd-stub-${PROVIDES}.control")

printf 'stub built for %s in %s\n' "$PROVIDES" "$OUTPUT" >&2
printf 'install it on the guest, and keep the roadmap entry for the real port\n' >&2
