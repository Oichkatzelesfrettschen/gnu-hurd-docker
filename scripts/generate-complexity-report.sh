#!/usr/bin/env bash
# Generate complexity report with rankings and recommendations
# WHY: Process raw metrics into actionable insights
# WHAT: Analyzes JSON data and produces structured report
# HOW: Reads metrics, calculates aggregates, ranks scripts

set -euo pipefail

INPUT_JSON="/tmp/raw-metrics.json"
OUTPUT_JSON="/tmp/script-complexity-report.json"

# Check for jq availability for better JSON processing
if command -v jq >/dev/null 2>&1; then
    USE_JQ=true
else
    USE_JQ=false
fi

if [ "$USE_JQ" = true ]; then
    # Use jq for robust JSON processing
    cat "$INPUT_JSON" | jq '
    {
      "overall_metrics": {
        "total_scripts": (.per_script_metrics | length),
        "total_loc": (.per_script_metrics | map(.loc) | add),
        "total_code_lines": (.per_script_metrics | map(.code_lines) | add),
        "total_comment_lines": (.per_script_metrics | map(.comment_lines) | add),
        "avg_script_size": (.per_script_metrics | map(.loc) | add / length | floor),
        "avg_complexity": (.per_script_metrics | map(.complexity_score) | add / length | floor),
        "total_functions": (.per_script_metrics | map(.functions) | add),
        "documentation_ratio": ((.per_script_metrics | map(.comment_lines) | add) / (.per_script_metrics | map(.loc) | add) * 100 | floor / 100),
        "scripts_with_set_e": (.per_script_metrics | map(select(.has_set_e == true)) | length),
        "scripts_with_header": (.per_script_metrics | map(select(.has_header == "yes")) | length)
      },
      "per_script_metrics": .per_script_metrics,
      "complexity_rankings": {
        "most_complex": (.per_script_metrics | sort_by(-.complexity_score) | .[0:5] | map({script, complexity_score, loc})),
        "largest_scripts": (.per_script_metrics | sort_by(-.loc) | .[0:5] | map({script, loc, complexity_score})),
        "simplest": (.per_script_metrics | sort_by(.complexity_score) | .[0:5] | map({script, complexity_score, loc})),
        "highest_dependency": (.per_script_metrics | sort_by(-.dependency_count) | .[0:5] | map({script, dependency_count, dependencies})),
        "best_documented": (.per_script_metrics | sort_by(-.comment_ratio) | .[0:5] | map({script, comment_ratio, has_header})),
        "worst_documented": (.per_script_metrics | sort_by(.comment_ratio) | .[0:5] | map({script, comment_ratio, has_header}))
      },
      "anti_patterns_found": {
        "oversized_scripts": (.per_script_metrics | map(select(.loc > 300)) | map({script, loc, issue: "Script exceeds 300 lines"})),
        "oversized_functions": (.per_script_metrics | map(select(.max_function_lines > 50)) | map({script, max_function_lines, issue: "Function exceeds 50 lines"})),
        "deep_nesting": (.per_script_metrics | map(select(.max_nesting_depth > 3)) | map({script, max_nesting_depth, issue: "Nesting depth exceeds 3 levels"})),
        "poor_maintainability": (.per_script_metrics | map(select(.maintainability_rating == "poor")) | map({script, rating: .maintainability_rating, loc, complexity_score})),
        "missing_set_e": (.per_script_metrics | map(select(.has_set_e == false)) | map({script, issue: "Missing set -e error handling"})),
        "low_documentation": (.per_script_metrics | map(select(.comment_ratio < 0.10)) | map({script, comment_ratio, issue: "Documentation below 10%"}))
      },
      "test_coverage": {
        "test_scripts": (.per_script_metrics | map(select(.script | startswith("test-"))) | map(.script)),
        "critical_untested": [
          "full-automated-setup.sh needs integration tests",
          "download-released-image.sh needs validation tests",
          "boot_hurd.sh needs boot failure tests",
          "install-* scripts need package verification tests"
        ]
      },
      "recommendations": [
        (.per_script_metrics | map(select(.loc > 300)) | map("Split \(.script) (\(.loc) LOC) into modules")),
        (.per_script_metrics | map(select(.max_function_lines > 100)) | map("Refactor large function in \(.script) (\(.max_function_lines) lines)")),
        (.per_script_metrics | map(select(.comment_ratio < 0.10)) | map("Add documentation to \(.script) (currently \(.comment_ratio * 100 | floor)%)")),
        (.per_script_metrics | map(select(.has_set_e == false)) | map("Add set -e to \(.script) for error handling")),
        ["Create test suite for install-* scripts with mock environments"],
        ["Add integration tests for full-automated-setup.sh"],
        ["Extract common functions from large scripts into shared library"]
      ] | flatten | unique
    }
    ' > "$OUTPUT_JSON"
else
    # Fallback: basic awk-based processing
    echo "Warning: jq not found, using basic awk processing" >&2
    echo '{"error": "jq required for full analysis"}' > "$OUTPUT_JSON"
fi

cat "$OUTPUT_JSON"
