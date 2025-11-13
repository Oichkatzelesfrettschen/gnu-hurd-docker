# Baseline Metrics Summary

**Analysis Date:** 2025-11-08
**Directory:** /home/eirikr/Playground/gnu-hurd-docker/scripts
**Full Report:** BASELINE-METRICS.json (40KB)

## Executive Summary

Analyzed **27 shell scripts** totaling **4,742 lines of code** with **87 functions** and an average cyclomatic complexity of **22.7**.

### Key Findings

1. **Code Distribution**
   - Code: 3,476 lines (73.3%)
   - Comments: 525 lines (11.1%)
   - Blank: 741 lines (15.6%)

2. **Quality Indicators**
   - 92.6% use `set -e` for error handling (25/27)
   - 100% have documentation headers (27/27)
   - Only 3.7% use trap handlers (1/27) - **IMPROVEMENT NEEDED**

3. **Anti-Patterns Detected**
   - 3 oversized scripts (>300 LOC)
   - 11 scripts with low comment ratio (<10%)
   - 1 script with extremely high complexity (>50)
   - 21 scripts with deep nesting (>3 levels)

4. **Test Coverage**
   - Only 11.1% test coverage (3/27 scripts)
   - Test scripts: test-docker-provision.sh, test-docker.sh, test-hurd-system.sh

## Critical Issues Requiring Immediate Attention

### 1. test-hurd-system.sh (CRITICAL PRIORITY)
- **Complexity:** 53 (highest in codebase)
- **LOC:** 418 (largest script)
- **Functions:** 13
- **Issue:** Extremely high cyclomatic complexity
- **Recommendation:** Break into smaller functions, extract logic into separate scripts or convert to Python

### 2. install-essentials-hurd.sh (HIGH PRIORITY)
- **Complexity:** 44
- **LOC:** 310
- **Maintainability Score:** 0.34
- **Recommendation:** Split into multiple modules or convert to Python

### 3. full-automated-setup.sh (HIGH PRIORITY)
- **Complexity:** 34
- **LOC:** 399
- **Maintainability Score:** 0.42
- **Recommendation:** Split into multiple modules, improve documentation

## Refactoring Priority Matrix

### Priority 1: Complexity Reduction
1. test-hurd-system.sh (complexity: 53)
2. install-essentials-hurd.sh (complexity: 44)
3. full-automated-setup.sh (complexity: 34)

### Priority 2: Size Reduction
1. test-hurd-system.sh (418 LOC)
2. full-automated-setup.sh (399 LOC)
3. install-essentials-hurd.sh (310 LOC)

### Priority 3: Maintainability Improvement
**Scripts with maintainability score < 0.5 and complexity > 20:**
- connect-console.sh (score: 0.27)
- install-essentials-hurd.sh (score: 0.34)
- configure-shell.sh (score: 0.42)
- full-automated-setup.sh (score: 0.42)
- install-claude-code-hurd.sh (score: 0.43)
- configure-users.sh (score: 0.44)

### Priority 4: Error Handling
**2 scripts missing `set -e`:**
- Need to add proper error handling to scripts without set -e

### Priority 5: Trap Handlers
**26 scripts without trap handlers:**
- Consider adding cleanup traps for production scripts

## Most Maintainable Scripts (Examples to Follow)

1. **bringup-and-provision.sh** (score: 2.922, 20.5% comments)
2. **boot_hurd.sh** (score: 1.488, 17.9% comments)
3. **fix-sources-hurd.sh** (score: 1.103, 23.2% comments)

## Dependency Analysis

### Most Common External Commands
1. echo (100% - 27 scripts)
2. grep (63.0% - 17 scripts)
3. apt, cat, docker (48.1% - 13 scripts each)
4. mkdir (40.7% - 11 scripts)
5. curl, ssh (37.0% - 10 scripts each)

### High Coupling Risk
- Docker used in 13 scripts (48.1%)
- APT package manager in 13 scripts (48.1%)
- SSH in 10 scripts (37.0%)

## Recommendations

### Short-term (1-2 weeks)
1. Refactor test-hurd-system.sh - break into modules
2. Add trap handlers to critical scripts (cleanup, error recovery)
3. Improve comments in 11 scripts with <10% ratio
4. Add missing `set -e` to 2 scripts

### Medium-term (1 month)
1. Split oversized scripts (>300 LOC) into modules
2. Extract common functions into shared library
3. Convert complex scripts to Python where appropriate
4. Increase test coverage from 11% to 50%

### Long-term (2-3 months)
1. Establish coding standards (max complexity: 30, max LOC: 200)
2. Add linting to CI/CD (shellcheck with complexity checks)
3. Create comprehensive test suite
4. Document architectural patterns

## Metrics for Success

### Baseline (Current)
- Average complexity: 22.7
- Average LOC/script: 175.6
- Comment ratio: 11.1%
- Test coverage: 11.1%
- Scripts with trap: 3.7%

### Target (3 months)
- Average complexity: <20
- Average LOC/script: <150
- Comment ratio: >15%
- Test coverage: >50%
- Scripts with trap: >50%

## Measurement Validation

### Methodology
- Cyclomatic complexity: count of if, elif, for, while, case, &&, ||, functions
- Maintainability score: (comment_ratio * 100) / complexity
- Nesting depth: indentation levels / 2
- Dependencies: unique external commands via regex

### Assumptions
- Complexity estimate is conservative (may be higher in practice)
- Comment ratio includes all lines starting with #
- Function count includes both `function name()` and `name()` styles

### Confidence Level
- High confidence in LOC, comment counts (directly measured)
- Medium confidence in complexity (heuristic-based)
- Low confidence in nesting depth (indentation-based approximation)

## Next Steps

1. Review BASELINE-METRICS.json for per-script details
2. Prioritize refactoring based on complexity/size rankings
3. Establish continuous monitoring (re-run analysis monthly)
4. Track improvements against baseline metrics
5. Update this summary after major refactoring efforts

---

**Files Generated:**
- /home/eirikr/Playground/gnu-hurd-docker/scripts/BASELINE-METRICS.json (40KB, full data)
- /home/eirikr/Playground/gnu-hurd-docker/scripts/BASELINE-SUMMARY.md (this file)

**Analysis Tool:** Python 3.13.7 with custom complexity analyzer
**Analysis Runtime:** <5 seconds
**Data Points Collected:** 27 scripts, 87 functions, 15 dependency types
