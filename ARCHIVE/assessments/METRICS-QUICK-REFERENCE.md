# Metrics Quick Reference Guide

**Purpose**: Fast lookup for baseline metrics and measurement commands

---

## Current Baseline (2025-11-07)

### Composite Quality Score: 79.5/100

```
Code Quality              86/100  ████████░░
Documentation             95/100  █████████░
Repository Health         79/100  ███████░░░
Professional Readiness    58/100  █████░░░░░
```

---

## Measurement Commands

### Code Quality

#### ShellCheck Analysis
```bash
# Check all shell scripts
shellcheck --format=json scripts/*.sh entrypoint.sh | \
  python3 -c "import sys, json; d=json.load(sys.stdin); \
  print(f'Total: {len(d)}'); \
  print({x.get('level'): len([i for i in d if i.get('level')==x.get('level')]) \
  for x in d})"

# Expected output: Total: 17
#                 {'error': 0, 'warning': 6, 'info': 10, 'style': 1}

# Check specific file
shellcheck -f gcc entrypoint.sh  # Easier to read
```

#### YAML Validation
```bash
# Validate docker-compose.yml
python3 -c "import yaml; yaml.safe_load(open('docker-compose.yml'))" && \
  echo "VALID" || echo "INVALID"

# Validate all YAML
for f in .github/workflows/*.yml mkdocs.yml docker-compose.yml; do
  python3 -c "import yaml; yaml.safe_load(open('$f'))" && echo "$f: OK" || echo "$f: FAIL"
done
```

#### Code Statistics
```bash
# Count lines of code by type
cloc . --quiet --csv | tail -10

# Count shell scripts and lines
find . -name "*.sh" | xargs wc -l | tail -1

# Find complexity issues (if using certain languages)
# For shell: no built-in, use McCabe-style analysis manually
```

---

### Documentation Metrics

#### Document Count
```bash
# Count markdown files
find . -name "*.md" -type f | wc -l
# Expected: 103

# Count markdown lines
find . -name "*.md" -type f | xargs wc -l | tail -1
# Expected: 54,259

# Find root-level docs
ls -1 *.md | wc -l
# Expected: 21 (mostly reference/migration)
```

#### Link Validation
```bash
# Find all markdown links
grep -rh '\[.*\](' . --include="*.md" | head -20

# Check for broken links (install: pip install markdown-link-check)
# markdown-link-check *.md docs/**/*.md

# Count valid internal links
grep -rh ](docs/ . --include="*.md" | wc -l
# Expected: 150+
```

#### README Quality
```bash
# Check primary README sections
for section in "Title" "Quick Start" "Architecture" "Troubleshooting" \
               "Contributing" "License" "Links"; do
  grep -qi "$section" README.md && echo "✓ $section" || echo "✗ $section"
done
```

---

### Repository Health

#### Commit Analysis
```bash
# Total commits
git log --oneline | wc -l
# Expected: 41

# Recent commits (last 30 days)
git log --oneline --since="30 days ago" | wc -l
# Expected: 16

# Conventional commits (last 30)
git log --oneline -30 | grep -E '^[a-f0-9]+ (feat|fix|docs|ci|chore|test|perf|refactor):' | wc -l
# Expected: 12 (40%)

# Commit velocity
git log --oneline --since="7 days ago" | wc -l  # Daily trend
```

#### Branch Status
```bash
# Check branches
git branch -a

# Show graph
git log --graph --oneline -10

# Check for unmerged branches
git branch --no-merged

# Check upstream
git status
```

#### CI/CD Status
```bash
# List workflows
ls -1 .github/workflows/*.yml
# Expected: 8 workflows

# Check workflow syntax
for f in .github/workflows/*.yml; do
  python3 -c "import yaml; yaml.safe_load(open('$f'))" && echo "$f: OK"
done

# View recent workflow runs (requires gh CLI)
gh run list --limit 10
gh run view [RUN_ID]
```

---

### Professional Readiness

#### Community Files Check
```bash
# Check all community files
for file in CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md LICENSE \
            .github/ISSUE_TEMPLATE/*.yml .github/PULL_REQUEST_TEMPLATE.md \
            .github/dependabot.yml; do
  [ -f "$file" ] && echo "✓ $file" || echo "✗ $file"
done

# Count present files
ls CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md LICENSE 2>/dev/null | wc -l
# Expected: 1 (just LICENSE)
```

#### Security Features
```bash
# Check for hardcoded secrets (requires truffleHog or similar)
# trufflehog filesystem . --only-verified

# Check license headers
grep -r "MIT License" . --include="*.sh" | wc -l
# Expected: 0 (not yet added)

# Verify no credentials in .env
[ -f .env ] && grep -E "password|secret|token" .env && echo "WARNING: Secrets found"
```

---

### Performance Metrics

#### Build Time
```bash
# Measure Docker build time
time docker-compose build 2>&1 | tail -1
# Record result, run 10 times to get mean ± stddev

# Measure cold build (remove images first)
docker system prune -a
time docker-compose build

# Measure incremental build
touch Dockerfile  # Invalidate cache
time docker-compose build --no-cache=false
```

#### Startup Time
```bash
# Measure container startup to SSH ready
TIME_START=$(date +%s%N)
docker-compose up -d
docker-compose logs -f | grep -m 1 "SSH ready" # Or similar marker
TIME_END=$(date +%s%N)
echo "Startup time: $(( (TIME_END - TIME_START) / 1000000 )) ms"

# Or use timeout
timeout 600 docker-compose logs -f 2>&1 | \
  tee /tmp/startup.log | \
  grep -m 1 "listening on port 2222"
```

#### Resource Usage
```bash
# Container memory usage (while running)
docker stats hurd-x86_64-qemu --no-stream

# Image size
docker images | grep hurd
# Get size in IMAGE column

# Disk image size
ls -lh debian-hurd-amd64.qcow2
# Expected: 4-10 GB
```

---

## Tracking Progress

### Monthly Measurement Checklist

```bash
# 1. Code Quality
shellcheck --format=json scripts/*.sh | python3 ... [record issue count]

# 2. Documentation
find . -name "*.md" | wc -l [record file count]
find . -name "*.md" | xargs wc -l | tail -1 [record line count]

# 3. Repository
git log --oneline | wc -l [record commit count]
git log --oneline -30 | grep '^[a-f0-9]* (feat|fix|docs|..):' | wc -l [record % conventional]

# 4. Professional
ls CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md 2>/dev/null | wc -l [record count]

# 5. Performance
time docker-compose build [record build time]
```

### Quick Dashboard View

```bash
#!/bin/bash
echo "GNU/HURD DOCKER - QUALITY DASHBOARD"
echo "===================================="
echo ""
echo "Code Quality:"
echo "  ShellCheck issues: $(shellcheck --format=json scripts/*.sh 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 'unknown')"
echo "  YAML valid: $(python3 -c 'import yaml; yaml.safe_load(open(\"docker-compose.yml\")); print(\"✓\")' 2>/dev/null || echo '✗')"
echo ""
echo "Documentation:"
echo "  Markdown files: $(find . -name "*.md" -type f | wc -l)"
echo "  Total lines: $(find . -name "*.md" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')"
echo ""
echo "Repository:"
echo "  Commits: $(git log --oneline | wc -l)"
echo "  Recent (30d): $(git log --oneline --since='30 days ago' | wc -l)"
echo "  Workflows: $(ls .github/workflows/*.yml 2>/dev/null | wc -l)"
echo ""
echo "Community:"
echo "  CONTRIBUTING.md: $([ -f CONTRIBUTING.md ] && echo '✓' || echo '✗')"
echo "  SECURITY.md: $([ -f SECURITY.md ] && echo '✓' || echo '✗')"
echo "  Files (1/8): $(ls CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md 2>/dev/null | wc -l)"
```

---

## Target Metrics

### 30-Day Improvement Targets

| Metric | Baseline | Target | Status |
|--------|----------|--------|--------|
| Composite Score | 79.5 | 84 | ░░░░░░░░░░ |
| ShellCheck Issues | 17 | <10 | ░░░░░░░░░░ |
| Conventional Commits | 40% | 70% | ░░░░░░░░░░ |
| Community Files | 1/8 | 6/8 | ░░░░░░░░░░ |
| Documentation | 95/100 | 97/100 | ░░░░░░░░░░ |

### 90-Day Improvement Targets

| Metric | Baseline | Target | Status |
|--------|----------|--------|--------|
| Composite Score | 79.5 | 88 | ░░░░░░░░░░ |
| ShellCheck Issues | 17 | 0 | ░░░░░░░░░░ |
| Conventional Commits | 40% | 90% | ░░░░░░░░░░ |
| Community Files | 1/8 | 8/8 | ░░░░░░░░░░ |
| Code Quality | 86/100 | 95/100 | ░░░░░░░░░░ |

---

## Common Measurement Patterns

### Pattern 1: Weekly Health Check (5 minutes)

```bash
#!/bin/bash
echo "Weekly Health Check - $(date +%Y-%m-%d)"
echo ""
echo "Code Quality:"
shellcheck -f gcc entrypoint.sh 2>&1 | tail -1 || echo "  OK"

echo "Documentation:"
echo "  Files: $(find . -name "*.md" | wc -l)"

echo "Repository:"
echo "  Week commits: $(git log --oneline --since='7 days ago' | wc -l)"

echo "CI/CD:"
gh run list --limit 1 | tail -1
```

### Pattern 2: Monthly Deep Dive (30 minutes)

See: MEASUREMENT-TRACKING-TEMPLATE.md

### Pattern 3: Quarterly Review (2 hours)

1. Run monthly tracking template
2. Calculate 3-month trend (mean, variance, correlation)
3. Compare to targets
4. Identify blockers
5. Plan next quarter improvements

---

## Interpretation Guide

### ShellCheck Issues

- **Error (0)**: Fatal issues, code won't run → FIX IMMEDIATELY
- **Warning (6)**: Code works but has issues → FIX BEFORE RELEASE
- **Info (10)**: Style/best practice → FIX WHEN CONVENIENT
- **Style (1)**: Formatting → LOW PRIORITY

**Current**: All pass (0 errors) - code is functional

### Code Quality Score (86/100)

- **90-100**: Excellent (production-ready)
- **80-89**: Good (ship with caution, review)
- **70-79**: Acceptable (needs fixes)
- **<70**: Poor (requires remediation)

**Current**: Good - production-ready but improvements recommended

### Conventional Commits (40%)

- **>80%**: Excellent discipline
- **>70%**: Good discipline
- **>50%**: Acceptable
- **<50%**: Needs enforcement

**Current**: Below standard - enforce commitlint in CI

### Community Files (1/8)

- **7-8/8**: Professional-grade
- **5-6/8**: Good governance
- **3-4/8**: Minimal governance
- **<3/8**: Needs urgent attention

**Current**: CRITICAL GAP - create CONTRIBUTING.md and SECURITY.md

---

## Resources

### Tools Used

- `shellcheck`: Shell script linting
- `python3 yaml`: YAML validation
- `git log`: Commit analysis
- `docker stats`: Container monitoring
- `cloc`: Code counting
- `gh`: GitHub CLI for workflow status

### Installation

```bash
# Ubuntu/Debian
sudo apt-get install shellcheck git

# Python packages
pip install pyyaml

# GitHub CLI
curl -fsSLo- https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
  sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
```

### Further Reading

- BASELINE-METRICS.md: Comprehensive baseline report
- MEASUREMENT-TRACKING-TEMPLATE.md: Monthly tracking template
- METRICS-SUMMARY.txt: Executive summary

---

**Last Updated**: 2025-11-07
**Baseline Commit**: 4684104
**Review Frequency**: Monthly
