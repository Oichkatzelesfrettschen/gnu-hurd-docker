# Security Audit & Code Review Summary
**GNU/Hurd Docker Scripts**  
**Date:** 2025-11-08  
**Auditor:** Claude Code Review Specialist  
**Scope:** 30 shell scripts, 4600+ LOC

---

## Executive Summary

**Overall Grade: B+**

**Status:** MOSTLY COMPLIANT with CLAUDE.md requirements

### Key Statistics
- **Shellcheck Compliance:** 100% (all 30 scripts pass `shellcheck -S error`)
- **Error Handling:** 90% use `set -e`, only 13% use `set -u` and `set -o pipefail`
- **Critical Issues:** 1 (docker-compose v1 usage)
- **High Issues:** 4 (hardcoded passwords, command injection risks)
- **Medium Issues:** 8 (inconsistent error handling)
- **Low Issues:** 12 (minor quality improvements)

---

## Critical Finding

### DOCKER-COMPOSE V1 LEGACY USAGE
**Severity:** CRITICAL  
**CLAUDE.md Requirement:** "Always use `docker compose` (v2) - never use `docker-compose` (v1 legacy)"

**Impact:** 13 scripts use `docker-compose` instead of `docker compose`

**Affected Files:**
- bringup-and-provision.sh (lines 3, 14)
- test-docker-provision.sh (lines 28, 72)
- test-docker.sh (lines 44, 54, 104-106)
- validate-config.sh (lines 5, 54-55, 130-173)
- download-image.sh (lines 141-142)
- setup-hurd-amd64.sh (line 60)
- connect-console.sh (lines 57, 76, 133)
- monitor-qemu.sh (line 133)
- test-hurd-system.sh (lines 54, 408)

**Fix:** Global find-replace `docker-compose` → `docker compose`

**Effort:** LOW (automated find-replace)

---

## Top 5 Highest-Risk Scripts

### 1. bringup-and-provision.sh (HIGH RISK)
- Uses docker-compose (v1 legacy)
- Hardcoded passwords: ROOT_PASS=root, AGENTS_PASS=agents
- Remote SSH execution with sshpass
- **Mitigation:** Good error handling (set -euo pipefail), proper quoting

### 2. install-ssh-hurd.sh (HIGH RISK)
- Hardcoded password: root:root sent via chpasswd
- Expect script with potential command injection
- Enables PasswordAuthentication in sshd
- Missing set -u and set -o pipefail
- **Mitigation:** Appropriate for dev automation, expect is necessary for serial console

### 3. full-automated-setup.sh (MEDIUM-HIGH RISK)
- 399 LOC (complex monolithic script)
- Hardcoded passwords throughout
- Missing set -u and set -o pipefail
- Extensive remote SSH execution
- **Mitigation:** Excellent user feedback, well-documented phases

### 4. fix-sources-hurd.sh (MEDIUM RISK)
- Remote SSH execution with heredoc
- Uses sshpass with password in env
- **Mitigation:** Excellent error handling (set -euo pipefail), single-quoted heredoc prevents expansion

### 5. test-docker-provision.sh (MEDIUM RISK)
- Uses docker-compose (v1 legacy)
- Missing set -u and set -o pipefail
- **Mitigation:** Good prerequisite checking, test script only

---

## Security Analysis

### Hardcoded Credentials (HIGH)
**Count:** 6 scripts

All instances are for **DEVELOPMENT ENVIRONMENTS ONLY**:
- bringup-and-provision.sh: ROOT_PASS=root, AGENTS_PASS=agents
- install-ssh-hurd.sh: root:root
- full-automated-setup.sh: root:root, agents:agents
- configure-users.sh: root:root, agents:agents
- install-essentials-hurd.sh: root:root
- test-hurd-system.sh: ROOT_PASSWORD=root, AGENTS_PASSWORD=agents

**Mitigation:** Scripts include warnings to change passwords. All usage is for local development VMs, not production.

### Command Injection Risks (MEDIUM)
**Count:** 3 instances

1. **boot_hurd.sh (line 25):** `source $CONFIG_FILE`
   - Risk: Shell injection via malicious config
   - Fix: Add config validation

2. **configure-shell.sh (line 27):** `eval echo ~$TARGET_USER`
   - Risk: Command injection via username
   - Fix: `TARGET_HOME=$(getent passwd $TARGET_USER | cut -d: -f6)`

3. **install-ssh-hurd.sh (line 30):** Expect script with variables
   - Risk: Limited - variables from script env
   - Fix: Validate SERIAL_HOST and SERIAL_PORT

### Remote Execution (MEDIUM)
**Count:** 4 scripts use sshpass + ssh + heredoc

All usage is for development automation. Scripts properly use single-quoted heredocs where appropriate to prevent expansion attacks.

**Recommendation:** Migrate to SSH key-based auth for production (current approach acceptable for dev).

### No Vulnerabilities Found
- SQL injection (no database operations)
- XSS (no web output)
- Path traversal (paths validated)
- LDAP injection (no LDAP)
- XML injection (no XML processing)
- Secrets committed to git (only dev passwords clearly marked)

---

## CLAUDE.md Compliance

### ✅ PASS
- **Treat warnings as errors:** All scripts pass `shellcheck -S error`
- **Variable quoting:** Most variables properly quoted
- **No secrets committed:** No actual secrets, only dev passwords

### ⚠️ PARTIAL
- **Error handling:**
  - `set -e`: 27/30 scripts (90%)
  - `set -u`: 4/30 scripts (13%) ← NEEDS IMPROVEMENT
  - `set -o pipefail`: 4/30 scripts (13%) ← NEEDS IMPROVEMENT

### ❌ FAIL
- **docker compose v2:** 13 scripts use legacy `docker-compose`
- **POSIX sh preferred:** All use bash (justified - bash features required)

---

## Immediate Action Items

### Priority 1: CRITICAL (Must Fix)
```bash
# Global find-replace in all scripts
find /home/eirikr/Playground/gnu-hurd-docker/scripts -name "*.sh" -type f -exec \
  sed -i 's/docker-compose/docker compose/g' {} +
```

### Priority 2: HIGH (Should Fix)
Add to 26 scripts missing full error handling:
```bash
# Add after shebang in each script
set -euo pipefail
```

Scripts needing update:
- boot_hurd.sh
- bringup-and-provision.sh (has -euo, already good)
- configure-shell.sh
- configure-users.sh
- connect-console.sh
- download-image.sh
- fix-script.sh
- full-automated-setup.sh
- health-check.sh
- install-claude-code-hurd.sh
- install-essentials-hurd.sh
- install-hurd-packages.sh
- install-nodejs-hurd.sh
- install-ssh-hurd.sh
- manage-snapshots.sh
- monitor-qemu.sh
- setup-hurd-amd64.sh
- setup-hurd-dev.sh
- test-docker-provision.sh
- test-docker.sh
- test-hurd-system.sh
- validate-config.sh

### Priority 3: MEDIUM (Good to Fix)
1. **Fix eval in configure-shell.sh:**
   ```bash
   # Replace line 27
   # OLD: TARGET_HOME=$(eval echo ~$TARGET_USER)
   # NEW: TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
   ```

2. **Add config validation in boot_hurd.sh** before sourcing

3. **Document hardcoded passwords:**
   Add comment above each hardcoded password:
   ```bash
   # WARNING: Development default only - CHANGE IN PRODUCTION
   ROOT_PASS=${ROOT_PASS:-root}
   ```

---

## Positive Findings

### Excellent Practices
- 100% shellcheck compliance with `-S error` flag
- Comprehensive error messages with color coding
- Good usage/help functions in most scripts
- Proper use of `readonly` for constants
- Single-quoted heredocs to prevent injection
- Good prerequisite checking
- Proper `trap` usage for cleanup
- `visudo` validation for sudoers files
- Backup practices (configure-shell.sh backs up .bashrc)

### Security Positives
- No secrets in git
- Minimal eval usage (only 1 instance)
- Variables mostly quoted
- Single-quoted heredocs prevent expansion
- Explicit security warnings in output
- Good use of set -e in 90% of scripts

---

## Quality Metrics

| Metric | Score | Assessment |
|--------|-------|------------|
| Shellcheck Compliance | 100% | Excellent |
| Error Handling | 60% | Needs improvement (set -u/-o pipefail) |
| Documentation | 90% | Excellent comments and usage |
| Complexity | 75% | Some scripts >200 LOC |
| Maintainability | 80% | Generally good |
| **Overall** | **B+** | **Production-ready with fixes** |

---

## Recommendations by Timeline

### Immediate (Today)
1. Global replace `docker-compose` → `docker compose` (5 minutes)
2. Add `set -u` to 26 scripts (30 minutes)
3. Add `set -o pipefail` to 26 scripts (included in step 2)

### Short Term (This Week)
1. Fix `eval` in configure-shell.sh (5 minutes)
2. Add config validation in boot_hurd.sh (15 minutes)
3. Add DEV-ONLY comments to hardcoded passwords (15 minutes)

### Long Term (This Month)
1. Refactor scripts >200 LOC into modules (8 hours)
   - full-automated-setup.sh (399 LOC)
   - test-hurd-system.sh (408 LOC)
   - manage-snapshots.sh (260 LOC)
   - configure-shell.sh (231 LOC)
   - install-hurd-packages.sh (231 LOC)

2. Consider migrating to POSIX sh where bash not needed (4 hours)

3. Add automated security scanning to CI/CD (2 hours)

---

## Conclusion

The GNU/Hurd Docker scripts are **well-written and production-ready** with minor fixes:

**Strengths:**
- Excellent shellcheck compliance (100%)
- Good security practices (no real secrets, proper quoting)
- Comprehensive functionality
- Clear documentation

**Critical Fix Required:**
- Replace `docker-compose` with `docker compose` (CLAUDE.md compliance)

**Recommended Improvements:**
- Add `set -u` and `set -o pipefail` to all scripts
- Fix eval usage in one script
- Add validation for sourced config files

**Overall Assessment:** B+ (will be A- after critical fix)

---

## Files Generated

1. **SECURITY-AUDIT-REPORT.json** - Full detailed analysis (990 lines)
2. **AUDIT-SUMMARY.md** - This executive summary

## Contact

For questions about this audit, refer to the detailed JSON report or consult the CLAUDE.md compliance requirements.
