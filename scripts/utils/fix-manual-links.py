#!/usr/bin/env python3
"""
Fix manual review links that couldn't be automatically fixed.
These are cases where the link pattern wasn't found due to formatting issues.
"""

import json
import re
from pathlib import Path


def fix_manual_links():
    docs_root = Path("/home/eirikr/Playground/gnu-hurd-docker/docs")
    json_path = docs_root / "link-fix-data.json"

    # Load the manual review items
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    manual_items = data.get("manual_review", [])
    fixes_applied = []

    for item in manual_items:
        if item.get("reason") != "pattern_not_found":
            continue

        file_path = docs_root / item["file"]

        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()

            # The issue is that some links have the link text and URL concatenated
            # Look for the pattern where link text and URL are the same
            old_pattern = (
                f"\\[{re.escape(item['text'])}\\]\\({re.escape(item['url'])}\\)"
            )

            # Check if pattern exists
            if re.search(old_pattern, content):
                # Replace with suggested URL
                new_link = f"[{item['text']}]({item['suggested']})"
                content = re.sub(old_pattern, new_link, content)

                # Write back
                with open(file_path, "w", encoding="utf-8") as f:
                    f.write(content)

                print(f"Fixed: {item['file']} line {item['line']}")
                fixes_applied.append(item)
            else:
                print(f"Pattern still not found in {item['file']} line {item['line']}")

        except Exception as e:
            print(f"Error processing {item['file']}: {e}")

    return fixes_applied


if __name__ == "__main__":
    fixes = fix_manual_links()
    print(f"\nFixed {len(fixes)} manual review items")
