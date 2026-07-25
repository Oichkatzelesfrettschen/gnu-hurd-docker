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
only the `Architecture: all` stanzas and republishes them in the target
architecture's index, so Mint supplies artwork and Debian Ports supplies every
executable. A pin keeps Debian Ports authoritative wherever both carry a name.

An `Architecture: all` metapackage names components without stating that any has
a Hurd build, so the metapackage is not evidence of readiness. This asks the
archive.

Classes:

  native            an Architecture: <target> binary exists
  architecture-all  one binary serves every architecture
  uninstallable     the package exists and its dependencies do not close
  missing           no binary for the target in any configured suite

This reads the archive as data on a Linux host. Hurd binaries cannot execute
here; docs/audits/hurd-execution-boundary-and-archive-layer.md carries that
probe.
"""

import argparse
import gzip
import io
import json
import os
import re
import subprocess
import sys
import urllib.request

PORTS = "http://ftp.ports.debian.org/debian-ports"
LMDE_MIRROR = os.environ.get(
    "LMDE_MIRROR", "http://mirrors.kernel.org/linuxmint-packages")
LMDE_SUITE = os.environ.get("LMDE_SUITE", "gigi")
# gigi advertises romeo and incoming, whose indices carry nothing for this
# purpose, so the overlay reads the components that publish payloads.
LMDE_COMPONENTS = ("main", "upstream", "import", "backport")

# The session core: what a MATE desktop needs before any recommended layer.
MATE_CORE = [
    "mate-desktop-environment-core",
    "mate-session-manager",
    "mate-settings-daemon",
    "mate-panel",
    "marco",
    "caja",
    "mate-control-center",
    "mate-terminal",
    "mate-notification-daemon",
    "mate-polkit",
    "mate-menus",
    "mate-icon-theme",
    "mate-themes",
]

# The full desktop, as a user meets it: the core plus the session pieces a
# complete experience needs.
MATE_FULL = MATE_CORE + [
    "mate-desktop-environment",
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
    "network-manager-gnome",
    "xorg",
    "xserver-xorg-video-vesa",
    "dbus-x11",
    "policykit-1-gnome",
]

# The Mint visual family, all Architecture: all, taken unmodified.
MINT_VISUAL = [
    "mint-themes",
    "mint-l-theme",
    "mint-l-icons",
    "mint-x-icons",
    "mint-y-icons",
    "mint-cursor-themes",
    "mint-artwork",
    # Mint names backgrounds per release codename rather than per suite, so the
    # set is discovered instead of guessed; a guessed name reads as a missing
    # package when it never existed.
    "mint-backgrounds-*",
    "mint-translations",
    "xapp-symbolic-icons",
    "xapps-common",
    "mintmenu",
]

SETS = {"mate-core": MATE_CORE, "mate-full": MATE_FULL,
        "mint-visual": MINT_VISUAL,
        "everything": MATE_FULL + MINT_VISUAL}


def run(argv, env=None, timeout=900):
    done = subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                          check=False, env=env)
    return done.returncode, done.stdout, done.stderr


def fetch(url):
    with urllib.request.urlopen(url, timeout=180) as response:
        return response.read()


def lmde_arch_all_stanzas():
    """Return the Architecture: all stanzas LMDE publishes, with their pool URLs
    rewritten absolute so a local index can point at the Mint mirror."""
    stanzas = []
    seen = set()
    for component in LMDE_COMPONENTS:
        url = "%s/dists/%s/%s/binary-amd64/Packages.gz" % (
            LMDE_MIRROR, LMDE_SUITE, component)
        try:
            raw = gzip.decompress(fetch(url)).decode("utf-8", "replace")
        except Exception as exc:  # noqa: BLE001 - a missing component is a fact
            print("lmde: %s unavailable (%s)" % (component, exc), file=sys.stderr)
            continue
        for stanza in raw.split("\n\n"):
            if not stanza.strip():
                continue
            if not re.search(r"^Architecture:\s*all\s*$", stanza, re.MULTILINE):
                continue
            name = re.search(r"^Package:\s*(\S+)", stanza, re.MULTILINE)
            if not name or name.group(1) in seen:
                continue
            seen.add(name.group(1))
            stanza = re.sub(r"^Filename:\s*(\S+)", lambda m:
                            "Filename: %s/%s" % (LMDE_MIRROR, m.group(1)),
                            stanza, flags=re.MULTILINE)
            stanzas.append(stanza.strip())
    return stanzas


def build_tree(root, architecture, with_lmde):
    """Create a private apt state tree whose native architecture is the target."""
    layout = ["etc/apt/apt.conf.d", "etc/apt/preferences.d", "etc/apt/trusted.gpg.d",
              "var/lib/apt/lists/partial", "var/lib/dpkg",
              "var/cache/apt/archives/partial"]
    for part in layout:
        os.makedirs(os.path.join(root, part), exist_ok=True)
    open(os.path.join(root, "var/lib/dpkg/status"), "w").close()

    keyring = "/usr/share/keyrings/debian-ports-archive-keyring.gpg"
    if os.path.exists(keyring):
        import shutil
        shutil.copy(keyring, os.path.join(root, "etc/apt/trusted.gpg.d"))

    sources = ["deb %s sid main" % PORTS, "deb %s unreleased main" % PORTS]

    lmde_count = 0
    if with_lmde:
        stanzas = lmde_arch_all_stanzas()
        lmde_count = len(stanzas)
        # Republished under the target architecture because Architecture: all is
        # valid for every architecture; the stanzas themselves are unmodified
        # apart from the absolute Filename.
        overlay = os.path.join(root, "lmde/dists/%s/main/binary-%s"
                               % (LMDE_SUITE, architecture))
        os.makedirs(overlay, exist_ok=True)
        with open(os.path.join(overlay, "Packages"), "w", encoding="utf-8") as fh:
            fh.write("\n\n".join(stanzas) + "\n")
        sources.append("deb [trusted=yes] file://%s/lmde %s main" % (root, LMDE_SUITE))
        # Debian Ports stays authoritative for any name both archives carry, so
        # Mint never supplies something the port builds natively.
        with open(os.path.join(root, "etc/apt/preferences.d/00-ports-wins"),
                  "w", encoding="utf-8") as fh:
            fh.write("Package: *\nPin: origin \"\"\nPin-Priority: 100\n\n"
                     "Package: *\nPin: release n=sid\nPin-Priority: 900\n\n"
                     "Package: *\nPin: release n=unreleased\nPin-Priority: 900\n")

    with open(os.path.join(root, "etc/apt/sources.list"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(sources) + "\n")

    config = os.path.join(root, "apt.conf")
    with open(config, "w", encoding="utf-8") as fh:
        fh.write(
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
    return config, lmde_count


def expand(env, packages):
    """Replace any trailing-* name with the packages the archive actually
    publishes under that prefix."""
    resolved = []
    for name in packages:
        if not name.endswith("*"):
            resolved.append(name)
            continue
        status, out, _ = run(["apt-cache", "pkgnames", name[:-1]], env=env)
        found = sorted(set(out.split())) if status == 0 else []
        if found:
            resolved.extend(found)
        else:
            print("no package matches %s" % name, file=sys.stderr)
    return resolved


def classify(env, package, architecture):
    status, out, _ = run(["apt-cache", "show", package], env=env)
    if status != 0 or not out.strip():
        return {"package": package, "class": "missing",
                "evidence": "no record in any configured suite"}
    architectures = re.findall(r"^Architecture:\s*(\S+)", out, re.MULTILINE)
    versions = re.findall(r"^Version:\s*(\S+)", out, re.MULTILINE)
    version = versions[0] if versions else ""
    if architecture in architectures:
        klass = "native"
    elif "all" in architectures:
        klass = "architecture-all"
    else:
        return {"package": package, "class": "missing", "version": version,
                "evidence": "record carries architectures %s"
                            % ",".join(sorted(set(architectures)))}
    sim, sim_out, sim_err = run(
        ["apt-get", "install", "-s", "-y", "--no-install-recommends", package],
        env=env)
    if sim != 0:
        return {"package": package, "class": "uninstallable", "version": version,
                "architecture_class": klass,
                "evidence": first_blocker(sim_out + sim_err)}
    return {"package": package, "class": klass, "version": version,
            "evidence": "resolves"}


def first_blocker(text):
    for line in text.splitlines():
        stripped = line.strip()
        if ("but it is not installable" in stripped
                or "none of the choices are installable" in stripped
                or stripped.startswith("E: ")):
            return stripped[:300]
    return " ".join(text.split())[:300] or "no resolver output"


def missing_dependencies(env, results):
    """Split the set into what installs today and what has to be built.

    The per-package verdicts already say which members resolve, so the
    installable subset is read from them rather than rediscovered by dropping
    members until a simulation passes.  Each failing member contributes the
    dependency name that blocked it, which is the name someone must build or
    substitute; a blocker that is itself a member of the set is reported under
    its own name.
    """
    installable, unmet = [], set()
    for item in results:
        if item["class"] in ("native", "architecture-all"):
            installable.append(item["package"])
            continue
        unmet.add(item["package"])
        for name in re.findall(r"Depends: (\S+)", item.get("evidence", "")):
            unmet.add(name)
        for name in re.findall(r"Package '(\S+)' has no installation candidate",
                               item.get("evidence", "")):
            unmet.add(name)
    return sorted(unmet), installable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--architecture", default="hurd-amd64",
                        choices=["hurd-amd64", "hurd-i386"])
    parser.add_argument("--set", default="mate-core", choices=sorted(SETS),
                        help="which package set to resolve")
    parser.add_argument("--no-lmde", action="store_true",
                        help="omit the LMDE Architecture: all overlay")
    parser.add_argument("--json", default="")
    parser.add_argument("packages", nargs="*")
    args = parser.parse_args()

    packages = args.packages or SETS[args.set]
    root = os.environ.get("HURD_APT_ROOT", "/srv/hurd-apt/%s" % args.architecture)
    os.makedirs(root, exist_ok=True)
    config, lmde_count = build_tree(root, args.architecture, not args.no_lmde)
    env = dict(os.environ, APT_CONFIG=config)

    status, _, err = run(["apt-get", "update", "-qq"], env=env)
    if status != 0:
        print("apt-get update failed: %s" % " ".join(err.split())[:400],
              file=sys.stderr)
        return 2

    packages = expand(env, packages)
    results = [classify(env, name, args.architecture) for name in packages]
    unmet, installable = missing_dependencies(env, results)
    if installable:
        final, final_out, final_err = run(
            ["apt-get", "install", "-s", "-y", "--no-install-recommends"] + installable,
            env=env)
    else:
        final, final_out, final_err = 1, "", "no member of the set installs"
    pulled = re.findall(r"^Inst (\S+)", final_out, re.MULTILINE)
    subset_blocker = "" if final == 0 else first_blocker(final_out + final_err)

    report = {
        "architecture": args.architecture,
        "set": args.set,
        "suites": ["sid", "unreleased"],
        "debian_ports": PORTS,
        "lmde": {"enabled": not args.no_lmde, "suite": LMDE_SUITE,
                 "mirror": LMDE_MIRROR,
                 "architecture_all_packages": lmde_count},
        "packages": results,
        "installable_subset": installable,
        "recursive_closure_size": len(pulled),
        "installable_subset_resolves": final == 0,
        "installable_subset_blocker": subset_blocker,
        "must_be_built_or_substituted": unmet,
        "summary": {},
    }
    for item in results:
        report["summary"][item["class"]] = report["summary"].get(item["class"], 0) + 1

    width = max(len(item["package"]) for item in results)
    print("architecture: %s   set: %s   LMDE arch:all packages: %d\n"
          % (args.architecture, args.set, lmde_count))
    for item in results:
        print("%-*s  %-18s %s" % (width, item["package"], item["class"],
                                  item.get("version", "")))
    print()
    for key in sorted(report["summary"]):
        print("%-18s %d" % (key, report["summary"][key]))
    print("\ninstallable subset: %d of %d, %s"
          % (len(installable), len(packages),
             "pulling %d packages recursively" % len(pulled) if final == 0
             else "still blocked: %s" % subset_blocker))
    if unmet:
        print("must be built or substituted (%d): %s"
              % (len(unmet), ", ".join(unmet)))

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2)
            fh.write("\n")
        print("\nreport: %s" % args.json)
    return 0


if __name__ == "__main__":
    sys.exit(main())
