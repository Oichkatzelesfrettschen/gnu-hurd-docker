"""Offline fixture suite for the Hurd package-closure resolver.

The resolver's verdicts are produced by apt over a synthetic architecture, so a
green source-level gate says nothing about whether a verdict is right. This
drives the same functions against hand-written indices whose correct answer is
known, and against a real signed Release whose signature can be broken on
purpose.

Everything here is local. The resolver reaches its archives through urllib,
which serves file:// as well as https://, so a fixture directory substitutes
for a mirror without a network and without a signature-bypassing shortcut in
the code under test. The authentication functions are called directly with good
and tampered bytes, because standing up a locally signed apt repository would
need key generation and would still be read through [trusted=yes], which is the
one thing that must not be trusted here.

This suite never compares against the committed live reports: sid, unreleased,
and the LMDE suite move daily, so a comparison would turn someone else's upload
into a red gate.
"""

import gzip
import hashlib
import json
import os
import shutil
import tempfile

FIXTURES = os.path.dirname(os.path.abspath(__file__))
# From a checkout the key sits at the repository path; the resolver image places
# it where LMDE_KEYRING names, so one invocation runs in both.
KEYRING = os.environ.get(
    "LMDE_KEYRING",
    os.path.join(FIXTURES, "..", "..", "config", "keys",
                 "linuxmint-archive-keyring.asc"))
MINT_FINGERPRINT = "302F0738F465C1535761F965A6616109451BBBF2"


class Args(object):
    """The attribute surface resolve() reads off an argparse namespace."""

    def __init__(self, **fields):
        self.architecture = "hurd-amd64"
        self.set = "mate-bootstrap"
        self.no_lmde = True
        self.ports_mirror = ""
        self.lmde_mirror = ""
        self.lmde_suite = "gigi"
        self.keyring = KEYRING
        self.foreign_architecture = ""
        self.build_dependencies = False
        self.main_archive = ""
        self.packages = []
        self.installed_status = ""
        for key, value in fields.items():
            setattr(self, key, value)


def stanza(name, version, architecture, **fields):
    lines = ["Package: %s" % name, "Version: %s" % version,
             "Architecture: %s" % architecture]
    for key, value in fields.items():
        lines.append("%s: %s" % (key.replace("_", "-").title(), value))
    body = "payload for %s %s" % (name, version)
    lines += ["Filename: pool/main/%s_%s.deb" % (name, version),
              "Size: %d" % len(body),
              "SHA256: %s" % hashlib.sha256(body.encode()).hexdigest(),
              "Maintainer: fixture <root@localhost>",
              "Description: fixture package %s" % name]
    return "\n".join(lines)


def write_repo(root, suite, stanzas, foreign_stanzas=()):
    """Publish one fixture suite as a file:// apt repository.

    A second architecture index is published when asked for, so a foreign
    architecture can be enabled against the same fixture.
    """
    entries, architectures = [], []
    for architecture, members in (("hurd-amd64", stanzas),
                                  ("hurd-i386", list(foreign_stanzas))):
        if not members:
            continue
        component = os.path.join(root, "dists", suite, "main",
                                 "binary-%s" % architecture)
        os.makedirs(component, exist_ok=True)
        body = ("\n\n".join(members) + "\n").encode("utf-8")
        with open(os.path.join(component, "Packages"), "wb") as handle:
            handle.write(body)
        entries.append(" %s %d main/binary-%s/Packages"
                       % (hashlib.sha256(body).hexdigest(), len(body),
                          architecture))
        architectures.append(architecture)
    release = ("Origin: fixture\nLabel: fixture\nSuite: %s\nCodename: %s\n"
               "Architectures: %s\nComponents: main\nSHA256:\n%s\n"
               % (suite, suite, " ".join(architectures), "\n".join(entries)))
    with open(os.path.join(root, "dists", suite, "Release"), "w",
              encoding="utf-8") as handle:
        handle.write(release)


def expire_release(root, suite):
    """Backdate a fixture suite's Release so apt treats it as expired.

    A snapshot Release carries the Valid-Until it was published with, so the
    bytes a timestamp pins stay identical while apt stops accepting them. That
    is the failure a pinned archive meets weeks after it is pinned, and it is
    invisible to a check that only reads the timestamp grammar.
    """
    path = os.path.join(root, "dists", suite, "Release")
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    stamped = ("Date: Mon, 01 Jan 2024 00:00:00 UTC\n"
               "Valid-Until: Tue, 02 Jan 2024 00:00:00 UTC\n")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(stamped + text)


def ports_fixture(root, sid, unreleased=(), foreign=()):
    write_repo(root, "sid", sid, foreign)
    write_repo(root, "unreleased", list(unreleased) or [
        stanza("fixture-unreleased-marker", "1", "hurd-amd64")])
    return "file://%s" % root


def lmde_fixture(root, suite, component, stanzas):
    """Publish one component index plus a Release naming its digest."""
    directory = os.path.join(root, "dists", suite, component, "binary-amd64")
    os.makedirs(directory, exist_ok=True)
    body = gzip.compress(("\n\n".join(stanzas) + "\n").encode("utf-8"), mtime=0)
    with open(os.path.join(directory, "Packages.gz"), "wb") as handle:
        handle.write(body)
    return hashlib.sha256(body).hexdigest()


class Suite(object):
    def __init__(self):
        self.failures = []
        self.passes = 0

    def check(self, name, condition, detail=""):
        if condition:
            self.passes += 1
            print("ok    %s" % name)
        else:
            self.failures.append("%s: %s" % (name, detail))
            print("FAIL  %s: %s" % (name, detail))

    def raises(self, name, exception, call):
        try:
            call()
        except exception as exc:
            self.passes += 1
            print("ok    %s (%s)" % (name, str(exc)[:80]))
            return
        except Exception as exc:  # noqa: BLE001 - the wrong exception is a failure
            self.check(name, False, "raised %r instead" % exc)
            return
        self.check(name, False, "returned without raising")


def verdicts(report):
    return {item["package"]: item["class"] for item in report["packages"]}


def test_classification(module, suite, workspace):
    root = os.path.join(workspace, "ports-classification")
    mirror = ports_fixture(root, [
        stanza("fixture-native", "1.0", "hurd-amd64"),
        stanza("fixture-all", "2.0", "all"),
        stanza("fixture-foreign", "3.0", "amd64"),
        stanza("fixture-uninstallable", "4.0", "hurd-amd64",
               depends="fixture-absent-dependency"),
        # A version skew between two packages the port does carry, which is
        # different work from a package the port lacks.
        stanza("fixture-skewed", "5.0", "hurd-amd64",
               depends="fixture-skew-partner (= 2.0)"),
        stanza("fixture-skew-partner", "1.0", "hurd-amd64"),
    ])
    state = os.path.join(workspace, "state-classification")
    os.makedirs(state)
    report = module.resolve(
        Args(ports_mirror=mirror,
             packages=["fixture-native", "fixture-all", "fixture-foreign",
                       "fixture-uninstallable", "fixture-never-published",
                       "fixture-skewed"]),
        state)
    seen = verdicts(report)
    evidence = {item["package"]: item.get("evidence", "")
                for item in report["packages"]}
    suite.check("a version skew is reported by the dependency, not the summary",
                seen.get("fixture-skewed") == "uninstallable"
                and "fixture-skew-partner" in evidence.get("fixture-skewed", ""),
                evidence.get("fixture-skewed", ""))
    suite.check("native binary classifies native",
                seen.get("fixture-native") == "native", str(seen))
    suite.check("one binary for every architecture classifies architecture-all",
                seen.get("fixture-all") == "architecture-all", str(seen))
    suite.check("a record for another architecture classifies missing",
                seen.get("fixture-foreign") == "missing", str(seen))
    suite.check("an unmet dependency classifies uninstallable",
                seen.get("fixture-uninstallable") == "uninstallable", str(seen))
    suite.check("an unpublished name classifies missing",
                seen.get("fixture-never-published") == "missing", str(seen))
    suite.check("the blocking dependency is named for rebuild",
                "fixture-absent-dependency"
                in report["must_be_built_or_substituted"],
                str(report["must_be_built_or_substituted"]))
    suite.check("the recursive transaction is recorded, not just counted",
                report["recursive_transaction_size"] == len(
                    report["recursive_transaction"])
                and report["recursive_transaction_size"] >= 2,
                str(report["recursive_transaction"]))
    suite.check("provenance records the apt and dpkg versions",
                bool(report["provenance"]["tools"]["apt"])
                and bool(report["provenance"]["tools"]["dpkg"]),
                str(report["provenance"]["tools"]))
    # The image is named by the digest its own Dockerfile pinned. A value read
    # from a local tag would record whatever that tag points at rather than the
    # image that produced the verdicts.
    suite.check("provenance names the resolver image by digest",
                report["provenance"]["resolver_image"].startswith(
                    "debian@sha256:"),
                report["provenance"]["resolver_image"] or "empty")


def test_version_selection(module, suite, workspace):
    root = os.path.join(workspace, "ports-versions")
    mirror = ports_fixture(
        root,
        [stanza("fixture-multi", "1.0", "hurd-amd64"),
         stanza("fixture-multi", "3.0", "hurd-amd64"),
         stanza("fixture-multi", "2.0", "hurd-amd64"),
         stanza("fixture-across", "1.0", "hurd-amd64")],
        [stanza("fixture-across", "9.0", "hurd-amd64")])
    state = os.path.join(workspace, "state-versions")
    os.makedirs(state)
    report = module.resolve(
        Args(ports_mirror=mirror,
             packages=["fixture-multi", "fixture-across"]), state)
    chosen = {item["package"]: item.get("version") for item in report["packages"]}
    suite.check("the highest of several versions is the candidate",
                chosen.get("fixture-multi") == "3.0", str(chosen))
    suite.check("version decides across suites, not read order",
                chosen.get("fixture-across") == "9.0", str(chosen))
    suite.check("the candidate origin is recorded",
                all(item.get("candidate_origin")
                    for item in report["packages"]),
                str([item.get("candidate_origin")
                     for item in report["packages"]]))
    # The apt state is per-invocation, so its path is machine-only state that
    # would differ on every rerun and make two reports of one archive read as
    # two results.
    serialized = json.dumps(report)
    suite.check("no per-invocation path reaches the report",
                state not in serialized and "/tmp/hurd-apt-" not in serialized,
                "a workspace path was serialized")


def test_conflict(module, suite, workspace):
    root = os.path.join(workspace, "ports-conflict")
    mirror = ports_fixture(root, [
        stanza("fixture-left", "1.0", "hurd-amd64", conflicts="fixture-right"),
        stanza("fixture-right", "1.0", "hurd-amd64", conflicts="fixture-left"),
    ])
    state = os.path.join(workspace, "state-conflict")
    os.makedirs(state)
    report = module.resolve(
        Args(ports_mirror=mirror,
             packages=["fixture-left", "fixture-right"]), state)
    seen = verdicts(report)
    suite.check("each conflicting package resolves on its own",
                seen.get("fixture-left") == "native"
                and seen.get("fixture-right") == "native", str(seen))
    suite.check("the set as a whole reports the conflict",
                not report["resolvable_subset_resolves"]
                and bool(report["resolvable_subset_blocker"]),
                report["resolvable_subset_blocker"])


def test_wildcards(module, suite, workspace):
    root = os.path.join(workspace, "ports-wildcard")
    mirror = ports_fixture(root, [
        stanza("fixture-family-one", "1.0", "all"),
        stanza("fixture-family-two", "1.0", "all"),
    ])
    state = os.path.join(workspace, "state-wildcard")
    os.makedirs(state)
    report = module.resolve(
        Args(ports_mirror=mirror,
             packages=["fixture-family-*", "fixture-nothing-*"]), state)
    seen = sorted(verdicts(report))
    suite.check("a wildcard expands to what the archive publishes",
                seen == ["fixture-family-one", "fixture-family-two"], str(seen))
    suite.check("a pattern matching nothing is reported rather than dropped",
                report["unmatched_patterns"] == ["fixture-nothing-*"],
                str(report["unmatched_patterns"]))

    state = os.path.join(workspace, "state-wildcard-empty")
    os.makedirs(state)
    empty = module.resolve(
        Args(ports_mirror=mirror, packages=["fixture-nothing-*"]), state)
    suite.check("an entirely unmatched set returns an empty result set",
                empty["packages"] == [], str(empty["packages"]))
    try:
        module.print_report(empty)
        suite.check("formatting an empty result set is guarded", False,
                    "print_report accepted an empty set")
    except ValueError:
        suite.check("formatting an empty result set is guarded", True)


def test_foreign_architecture(module, suite, workspace):
    """A foreign build installs into a native tree only when nothing it needs is
    Architecture: all.

    An Architecture: all package is realized under the native architecture, so
    an architecture-qualified dependency on one does not resolve. That is the
    barrier a foreign MATE component meets in the real archive, and it sits in
    the packaging layer rather than in any ABI question.
    """
    root = os.path.join(workspace, "ports-foreign")
    mirror = ports_fixture(
        root,
        [stanza("fixture-shared-data", "1.0", "all"),
         stanza("fixture-simple", "1.0", "hurd-amd64"),
         stanza("fixture-split", "1.0", "hurd-amd64",
                depends="fixture-shared-data")],
        foreign=[stanza("fixture-simple", "1.0", "hurd-i386",
                        multi_arch="same"),
                 stanza("fixture-split", "1.0", "hurd-i386",
                        depends="fixture-shared-data")])

    state = os.path.join(workspace, "state-foreign")
    os.makedirs(state)
    report = module.resolve(
        Args(ports_mirror=mirror, foreign_architecture="hurd-i386",
             packages=["fixture-simple", "fixture-split",
                       "fixture-shared-data"]), state)
    seen = verdicts(report)
    suite.check("a foreign request is qualified to its architecture",
                sorted(seen) == ["fixture-shared-data",
                                 "fixture-simple:hurd-i386",
                                 "fixture-split:hurd-i386"], str(sorted(seen)))
    # Qualifying an Architecture: all name asks for a binary the archive never
    # publishes, and the resulting "missing" reads as a multiarch limitation
    # rather than as an artifact of the question.
    suite.check("an Architecture: all request is not qualified to the foreign "
                "architecture",
                "fixture-shared-data:hurd-i386" not in seen, str(sorted(seen)))
    suite.check("an unqualified Architecture: all package still resolves",
                seen.get("fixture-shared-data") == "architecture-all", str(seen))
    suite.check("a self-contained foreign build resolves",
                seen.get("fixture-simple:hurd-i386") == "native", str(seen))
    suite.check("a foreign build needing an Architecture: all companion does not",
                seen.get("fixture-split:hurd-i386") == "uninstallable",
                str(seen) + " " + str([p.get("evidence")
                                       for p in report["packages"]]))
    foreign = report["foreign_architecture"]
    suite.check("the transaction reports its foreign-qualified members",
                foreign["enabled"] and foreign["name"] == "hurd-i386"
                and foreign["foreign_qualified_in_transaction"] >= 1,
                str(foreign))
    # The tree's dpkg status file is empty, so this measures that the removal
    # list is wired up rather than that a foreign build preserves an installed
    # userland. That question needs a tree seeded from the image's own status.
    suite.check("removals are reported against the tree's installed baseline",
                foreign["native_packages_removed"] == []
                and report["provenance"]["installed_baseline"]["kind"] == "empty",
                str(foreign["native_packages_removed"]))

    state = os.path.join(workspace, "state-foreign-native")
    os.makedirs(state)
    suite.raises("naming the native architecture as foreign is refused",
                 module.ArchiveTrustError,
                 lambda: module.resolve(
                     Args(ports_mirror=mirror,
                          foreign_architecture="hurd-amd64",
                          packages=["fixture-simple"]), state))


def source_stanza(name, version, build_depends, binaries=""):
    body = "source for %s %s" % (name, version)
    return "\n".join([
        "Package: %s" % name,
        "Binary: %s" % (binaries or name),
        "Version: %s" % version,
        "Architecture: any",
        "Build-Depends: %s" % build_depends,
        "Directory: pool/main/%s" % name[0],
        "Files:",
        " %s %d %s_%s.dsc" % (hashlib.md5(body.encode()).hexdigest(),
                              len(body), name, version),
        "Checksums-Sha256:",
        " %s %d %s_%s.dsc" % (hashlib.sha256(body.encode()).hexdigest(),
                              len(body), name, version),
    ])


def sources_fixture(root, suite, stanzas):
    """Publish a Sources index, which is what a build closure resolves against."""
    component = os.path.join(root, "dists", suite, "main", "source")
    os.makedirs(component, exist_ok=True)
    body = ("\n\n".join(stanzas) + "\n").encode("utf-8")
    with open(os.path.join(component, "Sources"), "wb") as handle:
        handle.write(body)
    return (" %s %d main/source/Sources"
            % (hashlib.sha256(body).hexdigest(), len(body)))


def test_build_dependencies(module, suite, workspace):
    """A missing binary is a rebuild candidate only if its build can start.

    Whether a binary exists and whether it can be produced are different archive
    questions, and a chain of build dependencies makes a rebuild an ordered
    sequence rather than one command.
    """
    root = os.path.join(workspace, "ports-buildable")
    # The binary index supplies what a build dependency resolves against.
    # apt-get build-dep adds build-essential to every request, so the fixture
    # archive publishes it the way the real one does.
    #
    # fixture-stale is published at an older version than its source, which is
    # the shape that made hurd-i386 report python3-setproctitle blocked: given a
    # bare name apt binds the source to the port binary's version and then finds
    # no source at that version.
    mirror = ports_fixture(root, [
        stanza("build-essential", "12.12", "hurd-amd64"),
        stanza("fixture-toolchain", "1.0", "hurd-amd64"),
        stanza("fixture-lib-dev", "1.0", "hurd-amd64"),
        stanza("fixture-stale", "1.0", "hurd-amd64"),
        # debhelper supplies debhelper-compat and the hurd package supplies
        # mount the same way: the name a source declares need not be a package.
        stanza("fixture-provider", "1.0", "hurd-amd64",
               provides="fixture-virtual-name"),
        # Present, and its own dependency is not, so the source text names a
        # build dependency the port has while the transaction still fails.
        stanza("fixture-broken-dev", "1.0", "hurd-amd64",
               depends="fixture-absent-deep"),
    ])
    entry = sources_fixture(root, "sid", [
        source_stanza("fixture-buildable", "1.0", "fixture-toolchain"),
        source_stanza("fixture-chained", "2.0",
                      "fixture-toolchain, fixture-absent-dev"),
        source_stanza("fixture-linux-only", "3.0",
                      "fixture-toolchain, fixture-selinux-dev"),
        source_stanza("fixture-stale", "2.0", "fixture-toolchain"),
        # The source name and the binary name are different namespaces, the way
        # policykit-1 builds polkitd.
        source_stanza("fixture-source-name", "1.0", "fixture-toolchain",
                      binaries="fixture-binary-name"),
        # The older paragraph is published first, so output order and version
        # order disagree and only a version comparison picks the right one.
        source_stanza("fixture-two-versions", "1.0", "fixture-absent-dev"),
        source_stanza("fixture-two-versions", "2.0", "fixture-toolchain"),
        # A build daemon reads each clause: an alternative group is satisfied by
        # any member, an architecture restriction that excludes the target
        # removes the clause, and a virtual name is satisfied by a provider.
        source_stanza("fixture-alternatives", "1.0",
                      "fixture-toolchain | fixture-absent-dev"),
        source_stanza("fixture-restricted", "1.0",
                      "fixture-toolchain, fixture-selinux-dev [linux-any]"),
        source_stanza("fixture-virtual", "1.0",
                      "fixture-toolchain, fixture-virtual-name"),
        source_stanza("fixture-two-absent", "1.0",
                      "fixture-toolchain, fixture-absent-one, "
                      "fixture-absent-two"),
        source_stanza("fixture-nested", "1.0",
                      "fixture-toolchain, fixture-broken-dev"),
    ])
    # The Release must name the Sources index for apt to accept it.
    release = os.path.join(root, "dists", "sid", "Release")
    with open(release, "a", encoding="utf-8") as handle:
        handle.write(entry + "\n")

    state = os.path.join(workspace, "state-buildable")
    os.makedirs(state)
    report = module.resolve(
        Args(ports_mirror=mirror, main_archive=mirror,
             build_dependencies=True,
             packages=["fixture-buildable", "fixture-chained",
                       "fixture-linux-only", "fixture-never-packaged",
                       "fixture-stale", "fixture-binary-name",
                       "fixture-two-versions", "fixture-alternatives",
                       "fixture-restricted", "fixture-virtual",
                       "fixture-two-absent", "fixture-nested"]),
        state)
    seen = verdicts(report)
    records = {item["package"]: item for item in report["packages"]}
    suite.check("a source whose build dependencies resolve is buildable",
                seen.get("fixture-buildable") == "buildable", str(seen))
    suite.check("a source blocked by a missing build dependency is blocked",
                seen.get("fixture-chained") == "blocked"
                and seen.get("fixture-linux-only") == "blocked", str(seen))
    suite.check("a name the source archive does not publish reports no-source",
                seen.get("fixture-never-packaged") == "no-source", str(seen))
    evidence = {item["package"]: item.get("evidence", "")
                for item in report["packages"]}
    suite.check("the blocking build dependency is named",
                "fixture-absent-dev" in evidence.get("fixture-chained", ""),
                evidence.get("fixture-chained", ""))
    suite.check("the report distinguishes a build closure from a binary one",
                report["mode"] == "build-dependencies", report.get("mode"))
    suite.check("a buildable source records how many build dependencies it pulls",
                any(item.get("build_dependency_count", 0) > 0
                    for item in report["packages"]),
                str([item.get("build_dependency_count")
                     for item in report["packages"]]))
    suite.check("a stale port binary does not decide which source is simulated",
                seen.get("fixture-stale") == "buildable", str(seen))
    suite.check("the simulated source version is the one the report names",
                records.get("fixture-stale", {}).get("version") == "2.0",
                str(records.get("fixture-stale")))
    suite.check("a binary name resolves to the source that builds it",
                records.get("fixture-binary-name", {}).get("source_package")
                == "fixture-source-name",
                str(records.get("fixture-binary-name")))
    suite.check("the highest source version wins over index order",
                seen.get("fixture-two-versions") == "buildable"
                and records.get("fixture-two-versions", {}).get("version")
                == "2.0", str(records.get("fixture-two-versions")))
    suite.check("a blocked source carries its build dependency as structured data",
                [entry["name"] for entry in
                 records.get("fixture-chained", {}).get(
                     "unsatisfied_build_dependencies", [])]
                == ["fixture-absent-dev"],
                str(records.get("fixture-chained", {}).get(
                    "unsatisfied_build_dependencies")))
    suite.check("a buildable source retains the versions its build would pull",
                all(item.get("build_dependency_transaction")
                    for item in report["packages"]
                    if item["class"] == "buildable"),
                str([item.get("build_dependency_transaction")
                     for item in report["packages"]]))
    suite.check("the buildable sources are checked against one builder tree",
                report["resolvable_subset_resolves"] is True
                and report["recursive_transaction_size"] > 0,
                str(report["resolvable_subset_blocker"]))
    suite.check("every unsatisfied build dependency is named, not only the first",
                [entry["name"] for entry in module.unsatisfied_dependencies(
                    "a : Depends: one (>= 2) but it is not installable\n"
                    "a : Depends: two but it is not going to be installed\n"
                    "a : Depends: one (>= 2) but it is not installable\n")]
                == ["one", "two"],
                str(module.unsatisfied_dependencies(
                    "a : Depends: one (>= 2) but it is not installable\n"
                    "a : Depends: two but it is not going to be installed\n")))
    def absent(name):
        return [entry["name"] for entry in
                records.get(name, {}).get("absent_build_dependencies", [])]

    suite.check("an alternative satisfied by any member is not absent",
                seen.get("fixture-alternatives") == "buildable"
                and absent("fixture-alternatives") == [],
                str(records.get("fixture-alternatives")))
    suite.check("an architecture restriction excluding the target removes the "
                "clause",
                seen.get("fixture-restricted") == "buildable"
                and absent("fixture-restricted") == [],
                str(records.get("fixture-restricted")))
    suite.check("a virtual name satisfied by a provider is not absent",
                seen.get("fixture-virtual") == "buildable"
                and absent("fixture-virtual") == [],
                str(records.get("fixture-virtual")))
    suite.check("every absent build dependency is found, past apt's first",
                absent("fixture-two-absent")
                == ["fixture-absent-one", "fixture-absent-two"],
                str(records.get("fixture-two-absent")))
    # The declared scan reads the source's clauses and the simulation resolves
    # transitively, so a build dependency the port has whose own dependency is
    # missing is invisible to the scan and named by apt.
    suite.check("a transitive blocker the source text does not name is reported",
                seen.get("fixture-nested") == "blocked"
                and absent("fixture-nested") == []
                and records.get("fixture-nested", {}).get("simulated_only"),
                str(records.get("fixture-nested")))
    suite.check("the two dependency views are reported where they disagree",
                any(entry["package"] == "fixture-nested"
                    for entry in report["dependency_view_disagreements"]),
                str(report["dependency_view_disagreements"]))
    suite.check("two independent absent clauses need no disagreement",
                records.get("fixture-two-absent", {}).get("declared_only") == []
                and records.get("fixture-two-absent", {}).get(
                    "simulated_only") == [],
                str(records.get("fixture-two-absent")))
    suite.check("a buildable source has an empty absent set",
                all(not item.get("absent_build_dependencies")
                    for item in report["packages"]
                    if item["class"] == "buildable"),
                str([(item["package"], item.get("absent_build_dependencies"))
                     for item in report["packages"]
                     if item["class"] == "buildable"]))
    suite.check("the schedule reads the declared set rather than apt's report",
                "fixture-absent-two" in report["must_be_built_or_substituted"],
                str(report["must_be_built_or_substituted"]))
    suite.check("a positive architecture restriction admits its member",
                module.applies_to("hurd-any", "hurd-amd64")
                and module.applies_to("hurd-amd64", "hurd-amd64")
                and not module.applies_to("linux-any", "hurd-amd64"), "")
    suite.check("a negated architecture restriction admits everything else",
                module.applies_to("!linux-any", "hurd-amd64")
                and not module.applies_to("!hurd-any", "hurd-amd64"), "")
    suite.check("naming packages explicitly is not labelled with a set default",
                report["set"] == "explicit", report["set"])
    # sid and unreleased move, so an unpinned closure and the build it schedules
    # can answer against different archives.
    ports, main = module.snapshot_mirrors("20260726T003219Z")
    suite.check("a snapshot timestamp pins both archives to one state",
                ports.endswith("/debian-ports/20260726T003219Z")
                and main.endswith("/debian/20260726T003219Z"),
                "%s %s" % (ports, main))
    suite.raises("a value that is not a snapshot timestamp is refused",
                 module.ArchiveTrustError,
                 lambda: module.snapshot_mirrors("yesterday"))
    suite.check("an unpinned report says so rather than omitting the field",
                report["provenance"]["archive_snapshot"] == "",
                str(report["provenance"].get("archive_snapshot")))
    suite.check("a build dependency's version constraint is retained",
                module.unsatisfied_dependencies(
                    "a : Depends: one (>= 2) but it is not installable"
                )[0]["constraint"] == ">= 2",
                str(module.unsatisfied_dependencies(
                    "a : Depends: one (>= 2) but it is not installable")))


def test_snapshot_expiry(module, suite, workspace):
    """A pinned archive stays usable after its Release expires.

    snapshot.debian.org serves the exact bytes a timestamp named, Valid-Until
    included, so apt refuses the pinned state some weeks after it was pinned
    while the signature and the payload are unchanged. Expiry checking is
    therefore disabled for a snapshot-pinned run and left enabled for a live
    mirror, where a stale Release is a genuine freshness failure. Disabling it
    everywhere would trade the lock for the freshness check.
    """
    root = os.path.join(workspace, "ports-expired")
    mirror = ports_fixture(root, [stanza("fixture-pinned", "1.0", "hurd-amd64")])
    expire_release(root, "sid")
    expire_release(root, "unreleased")

    state = os.path.join(workspace, "state-expired-live")
    os.makedirs(state)
    suite.raises("an expired Release is refused for a live mirror",
                 module.ArchiveTrustError,
                 lambda: module.resolve(
                     Args(ports_mirror=mirror, packages=["fixture-pinned"]),
                     state))

    state = os.path.join(workspace, "state-expired-pinned")
    os.makedirs(state)
    report = module.resolve(
        Args(ports_mirror=mirror, packages=["fixture-pinned"],
             archive_snapshot="20260726T003219Z"), state)
    suite.check("the same expired Release is accepted when the run is pinned",
                verdicts(report).get("fixture-pinned") == "native",
                str(verdicts(report)))
    suite.check("a pinned report records the timestamp it answered against",
                report["provenance"]["archive_snapshot"] == "20260726T003219Z",
                str(report["provenance"]["archive_snapshot"]))


def test_installed_baseline(module, suite, workspace):
    """A seeded baseline turns availability into a claim about this image.

    Resolved against an empty status file a transaction has no installed
    package to displace, so a removal list is empty by construction and a
    report cannot say whether an install would replace part of the guest's
    userland. The status file is what makes that question answerable, and a
    status file from the wrong port would answer it wrongly while parsing.
    """
    root = os.path.join(workspace, "ports-baseline")
    mirror = ports_fixture(root, [
        stanza("fixture-installed", "2.0", "hurd-amd64"),
        stanza("fixture-replacing", "1.0", "hurd-amd64",
               conflicts="fixture-installed", replaces="fixture-installed"),
    ])

    status = os.path.join(workspace, "guest-status")
    with open(status, "w", encoding="utf-8") as handle:
        handle.write("Package: fixture-installed\n"
                     "Status: install ok installed\n"
                     "Priority: optional\n"
                     "Architecture: hurd-amd64\n"
                     "Version: 1.0\n\n")

    state = os.path.join(workspace, "state-baseline-empty")
    os.makedirs(state)
    empty = module.resolve(
        Args(ports_mirror=mirror, packages=["fixture-replacing"]), state)
    suite.check("an unseeded run names its baseline empty rather than omitting it",
                empty["provenance"]["installed_baseline"]["kind"] == "empty",
                str(empty["provenance"]["installed_baseline"]))

    state = os.path.join(workspace, "state-baseline-seeded")
    os.makedirs(state)
    seeded = module.resolve(
        Args(ports_mirror=mirror, packages=["fixture-replacing"],
             installed_status=status), state)
    baseline = seeded["provenance"]["installed_baseline"]
    suite.check("a seeded run records the guest status it answered against",
                baseline["kind"] == "guest-dpkg-status"
                and baseline["package_count"] == 1
                and len(baseline["sha256"]) == 64, str(baseline))
    removals = [item.get("removes", []) for item in seeded["packages"]]
    suite.check("a transaction that displaces an installed package says so",
                any("fixture-installed" in entry for entry in removals),
                "%s vs unseeded %s"
                % (removals, [item.get("removes", [])
                              for item in empty["packages"]]))
    suite.check("the same transaction removes nothing against an empty baseline",
                all(not item.get("removes") for item in empty["packages"]),
                str([item.get("removes") for item in empty["packages"]]))

    # A per-package removal answers what installing one member displaces. The
    # set is installed as one transaction, so what that transaction displaces is
    # a separate field, and a reader looking for "does this set replace part of
    # the userland" reads the second rather than reassembling the first.
    suite.check("the set-level transaction names what it displaces",
                "fixture-installed" in seeded["transaction_removals"],
                str(seeded["transaction_removals"]))
    suite.check("the set-level removal list is empty against an empty baseline",
                empty["transaction_removals"] == [],
                str(empty["transaction_removals"]))

    wrong = os.path.join(workspace, "guest-status-wrong-port")
    with open(wrong, "w", encoding="utf-8") as handle:
        handle.write("Package: fixture-installed\n"
                     "Status: install ok installed\n"
                     "Architecture: hurd-i386\n"
                     "Version: 1.0\n\n")
    state = os.path.join(workspace, "state-baseline-wrong")
    os.makedirs(state)
    suite.raises("a status file from the other port is refused",
                 module.ArchiveTrustError,
                 lambda: module.resolve(
                     Args(ports_mirror=mirror, packages=["fixture-replacing"],
                          installed_status=wrong), state))

    state = os.path.join(workspace, "state-baseline-absent")
    os.makedirs(state)
    suite.raises("a named status file that does not exist is refused",
                 module.ArchiveTrustError,
                 lambda: module.resolve(
                     Args(ports_mirror=mirror, packages=["fixture-replacing"],
                          installed_status=os.path.join(workspace, "absent")),
                     state))


def test_key_pin(module, suite, workspace):
    packets = module.dearmor(open(KEYRING, encoding="utf-8").read())
    suite.check("the vendored key carries the pinned primary fingerprint",
                module.primary_key_fingerprint(packets) == MINT_FINGERPRINT,
                module.primary_key_fingerprint(packets))
    suite.raises("a keyring failing the pin is rejected",
                 module.ArchiveTrustError,
                 lambda: module.trusted_keyring(
                     KEYRING, "0" * 40, workspace))


def test_signature(module, suite, workspace):
    release = os.path.join(FIXTURES, "lmde-gigi-Release")
    signature = os.path.join(FIXTURES, "lmde-gigi-Release.gpg")
    keyring, _ = module.trusted_keyring(KEYRING, MINT_FINGERPRINT, workspace)
    suite.check("the recorded Release verifies against the pinned key",
                "Good signature" in module.verify_detached(
                    keyring, signature, release))

    tampered = os.path.join(workspace, "tampered-Release")
    with open(release, "rb") as handle:
        body = handle.read()
    with open(tampered, "wb") as handle:
        handle.write(body.replace(b"Origin:", b"origin:", 1))
    suite.raises("a modified Release fails verification",
                 module.ArchiveTrustError,
                 lambda: module.verify_detached(keyring, signature, tampered))

    truncated = os.path.join(workspace, "truncated-Release.gpg")
    with open(signature, "rb") as handle:
        raw = handle.read()
    with open(truncated, "wb") as handle:
        handle.write(raw[:len(raw) // 2])
    suite.raises("a malformed signature fails verification",
                 module.ArchiveTrustError,
                 lambda: module.verify_detached(keyring, truncated, release))


def test_index_integrity(module, suite, workspace):
    root = os.path.join(workspace, "lmde-fixture")
    digest = lmde_fixture(root, "gigi", "main",
                          [stanza("fixture-mint-theme", "1.0", "all"),
                           stanza("fixture-mint-binary", "1.0", "amd64")])
    mirror = "file://%s" % root
    good = {"digests": {"main/binary-amd64/Packages.gz": (digest, 0)}}
    index, seen = module.verified_index(mirror, "gigi", "main", good)
    suite.check("a matching index is accepted and its digest reported",
                seen == digest and "fixture-mint-theme" in index, seen)
    suite.check("only the Architecture: all stanzas cross into the overlay",
                [line for line in module.arch_all_stanzas(index, mirror)
                 if "fixture-mint-binary" in line] == [],
                "an amd64 binary reached the overlay")
    suite.check("the overlay rewrites pool paths to the Mint mirror",
                all("Filename: %s/pool" % mirror in text
                    for text in module.arch_all_stanzas(index, mirror)))

    mismatched = {"digests": {"main/binary-amd64/Packages.gz": ("0" * 64, 0)}}
    suite.raises("an index the Release contradicts is rejected",
                 module.ArchiveTrustError,
                 lambda: module.verified_index(mirror, "gigi", "main",
                                               mismatched))
    suite.raises("an index the Release does not name is rejected",
                 module.ArchiveTrustError,
                 lambda: module.verified_index(mirror, "gigi", "upstream",
                                               good))

    # A malformed index that still hashes correctly passes the integrity gate,
    # so decompression is where it must fail, and it must fail as a trust error
    # rather than as a traceback from the parser.
    corrupt = os.path.join(root, "dists", "gigi", "main", "binary-amd64",
                           "Packages.gz")
    body = b"this is not a gzip member"
    with open(corrupt, "wb") as handle:
        handle.write(body)
    named = {"digests": {"main/binary-amd64/Packages.gz":
                         (hashlib.sha256(body).hexdigest(), len(body))}}
    suite.raises("a malformed index does not reach the parser",
                 module.ArchiveTrustError,
                 lambda: module.verified_index(mirror, "gigi", "main", named))


def test_overlay_preserves_versions(module, suite, workspace):
    """Deduplicating the overlay by package name would let whichever component
    is read first decide the candidate, which is not the selection apt makes."""
    root = os.path.join(workspace, "lmde-overlay")
    digests = {}
    for component, stanzas in (
            ("main", [stanza("fixture-mint-dup", "1.0", "all"),
                      stanza("fixture-mint-dup", "3.0", "all")]),
            ("upstream", [stanza("fixture-mint-dup", "2.0", "all"),
                          stanza("fixture-mint-only-upstream", "1.0", "all")]),
            ("import", [stanza("fixture-mint-import", "1.0", "all")]),
            ("backport", [stanza("fixture-mint-backport", "1.0", "all")])):
        digest = lmde_fixture(root, "gigi", component, stanzas)
        digests["%s/binary-amd64/Packages.gz" % component] = (digest, 0)

    target = os.path.join(workspace, "overlay-tree")
    os.makedirs(target)
    summary = module.write_overlay(target, "hurd-amd64", "file://%s" % root,
                                   "gigi", {"digests": digests})
    suite.check("every component contributing payloads is published",
                summary["components"] == list(module.LMDE_COMPONENTS),
                str(summary["components"]))
    suite.check("every version survives into the overlay",
                summary["architecture_all_packages"] == 6,
                str(summary["architecture_all_packages"]))

    main = os.path.join(target, "lmde", "dists", "gigi", "main",
                        "binary-hurd-amd64", "Packages")
    with open(main, encoding="utf-8") as handle:
        text = handle.read()
    suite.check("two versions of one name both reach the index",
                text.count("Package: fixture-mint-dup") == 2, text[:120])

    upstream = os.path.join(target, "lmde", "dists", "gigi", "upstream",
                            "binary-hurd-amd64", "Packages")
    suite.check("a name carried by two components keeps both provenances",
                "fixture-mint-dup" in open(upstream, encoding="utf-8").read())
    suite.check("each source index digest is reported",
                sorted(summary["source_index_sha256"]) == sorted(digests),
                str(sorted(summary["source_index_sha256"])))
    suite.check("the generated overlay carries its own digest",
                len(summary["overlay_release_sha256"]) == 64)


def test_release_parsing(module, suite):
    release = os.path.join(FIXTURES, "lmde-gigi-Release")
    with open(release, encoding="utf-8") as handle:
        text = handle.read()
    digests = module.release_digests(text)
    suite.check("every read component is named in the verified Release",
                all("%s/binary-amd64/Packages.gz" % component in digests
                    for component in module.LMDE_COMPONENTS),
                str(sorted(k for k in digests if k.endswith("Packages.gz"))[:6]))
    suite.check("only the SHA-256 section is read",
                all(len(value[0]) == 64 for value in digests.values()),
                "a shorter digest was read as SHA-256")
    suite.check("the Release codename is recorded",
                module.release_field(text, "Codename") == "gigi")


def run(module):
    suite = Suite()
    workspace = tempfile.mkdtemp(prefix="hurd-closure-selftest-")
    try:
        test_key_pin(module, suite, workspace)
        test_signature(module, suite, workspace)
        test_release_parsing(module, suite)
        test_index_integrity(module, suite, workspace)
        test_overlay_preserves_versions(module, suite, workspace)
        test_classification(module, suite, workspace)
        test_version_selection(module, suite, workspace)
        test_conflict(module, suite, workspace)
        test_wildcards(module, suite, workspace)
        test_foreign_architecture(module, suite, workspace)
        test_build_dependencies(module, suite, workspace)
        test_snapshot_expiry(module, suite, workspace)
        test_installed_baseline(module, suite, workspace)
    finally:
        shutil.rmtree(workspace, ignore_errors=True)

    print("\n%d checks passed, %d failed" % (suite.passes, len(suite.failures)))
    for failure in suite.failures:
        print("  %s" % failure)
    return 1 if suite.failures else 0


if __name__ == "__main__":
    raise SystemExit(json.dumps(
        {"error": "run through report-hurd-package-closure.py --self-test"}))
