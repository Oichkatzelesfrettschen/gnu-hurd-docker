#!/usr/bin/env python3
"""Validate a runtime evidence capture against its schema and its own files.

The schema constrains the document.  It cannot see whether the streams a probe
advertises exist, whether their recorded digests describe the bytes on disk, or
whether a capture published as redacted still carries a machine-local path.
Those are the properties that make a capture citable, so they are checked here
and the schema check is one of four rather than the whole gate.

A digest mismatch is the signature of redaction that ran after hashing: the
sanitized file no longer matches the digest taken from the unsanitized stream.

Exit status: 0 every capture passes, 1 a capture fails, 2 the invocation is
unusable (no captures named, or jsonschema absent).
"""

import argparse
import hashlib
import json
import os
import re
import sys

SCHEMA = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "schemas", "runtime-evidence-v2.schema.json")

# A published capture carries no absolute home path, no repository path, and no
# machine hostname.  The scratchpad form appears separately because a capture
# driven by a temporary override names that file in reproduce.command.
LOCAL_PATH = re.compile(r"/home/[^/\"\s]+|/tmp/claude-[0-9]+|/root/[^/\"\s]+")

# A credential-shaped key, anchored to a token boundary so BYPASS_MODE and
# COMPASS_CONFIG stay settings rather than secrets.  The key is matched on its
# own and tested separately, because embedding the boundary in an assignment
# pattern lets the trailing "=" defeat the end anchor.
SECRET_KEY = re.compile(
    r"(?:^|_)(?:PASSWORD|PASSWD|PASS|TOKEN|SECRET|CREDENTIAL|CREDENTIALS|"
    r"AUTH|COOKIE|KEY|APIKEY)(?:_|$)", re.IGNORECASE)
ASSIGNMENT = re.compile(r"\b([A-Za-z0-9_]+)=([^\s\"',\]}]+)")


def live_secret(text):
    """Return the key of the first credential-shaped assignment whose value is
    neither the redaction token nor a placeholder, or None."""
    for match in ASSIGNMENT.finditer(text):
        key, value = match.group(1), match.group(2)
        if SECRET_KEY.search(key) and not value.startswith(("<", '"<')):
            return key
    return None


def load_schema():
    try:
        import jsonschema
    except ImportError:
        print("check-runtime-evidence: jsonschema is not installed; "
              "install python3-jsonschema", file=sys.stderr)
        raise SystemExit(2)
    with open(SCHEMA, encoding="utf-8") as fh:
        return jsonschema, json.load(fh)


def check_privacy(path):
    """Reject machine-local paths and surviving credentials anywhere under a
    capture.  This runs for every capture, superseded ones included: a
    superseded document is still published on the default branch, so marking it
    historical excuses its digests and its schema, never its disclosures."""
    failures = []
    for base, _dirs, names in os.walk(path):
        for name in names:
            target = os.path.join(base, name)
            try:
                with open(target, encoding="utf-8") as fh:
                    text = fh.read()
            except (OSError, UnicodeDecodeError):
                continue
            rel = os.path.relpath(target, path)
            found = LOCAL_PATH.search(text)
            if found:
                failures.append("%s: %s carries a machine-local path (%s)"
                                % (path, rel, found.group(0)))
            secret = live_secret(text)
            if secret:
                failures.append("%s: %s carries an unredacted credential-shaped "
                                "value (%s=...)" % (path, rel, secret))
    return failures


def check_capture(path, jsonschema, schema, require_redacted):
    """Return a list of failure strings for one capture directory, or None when
    the capture is superseded and only its privacy checks apply."""
    failures = []
    # A superseded capture is retained as history and is not a citable claim, so
    # its schema and digests are not repaired.  Recomputing its digests would
    # make a capture taken from a dirty tree with an untracked input look
    # self-consistent without making it reproducible.
    if os.path.exists(os.path.join(path, "SUPERSEDED.md")):
        print("%s: superseded; schema and digests not validated" % path)
        privacy = check_privacy(path) if require_redacted else []
        return privacy or None
    doc_path = os.path.join(path, "capture.json")
    if not os.path.exists(doc_path):
        return ["%s: no capture.json" % path]
    try:
        with open(doc_path, encoding="utf-8") as fh:
            document = json.load(fh)
    except ValueError as exc:
        return ["%s: capture.json does not decode: %s" % (path, exc)]

    validator = jsonschema.Draft202012Validator(schema)
    for error in sorted(validator.iter_errors(document), key=str):
        failures.append("%s: schema: %s at %s"
                        % (path, error.message,
                           "/".join(str(p) for p in error.absolute_path) or "<root>"))

    for name, probe in (document.get("probes") or {}).items():
        for stream in ("stdout", "stderr"):
            rel = probe.get("%s_file" % stream)
            recorded = probe.get("%s_sha256" % stream)
            if not rel:
                failures.append("%s: probe %s names no %s file" % (path, name, stream))
                continue
            # The path comes from the document under test, so it is confined
            # before it is opened.  An absolute path, a traversal, or a symlink
            # out of the capture would make this gate read arbitrary files, and
            # a directory or a device would make it crash or block.
            capture_root = os.path.realpath(path)
            joined = os.path.join(capture_root, rel)
            target = os.path.realpath(joined)
            if os.path.isabs(rel) or os.path.commonpath([capture_root, target]) != capture_root:
                failures.append("%s: probe %s names %s, which escapes the capture"
                                % (path, name, rel))
                continue
            if os.path.islink(joined):
                failures.append("%s: probe %s names %s, which is a symlink"
                                % (path, name, rel))
                continue
            if not os.path.exists(target):
                failures.append("%s: probe %s advertises %s, which is absent"
                                % (path, name, rel))
                continue
            if not os.path.isfile(target):
                failures.append("%s: probe %s names %s, which is not a regular file"
                                % (path, name, rel))
                continue
            if not recorded:
                continue
            with open(target, "rb") as fh:
                actual = hashlib.sha256(fh.read()).hexdigest()
            if actual != recorded:
                failures.append(
                    "%s: probe %s %s digest mismatch: records %s, file is %s"
                    % (path, name, stream, recorded[:16], actual[:16]))

    if require_redacted:
        failures.extend(check_privacy(path))
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("captures", nargs="*", help="capture directories")
    parser.add_argument("--require-redacted", action="store_true",
                        help="also reject machine-local paths, for published cases")
    args = parser.parse_args()
    if not args.captures:
        print("check-runtime-evidence: name at least one capture directory",
              file=sys.stderr)
        return 2

    jsonschema, schema = load_schema()
    failures = []
    validated = skipped = 0
    for path in args.captures:
        result = check_capture(path, jsonschema, schema, args.require_redacted)
        if result is None:
            skipped += 1
            continue
        validated += 1
        failures.extend(result)

    for line in failures:
        print(line)
    if failures:
        print("check-runtime-evidence: FAIL (%d finding(s) across %d capture(s))"
              % (len(failures), validated))
        return 1
    # A skipped capture is counted apart from a validated one, because reporting
    # a skip as a pass is the overstatement this gate exists to catch.
    print("check-runtime-evidence: OK (%d validated, %d superseded)"
          % (validated, skipped))
    return 0


if __name__ == "__main__":
    sys.exit(main())
