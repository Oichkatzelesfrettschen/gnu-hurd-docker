# Build Directory

This directory contains build artifacts and compiled outputs.

## Contents

- Docker image build artifacts
- Compiled binaries
- Package build files
- Temporary build files

## Notes

- This directory is gitignored (see `.gitignore`)
- Build artifacts are regenerated as needed
- Clean builds: `rm -rf build/*`
- For CI/CD builds, see `.github/workflows/`

## Build Process

Refer to:
- `docs/05-CI-CD/image-building.md` for Docker image builds
- `PKGBUILD` for Arch Linux package building
- `.github/workflows/build-x86_64.yml` for automated builds
