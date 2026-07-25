#!/usr/bin/env python3
"""Calibrate the capture producer against the outputs it must survive.

The contract fixtures hand-build documents and exercise the checker, so they say
nothing about the code that writes a capture.  That gap let a redaction pass
that corrupts JSON reach a green pipeline: the checker never sees a stream the
producer mangled, because the producer was never run.

These cases import the instrument and call it directly.  Every one names an
output shape a real probe produces -- a docker inspect document, an environment
array, a resolved Compose mapping, a QEMU accelerator transcript -- and asserts
what the producer does with it.

The final case runs a whole capture against stub probes and validates the
result with the same checker CI runs, so the suite carries one positive
evidence package the producer actually generated.
"""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, relative))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cap = load("capture_runtime_evidence", "scripts/capture-runtime-evidence.py")

CASES = []


def case(name):
    def register(fn):
        CASES.append((name, fn))
        return fn
    return register


@case("a JSON secret member stays valid JSON and loses its value")
def json_secret_member():
    text = json.dumps({"VNC_PASSWORD": "hunter2", "FORCE_KVM": "1"})
    out = cap.redact_stream(text, [])
    decoded = json.loads(out)
    assert decoded["VNC_PASSWORD"] == cap.REDACTED, decoded
    assert decoded["FORCE_KVM"] == "1", decoded
    assert "hunter2" not in out


@case("a JSON environment array keeps its shape and loses the credential")
def json_env_array():
    text = json.dumps({"Config": {"Env": ["VNC_PASSWORD=hunter2", "FORCE_KVM=1"]}})
    out = cap.redact_stream(text, [])
    env = json.loads(out)["Config"]["Env"]
    assert "VNC_PASSWORD=%s" % cap.REDACTED in env, env
    assert "FORCE_KVM=1" in env, env
    assert "hunter2" not in out


@case("a YAML mapping is redacted")
def yaml_mapping():
    out = cap.redact_stream(
        "services:\n  hurd:\n    environment:\n      VNC_PASSWORD: hunter2\n", [])
    assert "hunter2" not in out
    assert cap.REDACTED in out


@case("a key that merely contains PASS or KEY is not a credential")
def no_false_positive():
    text = json.dumps({"BYPASS_MODE": "1", "COMPASS_CONFIG": "/etc/compass",
                       "MONKEY_NAME": "bo", "API_KEY": "abc"})
    decoded = json.loads(cap.redact_stream(text, []))
    assert decoded["BYPASS_MODE"] == "1", decoded
    assert decoded["COMPASS_CONFIG"] == "/etc/compass", decoded
    assert decoded["MONKEY_NAME"] == "bo", decoded
    assert decoded["API_KEY"] == cap.REDACTED, decoded


@case("ordinary text passes through unchanged")
def plain_text():
    text = "GNU-Mach 1.8+git20260224-up-amd64\nnproc=1\npath=/usr/bin\n"
    assert cap.redact_stream(text, []) == text


@case("a machine path is replaced and the value is not")
def path_replacement():
    out = cap.redact_stream("/home/someone/repo/images/x.qcow2",
                            [("/home/someone/repo", "<repo>")])
    assert out == "<repo>/images/x.qcow2", out


@case("stored digests describe the post-redaction files")
def digests_match_files():
    with tempfile.TemporaryDirectory() as directory:
        capture = cap.Capture(directory, "docker", [(os.path.expanduser("~"), "<home>")])
        capture.run("secret-probe",
                    [sys.executable, "-c",
                     'print(\'{"VNC_PASSWORD": "hunter2"}\')'])
        probe = capture.probes["secret-probe"]
        for stream in ("stdout", "stderr"):
            target = os.path.join(directory, probe["%s_file" % stream])
            import hashlib
            actual = hashlib.sha256(open(target, "rb").read()).hexdigest()
            assert actual == probe["%s_sha256" % stream], stream
        body = open(os.path.join(directory, probe["stdout_file"])).read()
        assert "hunter2" not in body, body
        json.loads(body)


@case("a secret-bearing probe still decodes for the parser")
def json_probe_survives_secret():
    with tempfile.TemporaryDirectory() as directory:
        capture = cap.Capture(directory, "docker", [])
        decoded = cap.json_probe(
            capture, "inspect",
            [sys.executable, "-c",
             'print(\'[{"Config": {"Env": ["VNC_PASSWORD=hunter2"]}}]\')'])
        assert decoded is not None, "redaction made the probe undecodable"
        assert decoded[0]["Config"]["Env"] == ["VNC_PASSWORD=%s" % cap.REDACTED]


@case("a known KVM failure transcript classifies false")
def kvm_known_failure():
    verdict, reason = run_kvm_stub("qemu-system-x86_64: failed to initialize KVM: "
                                   "Permission denied", 1)
    assert verdict is False, (verdict, reason)
    assert reason


@case("an unknown KVM failure classifies not-captured rather than usable")
def kvm_unknown_failure():
    verdict, reason = run_kvm_stub("sh: qemu-system-x86_64: not found", 127)
    assert verdict is None, (verdict, reason)
    assert "127" in reason, reason


@case("a probe that stays alive to the timeout classifies usable")
def kvm_success():
    verdict, reason = run_kvm_stub("", 124)
    assert verdict is True, (verdict, reason)
    assert reason == ""


def run_kvm_stub(text, status):
    """Drive container_kvm_usable with a stub standing in for the runtime."""
    with tempfile.TemporaryDirectory() as directory:
        capture = cap.Capture(directory, "stub", [])
        script = ("import sys; sys.stderr.write(%r); sys.exit(%d)" % (text, status))
        original = capture.run

        def stub(name, argv, **kwargs):
            return original(name, [sys.executable, "-c", script], **kwargs)

        capture.run = stub
        return cap.container_kvm_usable(capture, "stub", "container")


@case("--image cannot be combined with a runtime selector")
def image_rejects_selectors():
    done = subprocess.run(
        [sys.executable, os.path.join(ROOT, "scripts", "capture-runtime-evidence.py"),
         "--image", "/nonexistent.qcow2", "--container", "hurd"],
        capture_output=True, text=True, check=False)
    assert done.returncode == 2, done.returncode
    assert "cannot be combined" in done.stderr, done.stderr


@case("an offline image capture selects no container and validates")
def offline_image_capture():
    with tempfile.TemporaryDirectory() as directory:
        image = os.path.join(directory, "guest.qcow2")
        with open(image, "wb") as fh:
            fh.write(b"not a real qcow2, but a stable byte string\n")
        out_dir = os.path.join(directory, "out")
        done = subprocess.run(
            [sys.executable, os.path.join(ROOT, "scripts",
                                          "capture-runtime-evidence.py"),
             "--image", image, "--output-dir", out_dir, "--redact"],
            capture_output=True, text=True, check=False, cwd=ROOT)
        assert done.returncode == 0, done.stderr
        capture_path = os.path.dirname(done.stdout.strip())
        document = json.load(open(done.stdout.strip()))

        command = document["reproduce"]["command"]
        assert "--image" in command, command
        assert document["image"]["sha256"]["value"], document["image"]["sha256"]
        assert document["image"]["supplied_path"]["class"] == "declared"
        assert document["instance"]["container"]["class"] == "not-captured"
        assert "offline" in document["instance"]["container"]["reason"]
        assert "image-sha256" in document["probes"], list(document["probes"])

        # The package the producer just wrote is validated by the same checker
        # CI runs, so the suite carries one positive evidence package rather
        # than only the documents it rejects.
        check = subprocess.run(
            [sys.executable, os.path.join(ROOT, "scripts", "check-runtime-evidence.py"),
             capture_path],
            capture_output=True, text=True, check=False)
        assert check.returncode == 0, check.stdout + check.stderr


def main():
    failures = 0
    for name, run in CASES:
        try:
            run()
        except AssertionError as exc:
            failures += 1
            print("FAIL  %s\n        %s" % (name, exc))
        except Exception as exc:  # noqa: BLE001 - report, do not mask
            failures += 1
            print("ERROR %s\n        %s: %s" % (name, type(exc).__name__, exc))
        else:
            print("ok    %s" % name)
    if failures:
        print("test-capture-producer: FAIL (%d of %d)" % (failures, len(CASES)))
        return 1
    print("test-capture-producer: OK (%d cases)" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
