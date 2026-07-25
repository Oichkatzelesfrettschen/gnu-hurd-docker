#!/usr/bin/env python3
"""Resolve package closures for a Hurd architecture, with the LMDE overlay.

Debian GNU/Hurd has two ports. hurd-i386 is the mature 32-bit port that the
published Debian GNU/Hurd releases are cut from; hurd-amd64 is the newer 64-bit
port. Both are carried by debian-ports, and neither has a `stable` suite there:
the archive publishes `sid` and `unreleased` only, so a closure is resolved
against a rolling target for both and a rerun after an upload reports different
numbers.

Mint supplies no Hurd binaries. LMDE 7 `gigi` advertises `i386` and `amd64`
only, and its `Architecture: all` payloads -- themes, icons, cursors, artwork,
backgrounds, translations -- are listed inside those per-architecture indices
rather than under a `binary-all` directory. Taking a Mint index wholesale would
therefore offer amd64 binaries to a Hurd architecture. The overlay below keeps
only the `Architecture: all` stanzas and republishes them per component in the
target architecture's index, so Mint supplies artwork and Debian Ports supplies
every executable, and a pin keeps Debian Ports authoritative wherever both
carry a name.

Mint metadata is authenticated before it is read. The suite Release is fetched
over HTTPS and verified with gpgv against the Linux Mint repository signing key
vendored at config/keys, pinned by fingerprint; every component index is then
accepted only when its SHA-256 matches the entry in that verified Release. A
signature failure, an index the Release does not name, and a hash mismatch are
each hard failures, because an overlay that silently shrinks reports a smaller
closure as though the archive were smaller.

What this establishes is availability, candidate version, declared dependencies,
and resolver closure. It does not establish that a package installs: maintainer
scripts, runtime startup, D-Bus and GSettings behavior, and session viability
are guest facts, and a resolved set is a prediction about them rather than a
measurement of them. The verdicts below say "resolves", never "installs".

Classes:

  native            an Architecture: <target> binary exists
  architecture-all  one binary serves every architecture
  uninstallable     the package exists and its dependencies do not close
  missing           no binary for the target in any configured suite

This reads the archive as data on a Linux host. A Hurd userland does not execute
in an ordinary Linux container, which would take a Mach ABI compatibility layer
nothing here supplies; docs/audits/hurd-execution-boundary-and-archive-layer.md
carries that probe.
"""

import argparse
import base64
import datetime
import gzip
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

PORTS = os.environ.get("HURD_PORTS_MIRROR",
                       "http://ftp.ports.debian.org/debian-ports")
LMDE_MIRROR = os.environ.get(
    "LMDE_MIRROR", "https://mirrors.edge.kernel.org/linuxmint-packages")
LMDE_SUITE = os.environ.get("LMDE_SUITE", "gigi")
# gigi advertises romeo and incoming as well, and their amd64 indices are the
# 20-byte empty gzip, so the overlay reads the components that publish payloads.
LMDE_COMPONENTS = ("main", "upstream", "import", "backport")

# The primary key of the Linux Mint repository signing key. gpgv resolves
# subkeys from it, so pinning the primary survives a subkey rotation.
MINT_KEY_FINGERPRINT = "302F0738F465C1535761F965A6616109451BBBF2"
MINT_KEYRING = os.environ.get(
    "LMDE_KEYRING",
    "/usr/local/share/gnu-hurd-docker/linuxmint-archive-keyring.asc")

OVERLAY_ORIGIN = "lmde-arch-all-overlay"

# The fixture suite lives beside the resolver in the image and in the tree, so
# the same --self-test invocation runs from a checkout and from the container.
SELF_TEST_SUITE = os.environ.get(
    "HURD_SELF_TEST_SUITE",
    os.path.join(os.path.dirname(os.path.abspath(__file__)),
                 "..", "tests", "hurd-archive"))

# What has to work before a MATE session can start at all. The metapackage and
# the privileged-session layer are deliberately absent: their failure answers a
# different question and must not mask this one.
MATE_BOOTSTRAP = [
    "mate-session-manager",
    "mate-settings-daemon",
    "mate-panel",
    "marco",
    "caja",
    "mate-terminal",
    "mate-notification-daemon",
    "mate-menus",
    "mate-icon-theme",
    "mate-themes",
]

# Settings administration, which a session can start without.
MATE_CONTROL = [
    "mate-control-center",
    "dconf-gsettings-backend",
    "dconf-cli",
]

# The authorization layer. Its absence is the reason the metapackages fail, and
# it is a port rather than a packaging accident.
MATE_PRIVILEGED = [
    "mate-polkit",
    "polkitd",
    "accountsservice",
]

# The metapackages, asked as their own question: whether Debian's declared
# desktop closes on this port.
MATE_META = [
    "mate-desktop-environment-core",
    "mate-desktop-environment",
]

# The desktop as a user meets it, past the first session.
MATE_APPLICATIONS = [
    "mate-applets",
    "mate-media",
    "mate-power-manager",
    "mate-screensaver",
    "mate-system-monitor",
    "mate-utils",
    "atril",
    "engrampa",
    "eom",
    "pluma",
    "mate-calc",
    "caja-open-terminal",
    "mate-tweak",
    "xorg",
    "xserver-xorg-video-vesa",
    "dbus-x11",
]

# Mint presentation assets, all Architecture: all, taken unmodified. Mint names
# backgrounds per release codename rather than per suite, so the set is
# discovered instead of guessed; a guessed name reads as a missing package when
# it never existed.
MINT_VISUAL = [
    "mint-themes",
    "mint-l-theme",
    "mint-l-icons",
    "mint-x-icons",
    "mint-y-icons",
    "mint-cursor-themes",
    "mint-artwork",
    "mint-backgrounds-*",
    "mint-translations",
]

# Mint integration, which is code rather than artwork and fails for its own
# reasons.
MINT_INTEGRATION = [
    "mintmenu",
    "xapps-common",
    "xapp-symbolic-icons",
]

SETS = {
    "mate-bootstrap": MATE_BOOTSTRAP,
    "mate-control": MATE_CONTROL,
    "mate-privileged-integration": MATE_PRIVILEGED,
    "mate-meta-validation": MATE_META,
    "mate-applications": MATE_APPLICATIONS,
    "mint-visual": MINT_VISUAL,
    "mint-mate-integration": MINT_INTEGRATION,
    "everything": (MATE_BOOTSTRAP + MATE_CONTROL + MATE_PRIVILEGED
                   + MATE_META + MATE_APPLICATIONS + MINT_VISUAL
                   + MINT_INTEGRATION),
}


class ArchiveTrustError(Exception):
    """Metadata failed to authenticate, so no verdict may be drawn from it."""


def run(argv, env=None, timeout=900):
    done = subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                          check=False, env=env)
    return done.returncode, done.stdout, done.stderr


def fetch(url):
    """Retrieve bytes. urllib serves file:// as well as https://, which is the
    seam the offline self-test uses to feed fixture archives to the same code
    path the network archives take."""
    with urllib.request.urlopen(url, timeout=180) as response:
        return response.read()


def dearmor(text):
    """Decode an ASCII-armored OpenPGP block to its packet bytes.

    Armor headers carry a colon and the CRC line begins with '=', so the radix-64
    payload is everything else. Decoding here keeps gnupg off the resolver image:
    gpgv reads a binary keyring and needs no key management.
    """
    payload, inside = [], False
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("-----BEGIN"):
            inside = True
            continue
        if line.startswith("-----END"):
            break
        if inside and line and ":" not in line and not line.startswith("="):
            payload.append(line)
    if not payload:
        raise ArchiveTrustError("no armored OpenPGP block found")
    return base64.b64decode("".join(payload))


def primary_key_fingerprint(packets):
    """Return the fingerprint of the first public-key packet.

    RFC 4880 section 12.2 defines a version 4 fingerprint as SHA-1 over 0x99,
    the two-octet packet length, and the packet body -- which is exactly the
    leading bytes of an old-format tag 6 packet, the form gpg exports.
    """
    if not packets or packets[0] != 0x99:
        raise ArchiveTrustError(
            "the keyring does not begin with an old-format public-key packet")
    length = int.from_bytes(packets[1:3], "big")
    return hashlib.sha1(packets[:3 + length]).hexdigest().upper()


def trusted_keyring(path, fingerprint, workspace):
    """Materialize the vendored key as a binary keyring after checking its pin.

    The pin is the trust anchor: it is checked into the repository, so replacing
    the key file alone changes nothing a reviewer cannot see.
    """
    with open(path, "r", encoding="utf-8") as handle:
        packets = dearmor(handle.read())
    found = primary_key_fingerprint(packets)
    if found != fingerprint.upper().replace(" ", ""):
        raise ArchiveTrustError(
            "keyring %s carries primary key %s, and %s is pinned"
            % (path, found, fingerprint))
    binary = os.path.join(workspace, "archive-keyring.gpg")
    with open(binary, "wb") as handle:
        handle.write(packets)
    return binary, found


def verify_detached(keyring, signature, message):
    status, out, err = run(["gpgv", "--keyring", keyring, signature, message],
                           timeout=120)
    if status != 0:
        raise ArchiveTrustError(
            "gpgv rejected %s: %s" % (message, " ".join((out + err).split())[:300]))
    return " ".join((out + err).split())[:300]


def release_digests(text):
    """Map each path named in a Release SHA-256 section to its digest and size."""
    digests, inside = {}, False
    for line in text.splitlines():
        if re.match(r"^[A-Za-z0-9-]+:", line):
            inside = line.startswith("SHA256:")
            continue
        if not inside:
            continue
        fields = line.split()
        if len(fields) == 3:
            digests[fields[2]] = (fields[0], int(fields[1]))
    return digests


def release_field(text, name):
    found = re.search(r"^%s:\s*(.+)$" % re.escape(name), text, re.MULTILINE)
    return found.group(1).strip() if found else ""


def verified_lmde_release(mirror, suite, keyring, workspace):
    """Fetch the LMDE Release, verify its detached signature, and return it."""
    base = "%s/dists/%s" % (mirror, suite)
    release = fetch("%s/Release" % base)
    signature = fetch("%s/Release.gpg" % base)
    release_path = os.path.join(workspace, "lmde-Release")
    signature_path = os.path.join(workspace, "lmde-Release.gpg")
    with open(release_path, "wb") as handle:
        handle.write(release)
    with open(signature_path, "wb") as handle:
        handle.write(signature)
    verify_detached(keyring, signature_path, release_path)
    text = release.decode("utf-8", "replace")
    return {
        "text": text,
        "sha256": hashlib.sha256(release).hexdigest(),
        "date": release_field(text, "Date"),
        "codename": release_field(text, "Codename"),
        "digests": release_digests(text),
    }


def verified_index(mirror, suite, component, release):
    """Return one component index, refusing anything the Release does not name
    or whose bytes do not hash to what it names."""
    path = "%s/binary-amd64/Packages.gz" % component
    expected = release["digests"].get(path)
    if expected is None:
        raise ArchiveTrustError(
            "the verified Release for %s does not name %s" % (suite, path))
    raw = fetch("%s/dists/%s/%s" % (mirror, suite, path))
    found = hashlib.sha256(raw).hexdigest()
    if found != expected[0]:
        raise ArchiveTrustError(
            "%s hashes to %s and the verified Release names %s"
            % (path, found, expected[0]))
    try:
        index = gzip.decompress(raw)
    except (OSError, EOFError) as exc:
        raise ArchiveTrustError(
            "%s matches its digest and does not decompress: %s" % (path, exc))
    return index.decode("utf-8", "replace"), found


def arch_all_stanzas(index, mirror):
    """Keep the Architecture: all stanzas and make their pool paths absolute.

    Every version and every component copy is kept. Deduplicating by name would
    let whichever component happened to be read first decide the candidate, which
    is not the selection apt performs; apt chooses by version and priority, and
    it can only do that when it is shown the whole set.
    """
    kept = []
    for stanza in index.split("\n\n"):
        if not stanza.strip():
            continue
        if not re.search(r"^Architecture:\s*all\s*$", stanza, re.MULTILINE):
            continue
        stanza = re.sub(r"^Filename:\s*(\S+)", lambda m:
                        "Filename: %s/%s" % (mirror, m.group(1)),
                        stanza, flags=re.MULTILINE)
        kept.append(stanza.strip())
    return kept


def write_overlay(root, architecture, mirror, suite, release):
    """Publish the LMDE Architecture: all payloads as a local repository.

    Each source component keeps its own component directory, so provenance
    survives into the index apt reads and apt performs the version selection
    rather than this script.
    """
    overlay = os.path.join(root, "lmde")
    components, kept, index_digests = [], 0, {}
    entries = []
    for component in LMDE_COMPONENTS:
        index, digest = verified_index(mirror, suite, component, release)
        index_digests["%s/binary-amd64/Packages.gz" % component] = digest
        stanzas = arch_all_stanzas(index, mirror)
        if not stanzas:
            continue
        directory = os.path.join(overlay, "dists", suite, component,
                                 "binary-%s" % architecture)
        os.makedirs(directory, exist_ok=True)
        body = ("\n\n".join(stanzas) + "\n").encode("utf-8")
        with open(os.path.join(directory, "Packages"), "wb") as handle:
            handle.write(body)
        entries.append((" %s %d %s/binary-%s/Packages"
                        % (hashlib.sha256(body).hexdigest(), len(body),
                           component, architecture)))
        components.append(component)
        kept += len(stanzas)

    text = ("Origin: %s\nLabel: LMDE Architecture: all overlay\n"
            "Suite: %s\nCodename: %s\nArchitectures: %s\nComponents: %s\n"
            "SHA256:\n%s\n"
            % (OVERLAY_ORIGIN, suite, suite, architecture,
               " ".join(components), "\n".join(entries)))
    release_path = os.path.join(overlay, "dists", suite, "Release")
    with open(release_path, "w", encoding="utf-8") as handle:
        handle.write(text)
    return {
        "components": components,
        "architecture_all_packages": kept,
        "source_index_sha256": index_digests,
        "overlay_release_sha256": hashlib.sha256(
            text.encode("utf-8")).hexdigest(),
    }


def build_tree(root, architecture, ports, lmde):
    """Create a private apt state tree whose native architecture is the target."""
    layout = ["etc/apt/apt.conf.d", "etc/apt/preferences.d",
              "etc/apt/trusted.gpg.d", "var/lib/apt/lists/partial",
              "var/lib/dpkg", "var/cache/apt/archives/partial"]
    for part in layout:
        os.makedirs(os.path.join(root, part), exist_ok=True)
    open(os.path.join(root, "var/lib/dpkg/status"), "w").close()

    keyring = "/usr/share/keyrings/debian-ports-archive-keyring.gpg"
    if os.path.exists(keyring):
        shutil.copy(keyring, os.path.join(root, "etc/apt/trusted.gpg.d"))

    # A file:// ports mirror is a fixture, which carries no signature; the
    # network mirror is verified by apt against the debian-ports keyring above.
    local = "[trusted=yes] " if ports.startswith("file:") else ""
    sources = ["deb %s%s sid main" % (local, ports),
               "deb %s%s unreleased main" % (local, ports)]

    if lmde:
        sources.append("deb [trusted=yes] file://%s/lmde %s %s"
                       % (root, LMDE_SUITE, " ".join(lmde["components"])))
        # The overlay is authenticated upstream and republished locally, so its
        # own signature would prove nothing; the pin is what keeps it from
        # supplying a name Debian Ports builds natively.
        with open(os.path.join(root, "etc/apt/preferences.d/00-ports-wins"),
                  "w", encoding="utf-8") as handle:
            handle.write("Package: *\nPin: release o=%s\nPin-Priority: 100\n"
                         % OVERLAY_ORIGIN)

    with open(os.path.join(root, "etc/apt/sources.list"), "w",
              encoding="utf-8") as handle:
        handle.write("\n".join(sources) + "\n")

    config = os.path.join(root, "apt.conf")
    with open(config, "w", encoding="utf-8") as handle:
        handle.write(
            'APT::Architecture "%(a)s";\n'
            'APT::Architectures { "%(a)s"; };\n'
            'Dir::Etc "%(r)s/etc/apt";\n'
            'Dir::Etc::SourceList "%(r)s/etc/apt/sources.list";\n'
            'Dir::Etc::Parts "%(r)s/etc/apt/apt.conf.d";\n'
            'Dir::Etc::PreferencesParts "%(r)s/etc/apt/preferences.d";\n'
            'Dir::Etc::TrustedParts "%(r)s/etc/apt/trusted.gpg.d";\n'
            'Dir::State "%(r)s/var/lib/apt";\n'
            'Dir::State::status "%(r)s/var/lib/dpkg/status";\n'
            'Dir::Cache "%(r)s/var/cache/apt";\n'
            % {"a": architecture, "r": root})
    return config


def expand(env, packages):
    """Replace any trailing-* name with the packages the archive publishes under
    that prefix."""
    resolved, unmatched = [], []
    for name in packages:
        if not name.endswith("*"):
            resolved.append(name)
            continue
        status, out, _ = run(["apt-cache", "pkgnames", name[:-1]], env=env)
        found = sorted(set(out.split())) if status == 0 else []
        if found:
            resolved.extend(found)
        else:
            unmatched.append(name)
            print("no package matches %s" % name, file=sys.stderr)
    return resolved, unmatched


def candidate_origin(env, package, workspace):
    """Report which configured source supplies the candidate.

    apt-cache policy marks the installed-or-selected entry with ***; absent
    that, the first priority line of the version table is the candidate's, which
    is what distinguishes a Debian Ports answer from an overlay answer.

    The overlay lives under a per-invocation temporary directory, so its path is
    replaced by the overlay's origin name: the raw path is machine-only state
    that would differ on every rerun and make two reports of the same archive
    read as two different results.
    """
    status, out, _ = run(["apt-cache", "policy", package], env=env)
    if status != 0:
        return ""
    lines = [line.strip().replace("file:%s/lmde" % workspace, OVERLAY_ORIGIN)
             for line in out.splitlines()]
    for index, line in enumerate(lines):
        if line.startswith("***") and index + 1 < len(lines):
            return lines[index + 1][:200]
    for line in lines:
        if re.match(r"^\d+ \S+", line):
            return line[:200]
    return ""


def classify(env, package, architecture, workspace):
    status, out, _ = run(["apt-cache", "show", package], env=env)
    if status != 0 or not out.strip():
        return {"package": package, "class": "missing",
                "evidence": "no record in any configured suite"}
    architectures = re.findall(r"^Architecture:\s*(\S+)", out, re.MULTILINE)
    versions = re.findall(r"^Version:\s*(\S+)", out, re.MULTILINE)
    version = versions[0] if versions else ""
    record = {"package": package, "version": version,
              "architectures": sorted(set(architectures)),
              "candidate_origin": candidate_origin(env, package, workspace)}
    if architecture in architectures:
        klass = "native"
    elif "all" in architectures:
        klass = "architecture-all"
    else:
        record.update({"class": "missing",
                       "evidence": "record carries architectures %s"
                                   % ",".join(sorted(set(architectures)))})
        return record
    sim, sim_out, sim_err = run(
        ["apt-get", "install", "-s", "-y", "--no-install-recommends", package],
        env=env)
    if sim != 0:
        record.update({"class": "uninstallable", "architecture_class": klass,
                       "evidence": first_blocker(sim_out + sim_err)})
        return record
    record.update({"class": klass, "evidence": "dependencies resolve"})
    return record


def first_blocker(text):
    """Name the dependency that failed, preferring it to the resolver's summary.

    apt ends with "E: Unable to correct problems", which says a transaction
    failed without saying what blocked it. A line naming a dependency
    distinguishes a package the port lacks from a version skew between two
    packages the port has, and those are different pieces of work.
    """
    reasons = ("but it is not installable",
               "but it is not going to be installed",
               "none of the choices are installable",
               "but it is not installed")
    fallback = ""
    for line in text.splitlines():
        stripped = line.strip()
        if any(reason in stripped for reason in reasons):
            return stripped[:300]
        if not fallback and stripped.startswith("E: "):
            fallback = stripped[:300]
    return fallback or " ".join(text.split())[:300] or "no resolver output"


def missing_dependencies(results):
    """Split the set into what resolves today and what has to be built.

    The per-package verdicts already say which members resolve, so the resolvable
    subset is read from them rather than rediscovered by dropping members until a
    simulation passes. Each failing member contributes the dependency name that
    blocked it, which is the name someone must build or substitute; a blocker
    that is itself a member of the set is reported under its own name.
    """
    resolvable, unmet = [], set()
    for item in results:
        if item["class"] in ("native", "architecture-all"):
            resolvable.append(item["package"])
            continue
        unmet.add(item["package"])
        for name in re.findall(r"Depends: (\S+)", item.get("evidence", "")):
            unmet.add(name)
        for name in re.findall(r"Package '(\S+)' has no installation candidate",
                               item.get("evidence", "")):
            unmet.add(name)
    return sorted(unmet), resolvable


def tool_versions(env):
    versions = {}
    for name, argv in (("apt", ["apt-get", "--version"]),
                       ("dpkg", ["dpkg", "--version"])):
        status, out, _ = run(argv, env=env, timeout=60)
        versions[name] = out.splitlines()[0].strip() if status == 0 and out else ""
    return versions


def resolve(args, workspace):
    """Build the tree, authenticate the metadata, and classify the set."""
    provenance = {
        "collected_at": datetime.datetime.now(
            datetime.timezone.utc).replace(microsecond=0).isoformat(),
        "resolver_image": os.environ.get("HURD_RESOLVER_IMAGE", ""),
        "debian_ports_mirror": args.ports_mirror,
        "suites": ["sid", "unreleased"],
    }

    lmde = None
    if not args.no_lmde:
        keyring, fingerprint = trusted_keyring(
            args.keyring, MINT_KEY_FINGERPRINT, workspace)
        release = verified_lmde_release(args.lmde_mirror, args.lmde_suite,
                                        keyring, workspace)
        lmde = write_overlay(workspace, args.architecture, args.lmde_mirror,
                             args.lmde_suite, release)
        lmde.update({
            "mirror": args.lmde_mirror,
            "suite": args.lmde_suite,
            "signing_key_fingerprint": fingerprint,
            "release_sha256": release["sha256"],
            "release_date": release["date"],
        })

    config = build_tree(workspace, args.architecture, args.ports_mirror, lmde)
    env = dict(os.environ, APT_CONFIG=config)
    provenance["tools"] = tool_versions(env)

    status, _, err = run(["apt-get", "update", "-qq"], env=env)
    if status != 0:
        raise ArchiveTrustError("apt-get update failed: %s"
                                % " ".join(err.split())[:400])

    packages, unmatched = expand(env, args.packages or SETS[args.set])
    results = [classify(env, name, args.architecture, workspace)
               for name in packages]
    unmet, resolvable = missing_dependencies(results)

    if resolvable:
        final, final_out, final_err = run(
            ["apt-get", "install", "-s", "-y", "--no-install-recommends"]
            + resolvable, env=env)
    else:
        final, final_out, final_err = 1, "", "no member of the set resolves"
    transaction = [line.strip()[5:] for line in final_out.splitlines()
                   if line.startswith("Inst ")]

    report = {
        "architecture": args.architecture,
        "set": args.set,
        "provenance": provenance,
        "lmde_overlay": lmde or {"enabled": False},
        "packages": results,
        "unmatched_patterns": unmatched,
        "resolvable_subset": resolvable,
        "resolvable_subset_resolves": final == 0,
        "resolvable_subset_blocker": "" if final == 0
                                     else first_blocker(final_out + final_err),
        "recursive_transaction": transaction,
        "recursive_transaction_size": len(transaction),
        "must_be_built_or_substituted": unmet,
        "summary": {},
    }
    for item in results:
        report["summary"][item["class"]] = report["summary"].get(
            item["class"], 0) + 1
    return report


def print_report(report):
    results = report["packages"]
    if not results:
        raise ValueError("no package matched the requested set")
    lmde = report["lmde_overlay"]
    print("architecture: %s   set: %s   LMDE arch:all packages: %s\n"
          % (report["architecture"], report["set"],
             lmde.get("architecture_all_packages", "overlay off")))
    width = max(len(item["package"]) for item in results)
    for item in results:
        print("%-*s  %-18s %s" % (width, item["package"], item["class"],
                                  item.get("version", "")))
    print()
    for key in sorted(report["summary"]):
        print("%-18s %d" % (key, report["summary"][key]))
    print("\nresolvable subset: %d of %d, %s"
          % (len(report["resolvable_subset"]), len(results),
             "pulling %d packages recursively"
             % report["recursive_transaction_size"]
             if report["resolvable_subset_resolves"]
             else "still blocked: %s" % report["resolvable_subset_blocker"]))
    if report["must_be_built_or_substituted"]:
        print("must be built or substituted (%d): %s"
              % (len(report["must_be_built_or_substituted"]),
                 ", ".join(report["must_be_built_or_substituted"])))
    if report["unmatched_patterns"]:
        print("patterns matching nothing: %s"
              % ", ".join(report["unmatched_patterns"]))


def self_test(suite):
    """Run the fixture suite, which imports this module and drives it offline."""
    path = os.path.join(suite, "selftest.py")
    if not os.path.exists(path):
        print("no fixture suite at %s" % path, file=sys.stderr)
        return 5
    namespace = {"__name__": "selftest_hurd_closure", "__file__": path}
    with open(path, "r", encoding="utf-8") as handle:
        exec(compile(handle.read(), path, "exec"), namespace)  # noqa: S102
    return namespace["run"](sys.modules[__name__])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--architecture", default="hurd-amd64",
                        choices=["hurd-amd64", "hurd-i386"])
    parser.add_argument("--set", default="mate-bootstrap", choices=sorted(SETS),
                        help="which package set to resolve")
    parser.add_argument("--no-lmde", action="store_true",
                        help="omit the LMDE Architecture: all overlay")
    parser.add_argument("--ports-mirror", default=PORTS)
    parser.add_argument("--lmde-mirror", default=LMDE_MIRROR)
    parser.add_argument("--lmde-suite", default=LMDE_SUITE)
    parser.add_argument("--keyring", default=MINT_KEYRING,
                        help="armored Linux Mint archive key, pinned by fingerprint")
    parser.add_argument("--json", default="")
    parser.add_argument("--self-test", action="store_true",
                        help="run the offline fixture suite and exit")
    parser.add_argument("--self-test-suite", default=SELF_TEST_SUITE,
                        help="directory holding selftest.py and its fixtures")
    parser.add_argument("packages", nargs="*")
    args = parser.parse_args()

    if args.self_test:
        return self_test(args.self_test_suite)

    workspace = tempfile.mkdtemp(prefix="hurd-apt-")
    try:
        report = resolve(args, workspace)
    except ArchiveTrustError as exc:
        print("archive metadata rejected: %s" % exc, file=sys.stderr)
        return 3
    except (urllib.error.URLError, OSError) as exc:
        # An unreachable mirror produces no verdict, and reporting it as one
        # would be the overstatement this resolver exists to remove.
        print("archive unreachable: %s" % exc, file=sys.stderr)
        return 3
    finally:
        if os.environ.get("HURD_APT_KEEP"):
            print("apt state kept at %s" % workspace, file=sys.stderr)
        else:
            shutil.rmtree(workspace, ignore_errors=True)

    if not report["packages"]:
        print("no package matched the requested set", file=sys.stderr)
        return 4

    print_report(report)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=2, sort_keys=True)
            handle.write("\n")
        print("\nreport: %s" % args.json)
    return 0


if __name__ == "__main__":
    sys.exit(main())
