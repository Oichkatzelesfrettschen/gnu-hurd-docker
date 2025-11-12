#!/usr/bin/env bash
# Script Complexity Analyzer
# WHY: Establish quantitative baselines for script quality
# WHAT: Measures LOC, complexity, dependencies, documentation
# HOW: Parses scripts and counts various metrics

set -euo pipefail

SCRIPTS_DIR="/home/eirikr/Playground/gnu-hurd-docker/scripts"

# Analyze a single script
analyze_script() {
    script="$1"
    basename_script=$(basename "$script")

    # Basic counts
    total_lines=$(wc -l < "$script")
    code_lines=$(grep -v '^\s*#' "$script" | grep -v '^\s*$' | wc -l)
    comment_lines=$(grep '^\s*#' "$script" | wc -l)
    blank_lines=$(grep '^\s*$' "$script" | wc -l)

    # Function count
    function_count=$(grep -E '^\s*[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)' "$script" | wc -l)

    # Complexity indicators
    if_count=$(grep -E '\s*if\s+' "$script" | wc -l)
    for_count=$(grep -E '\s*for\s+' "$script" | wc -l)
    while_count=$(grep -E '\s*while\s+' "$script" | wc -l)
    case_count=$(grep -E '\s*case\s+' "$script" | wc -l)

    # Approximate cyclomatic complexity (1 + decision points)
    complexity=$((1 + if_count + for_count + while_count + case_count))

    # Error handling
    exit_count=$(grep -E '\s*exit\s+[0-9]' "$script" | wc -l)
    set_e=$(grep -E '^\s*set\s+.*e' "$script" | wc -l)

    # External dependencies (commands called)
    # Extract commands that look like external tools
    dependencies=$(grep -oE '\b(apt|apt-get|dpkg|systemctl|qemu|docker|git|wget|curl|ssh|scp|tar|gzip|xz|mkdir|chmod|chown|cp|mv|rm|cat|grep|sed|awk|cut|sort|uniq|wc|find|which|ping|nc|socat|expect|timeout|truncate)\b' "$script" | sort -u | tr '\n' ',' | sed 's/,$//')
    dep_count=$(echo "$dependencies" | tr ',' '\n' | grep -v '^$' | wc -l)

    # Documentation metrics
    if [ $total_lines -gt 0 ]; then
        comment_ratio=$(awk "BEGIN {printf \"%.3f\", $comment_lines / $total_lines}")
    else
        comment_ratio="0.000"
    fi

    has_header=$(head -20 "$script" | grep -E '^\s*#\s*(WHY|WHAT|HOW|Description|Purpose)' > /dev/null && echo "yes" || echo "no")

    # Find longest function
    max_function_lines=0
    if [ $function_count -gt 0 ]; then
        # This is approximate - just find largest block between function definition and next function or EOF
        awk '/^[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)/ {
            if (start > 0) {
                len = NR - start
                if (len > max) max = len
            }
            start = NR
        }
        END {
            if (start > 0) {
                len = NR - start
                if (len > max) max = len
            }
            print max
        }' max=0 start=0 "$script" > /tmp/maxfunc.tmp
        max_function_lines=$(cat /tmp/maxfunc.tmp)
    fi

    # Nesting depth (approximate by counting indentation)
    max_indent=$(awk '{
        indent = match($0, /[^ \t]/)
        if (indent > 0 && indent > max) max = indent
    }
    END {print int(max/2)}' max=0 "$script")

    # Global variable assignments (approximate)
    global_vars=$(grep -E '^\s*[A-Z_][A-Z0-9_]*=' "$script" | wc -l)

    # Maintainability rating
    if [ $total_lines -gt 400 ] || [ $complexity -gt 100 ] || [ $max_function_lines -gt 100 ]; then
        rating="poor"
    elif [ $total_lines -gt 200 ] || [ $complexity -gt 50 ] || [ $max_function_lines -gt 50 ]; then
        rating="fair"
    else
        rating="good"
    fi

    # Output JSON object
    cat <<EOF
{
  "script": "$basename_script",
  "loc": $total_lines,
  "code_lines": $code_lines,
  "comment_lines": $comment_lines,
  "blank_lines": $blank_lines,
  "functions": $function_count,
  "complexity_score": $complexity,
  "if_statements": $if_count,
  "loops": $((for_count + while_count)),
  "case_statements": $case_count,
  "exit_points": $exit_count,
  "has_set_e": $([ $set_e -gt 0 ] && echo "true" || echo "false"),
  "dependencies": "$dependencies",
  "dependency_count": $dep_count,
  "comment_ratio": $comment_ratio,
  "has_header": "$has_header",
  "max_function_lines": $max_function_lines,
  "max_nesting_depth": $max_indent,
  "global_variables": $global_vars,
  "maintainability_rating": "$rating"
}
EOF
}

# Main analysis
echo "{"
echo "  \"analysis_timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
echo "  \"scripts_analyzed\": $(ls "$SCRIPTS_DIR"/*.sh 2>/dev/null | wc -l),"
echo '  "per_script_metrics": ['

first=true
for script in "$SCRIPTS_DIR"/*.sh; do
    if [ -f "$script" ]; then
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        analyze_script "$script"
    fi
done

echo ""
echo "  ]"
echo "}"
