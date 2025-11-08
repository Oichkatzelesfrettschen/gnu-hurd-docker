# CI/CD Provisioned Image Workflow

## Overview

This document describes the Docker-based workflow for building fully provisioned Debian GNU/Hurd images with all development tools pre-installed.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│           Docker Host (GitHub Actions / Local)          │
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │  Provisioning Container (Debian Bookworm)      │    │
│  │                                                 │    │
│  │  ┌────────────────────────────────────────┐   │    │
│  │  │  QEMU VM (Hurd i386)                   │   │    │
│  │  │  - Serial console (telnet)             │   │    │
│  │  │  - Automated expect scripts            │   │    │
│  │  │  - Package installation                │   │    │
│  │  │  - Configuration                       │   │    │
│  │  └────────────────────────────────────────┘   │    │
│  │                                                 │    │
│  │  Result: Provisioned qcow2 image              │    │
│  └────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

## What Gets Installed

The provisioned image includes:

1. **SSH Server**
   - openssh-server
   - random-egd (entropy generator)
   - Configured for root login (root/root)

2. **Network Tools**
   - curl, wget
   - net-tools, dnsutils
   - telnet, netcat
   - ping, traceroute

3. **Web Browsers**
   - lynx (text browser)
   - w3m, links, elinks

4. **Development Tools**
   - build-essential (gcc, make, etc.)
   - git, vim
   - python3, python3-pip
   - cmake, autoconf, automake

5. **Node.js** (if available in Debian repos)
   - nodejs
   - npm

## Local Testing

### Prerequisites

- Docker with KVM support
- Base Hurd image in `images/` directory

### Build and Test

```bash
# 1. Build the provisioning Docker image
docker-compose -f docker-compose.provision.yml build

# 2. Run provisioning (takes ~10-15 minutes)
docker-compose -f docker-compose.provision.yml up

# 3. Verify the output
ls -lh images/debian-hurd-i386-80gb-provisioned.qcow2

# 4. Test the provisioned image
QEMU_DRIVE=images/debian-hurd-i386-80gb-provisioned.qcow2 \
  docker-compose up -d

# 5. SSH into the provisioned system
ssh -p 2222 root@localhost
# Password: root
```

### Manual Provisioning Script

```bash
# Run provisioning script directly
./scripts/create-provisioned-image.sh \
  images/debian-hurd-i386-80gb.qcow2 \
  images/debian-hurd-i386-80gb-provisioned.qcow2
```

## GitHub Actions Workflow

The workflow automatically:

1. **Checks out code**
2. **Enables KVM** for fast emulation
3. **Builds provisioning Docker image**
4. **Runs automated provisioning** via expect scripts
5. **Uploads provisioned image** as artifact
6. **Creates release** (on tagged commits)

### Trigger Workflow

```bash
# Push to main branch
git push origin main

# Or trigger manually
gh workflow run build-provisioned-image.yml
```

### Download Artifacts

```bash
# List recent runs
gh run list --workflow=build-provisioned-image.yml

# Download artifact from latest run
gh run download --name debian-hurd-provisioned-image
```

## Customization

### Add More Packages

Edit `scripts/create-provisioned-image.sh`:

```bash
# Add your packages here
send_command "apt-get install -y your-package-here"
```

### Modify Configuration

Add configuration commands to the expect script:

```bash
# Example: Configure git
send_command "git config --global user.name 'Hurd Builder'"
send_command "git config --global user.email 'builder@hurd.local'"
```

### Change Boot Timeout

Adjust the sleep duration after QEMU start:

```bash
# In create-provisioned-image.sh
sleep 60  # Increase if boot takes longer
```

## Troubleshooting

### Provisioning Times Out

**Symptom:** Expect script fails to connect or times out

**Solutions:**
1. Increase boot wait time in script
2. Check base image boots correctly
3. Verify KVM is enabled (`ls -la /dev/kvm`)

### QEMU Won't Start

**Symptom:** "Could not access KVM kernel module"

**Solutions:**
```bash
# Check KVM availability
ls -la /dev/kvm

# Add user to kvm group (local testing)
sudo usermod -a -G kvm $USER
newgrp kvm

# For GitHub Actions, workflow enables KVM via udev rules
```

### Packages Fail to Install

**Symptom:** apt-get returns errors

**Solutions:**
1. Check network connectivity in VM
2. Verify Debian repos are accessible
3. Try different mirror in /etc/apt/sources.list

### Image Corruption

**Symptom:** Provisioned image won't boot

**Solutions:**
```bash
# Check image integrity
qemu-img check images/debian-hurd-i386-80gb-provisioned.qcow2

# Repair if possible
qemu-img check -r all images/debian-hurd-i386-80gb-provisioned.qcow2

# Or re-run provisioning from clean base
```

## Performance

### Build Times

- **With KVM:** 10-15 minutes
- **Without KVM (TCG):** 60-90 minutes

### Image Sizes

- **Base image:** 2.4 GB actual, 80 GB virtual
- **Provisioned image:** ~3.5 GB actual, 80 GB virtual
- **Compressed:** ~2.8 GB (using qcow2 compression)

## Integration with Main Workflow

After provisioning, use the image in your main docker-compose:

```yaml
# docker-compose.override.yml
services:
  gnu-hurd-dev:
    environment:
      - QEMU_DRIVE=/opt/hurd-image/debian-hurd-i386-80gb-provisioned.qcow2
```

Now when you run `docker-compose up`, you get a fully configured system with:
- SSH accessible on port 2222
- All dev tools ready
- No manual setup required

## Next Steps

1. ✅ **Test locally**: Run provisioning on your machine
2. ✅ **Push to GitHub**: Let Actions build the image
3. ✅ **Download artifact**: Get the provisioned image
4. ✅ **Use in development**: Replace base image with provisioned one
5. ✅ **Iterate**: Add more tools as needed

## Benefits

✅ **Reproducible:** Same image every time  
✅ **Automated:** No manual configuration  
✅ **Version controlled:** Scripts in git  
✅ **CI/CD ready:** GitHub Actions integration  
✅ **Fast:** Pre-installed tools, no setup time  
✅ **Shareable:** Upload to releases for team use  

---

**Generated:** 2025-11-07  
**Repository:** gnu-hurd-docker  
**Maintainer:** Oaich
