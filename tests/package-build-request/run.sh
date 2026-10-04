#!/bin/bash
# Prove scripts/build-hurd-source-package.sh refuses a malformed request
# before it touches the guest.
#
# source, version, build_user, and build_parallelism each reach a guest root
# or build-user shell command as an interpolated string rather than an argv
# element, so a value outside the grammar its field describes is a command-
# injection surface rather than a cosmetic defect. Each case here supplies one
# malformed field and asserts both the refusal and that no ssh or scp ran: a
# stub that would only answer if invoked stays silent, and its silence is the
# second half of the proof.
#
# The guest round trip itself -- a real or emulated sshd answering the copied
# producer -- is not exercised here. That is a distinct, larger fixture this
# suite does not yet provide; scripts/guest/build-source-package.sh's own
# contract is covered directly in tests/package-build-producer/.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ORCHESTRATOR="$ROOT/scripts/build-hurd-source-package.sh"
WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/package-build-request-XXXXXX")"
failures=0

cleanup() { rm -rf "$WORKSPACE"; }
trap cleanup EXIT

check() {
    local description="$1" observed="$2" expected="$3"
    if [ "$observed" = "$expected" ]; then
        printf 'ok    %s\n' "$description"
    else
        failures=$((failures + 1))
        printf 'FAIL  %s (observed %s, expected %s)\n' \
            "$description" "$observed" "$expected"
    fi
}

bin="$WORKSPACE/bin"
mkdir -p "$bin"
sentinel="$WORKSPACE/ssh-was-invoked"
# A stub that would only answer if the orchestrator reached it; its absence
# after a run is the proof that validation refused before any guest contact.
for tool in ssh scp; do
    cat > "$bin/$tool" <<EOF
#!/bin/bash
touch "$sentinel"
exit 1
EOF
    chmod +x "$bin/$tool"
done

run_dir="$WORKSPACE/run"
mkdir -p "$run_dir"

drive() {
    local request_json="$1" label="$2"
    local request_path="$WORKSPACE/request-${label}.json"
    printf '%s' "$request_json" > "$request_path"
    rm -f "$sentinel"
    (
        export PATH="$bin:$PATH"
        bash "$ORCHESTRATOR" --request "$request_path" --run-dir "$run_dir" \
            >"$WORKSPACE/${label}.stdout" 2>"$WORKSPACE/${label}.stderr"
    )
    echo "$?"
}

base='{"schema_version":1,"source":"fixture","version":"1.0-1","build_user":"builder","build_parallelism":1,"local_patches":[]}'

exit_code="$(drive "$base" valid-shape)"
check "a well-formed request is not itself refused by validation" \
    "$([ "$exit_code" != "2" ] && echo not-refused || echo refused)" "not-refused"

bad_source='{"schema_version":1,"source":"fixture; rm -rf /","version":"1.0-1","build_user":"builder","build_parallelism":1,"local_patches":[]}'
exit_code="$(drive "$bad_source" bad-source)"
check "a source name outside the package grammar is refused" "$exit_code" "2"
check "a refused source name never reaches ssh or scp" \
    "$([ -f "$sentinel" ] && echo invoked || echo silent)" "silent"

bad_version='{"schema_version":1,"source":"fixture","version":"1.0'"'"'; touch pwned","build_user":"builder","build_parallelism":1,"local_patches":[]}'
exit_code="$(drive "$bad_version" bad-version)"
check "a version outside Debian version grammar is refused" "$exit_code" "2"
check "a refused version never reaches ssh or scp" \
    "$([ -f "$sentinel" ] && echo invoked || echo silent)" "silent"

bad_user='{"schema_version":1,"source":"fixture","version":"1.0-1","build_user":"root; id","build_parallelism":1,"local_patches":[]}'
exit_code="$(drive "$bad_user" bad-user)"
check "a build_user outside account-name grammar is refused" "$exit_code" "2"
check "a refused build_user never reaches ssh or scp" \
    "$([ -f "$sentinel" ] && echo invoked || echo silent)" "silent"

bad_parallelism='{"schema_version":1,"source":"fixture","version":"1.0-1","build_user":"builder","build_parallelism":"1 && rm -rf /","local_patches":[]}'
exit_code="$(drive "$bad_parallelism" bad-parallelism)"
check "a non-integer build_parallelism is refused" "$exit_code" "2"
check "a refused build_parallelism never reaches ssh or scp" \
    "$([ -f "$sentinel" ] && echo invoked || echo silent)" "silent"

huge_parallelism='{"schema_version":1,"source":"fixture","version":"1.0-1","build_user":"builder","build_parallelism":1000,"local_patches":[]}'
exit_code="$(drive "$huge_parallelism" huge-parallelism)"
check "a build_parallelism outside the accepted bound is refused" "$exit_code" "2"

patched='{"schema_version":1,"source":"fixture","version":"1.0-1","build_user":"builder","build_parallelism":1,"local_patches":["0001-fix.patch"]}'
exit_code="$(drive "$patched" nonempty-patches)"
check "a nonempty local_patches list is refused" "$exit_code" "2"
check "a refused patch list never reaches ssh or scp" \
    "$([ -f "$sentinel" ] && echo invoked || echo silent)" "silent"

echo ""
echo "${failures} failure(s)"
[ "$failures" -eq 0 ]
