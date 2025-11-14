#!/usr/bin/env python3
"""
Fix remaining broken links, especially case-sensitive issues.
"""

import re
from pathlib import Path


def fix_case_sensitive_links():
    docs_root = Path("/home/eirikr/Playground/gnu-hurd-docker/docs")

    fixes_to_apply = [
        # Fix INDEX.md case issues
        ("01-GETTING-STARTED/requirements.md", "01-GETTING-STARTED/REQUIREMENTS.md"),
        ("01-GETTING-STARTED/installation.md", "01-GETTING-STARTED/INSTALLATION.md"),
        ("01-GETTING-STARTED/quickstart.md", "01-GETTING-STARTED/QUICKSTART.md"),

        # Fix other common lowercase issues
        ("02-ARCHITECTURE/qemu-configuration.md", "02-ARCHITECTURE/QEMU-CONFIGURATION.md"),
        ("02-ARCHITECTURE/control-plane.md", "02-ARCHITECTURE/CONTROL-PLANE.md"),
        ("02-ARCHITECTURE/system-overview.md", "02-ARCHITECTURE/OVERVIEW.md"),

        ("03-CONFIGURATION/port-forwarding.md", "03-CONFIGURATION/PORT-FORWARDING.md"),
        ("03-CONFIGURATION/custom-features.md", "03-CONFIGURATION/CUSTOM-FEATURES.md"),
        ("03-CONFIGURATION/user-setup.md", "03-CONFIGURATION/USER-CONFIGURATION.md"),

        ("04-OPERATION/deployment.md", "04-OPERATION/deployment/DEPLOYMENT.md"),
        ("04-OPERATION/monitoring.md", "04-OPERATION/MONITORING.md"),
        ("04-OPERATION/interactive-access.md", "04-OPERATION/INTERACTIVE-ACCESS.md"),

        ("05-CI-CD/workflows.md", "05-CI-CD/WORKFLOWS.md"),
        ("05-CI-CD/docker-compose-guide.md", "05-CI-CD/DOCKER-COMPOSE-GUIDE.md"),

        ("06-TROUBLESHOOTING/common-issues.md", "06-TROUBLESHOOTING/COMMON-ISSUES.md"),
        ("06-TROUBLESHOOTING/ssh-problems.md", "06-TROUBLESHOOTING/SSH-ISSUES.md"),
        ("06-TROUBLESHOOTING/filesystem-issues.md", "06-TROUBLESHOOTING/FSCK-ERRORS.md"),

        ("07-RESEARCH-AND-LESSONS/findings.md", "07-RESEARCH-AND-LESSONS/FINDINGS.md"),

        ("08-REFERENCE/quick-reference.md", "08-REFERENCE/QUICK-REFERENCE.md"),
        ("08-REFERENCE/scripts.md", "08-REFERENCE/SCRIPTS.md"),
        ("08-REFERENCE/checklists.md", "08-REFERENCE/checklists/X86_64-VALIDATION.md"),
    ]

    # Process INDEX.md file specifically
    index_file = docs_root / "INDEX.md"

    try:
        with open(index_file, 'r', encoding='utf-8') as f:
            content = f.read()

        changes_made = False
        for old_path, new_path in fixes_to_apply:
            # Look for links to old path
            pattern = f"\\[([^\\]]+)\\]\\({re.escape(old_path)}\\)"
            if re.search(pattern, content):
                content = re.sub(pattern, f"[\\1]({new_path})", content)
                changes_made = True
                print(f"Fixed: {old_path} -> {new_path}")

        if changes_made:
            with open(index_file, 'w', encoding='utf-8') as f:
                f.write(content)
            print(f"Updated: {index_file}")

    except Exception as e:
        print(f"Error processing INDEX.md: {e}")

    # Fix missing/renamed files
    file_mappings = {
        "USER-SETUP.md": "03-CONFIGURATION/user/SETUP.md",
        "docs/USER-SETUP.md": "03-CONFIGURATION/user/SETUP.md",
        "docs/ARCHITECTURE.md": "02-ARCHITECTURE/SYSTEM-DESIGN.md",
        "docs/TROUBLESHOOTING.md": "06-TROUBLESHOOTING/GENERAL.md",
        "docs/RESEARCH-FINDINGS.md": "07-RESEARCH-AND-LESSONS/FINDINGS.md",
        "docs/KERNEL-STANDARDIZATION-PLAN.md": "07-RESEARCH-AND-LESSONS/KERNEL-STANDARDIZATION.md",
    }

    # Process all markdown files for these mappings
    for md_file in docs_root.rglob("*.md"):
        try:
            with open(md_file, 'r', encoding='utf-8') as f:
                original_content = f.read()

            content = original_content
            changes_made = False

            for old_path, new_path in file_mappings.items():
                # Calculate relative path from current file to new target
                source_dir = md_file.parent
                new_abs_path = docs_root / new_path

                if new_abs_path.exists():
                    try:
                        new_rel_path = (
                            new_abs_path.relative_to(source_dir).as_posix()
                        )
                    except ValueError:
                        # Need to go up directories
                        new_rel_path = (
                            '../' * (
                                len(source_dir.relative_to(docs_root).parts)
                            ) + new_path
                        )

                    # Replace old path references
                    pattern = f"\\[([^\\]]+)\\]\\({re.escape(old_path)}\\)"
                    if re.search(pattern, content):
                        content = re.sub(
                            pattern, f"[\\1]({new_rel_path})", content
                        )
                        changes_made = True
                        fixed_path = md_file.relative_to(docs_root)
                        print(f"Fixed in {fixed_path}: {old_path} -> "
                              f"{new_rel_path}")

            if changes_made:
                with open(md_file, 'w', encoding='utf-8') as f:
                    f.write(content)

        except Exception as e:
            print(f"Error processing {md_file}: {e}")


if __name__ == "__main__":
    print("Fixing remaining broken links...")
    fix_case_sensitive_links()
    print("\nDone!")
