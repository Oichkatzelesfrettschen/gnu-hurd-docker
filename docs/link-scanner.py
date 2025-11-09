#!/usr/bin/env python3
"""
Link Scanner and Fixer for Consolidated Documentation
Scans all markdown files for internal links and fixes broken references.
"""

import os
import re
import json
from pathlib import Path
from typing import Dict, List, Tuple, Set
from collections import defaultdict

class LinkScanner:
    def __init__(self, docs_root: Path):
        self.docs_root = docs_root
        self.all_md_files = set()
        self.link_report = defaultdict(list)
        self.fixes_applied = []
        self.manual_review = []

    def scan_files(self):
        """Build index of all markdown files"""
        for file_path in self.docs_root.rglob("*.md"):
            # Store relative path from docs root
            rel_path = file_path.relative_to(self.docs_root)
            self.all_md_files.add(str(rel_path))

    def extract_links(self, content: str, file_path: Path) -> List[Tuple[str, str, int]]:
        """Extract markdown links from content
        Returns: List of (link_text, link_url, line_number)
        """
        links = []
        # Match markdown links [text](url)
        pattern = r'\[([^\]]+)\]\(([^\)]+)\)'

        lines = content.split('\n')
        for line_num, line in enumerate(lines, 1):
            for match in re.finditer(pattern, line):
                link_text = match.group(1)
                link_url = match.group(2)
                links.append((link_text, link_url, line_num))

        return links

    def is_internal_link(self, url: str) -> bool:
        """Check if link is internal (not http/https/ftp)"""
        if url.startswith(('http://', 'https://', 'ftp://', 'mailto:', '#')):
            return False
        return True

    def resolve_link_path(self, link_url: str, source_file: Path) -> Path:
        """Resolve relative link to absolute path"""
        # Remove anchor fragments
        if '#' in link_url:
            link_url = link_url.split('#')[0]

        if not link_url:
            return None

        # Handle absolute paths within docs
        if link_url.startswith('/'):
            # Assume it's from docs root
            return self.docs_root / link_url.lstrip('/')

        # Relative path from source file's directory
        source_dir = source_file.parent
        return (source_dir / link_url).resolve()

    def find_file_new_location(self, old_path: str) -> str:
        """Try to find where a file was moved to"""
        # Get just the filename
        filename = os.path.basename(old_path)

        # Search for files with same name
        candidates = []
        for md_file in self.all_md_files:
            if os.path.basename(md_file) == filename:
                candidates.append(md_file)

        # If exactly one match, return it
        if len(candidates) == 1:
            return candidates[0]

        # If multiple matches, try to find best match based on path similarity
        if len(candidates) > 1:
            # Look for similar path patterns
            old_parts = old_path.split('/')
            best_match = None
            best_score = 0

            for candidate in candidates:
                cand_parts = candidate.split('/')
                # Score based on common path elements
                score = len(set(old_parts) & set(cand_parts))
                if score > best_score:
                    best_score = score
                    best_match = candidate

            if best_match:
                return best_match

        return None

    def scan_and_fix(self):
        """Main scanning and fixing logic"""
        self.scan_files()

        total_links = 0
        broken_links = 0
        fixed_links = 0

        # Process each markdown file
        for md_file in sorted(self.all_md_files):
            file_path = self.docs_root / md_file

            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    original_content = f.read()
            except Exception as e:
                print(f"Error reading {md_file}: {e}")
                continue

            links = self.extract_links(original_content, file_path)
            if not links:
                continue

            modified_content = original_content
            file_has_changes = False

            for link_text, link_url, line_num in links:
                if not self.is_internal_link(link_url):
                    continue

                total_links += 1

                # Resolve the link path
                resolved_path = self.resolve_link_path(link_url, file_path)
                if not resolved_path:
                    continue

                # Check if file exists
                if resolved_path.exists():
                    self.link_report['valid'].append({
                        'file': str(md_file),
                        'line': line_num,
                        'text': link_text,
                        'url': link_url
                    })
                else:
                    broken_links += 1

                    # Try to find new location
                    # Convert resolved path back to relative from docs root
                    try:
                        rel_from_docs = resolved_path.relative_to(self.docs_root)
                    except ValueError:
                        # Path is outside docs root
                        self.link_report['broken'].append({
                            'file': str(md_file),
                            'line': line_num,
                            'text': link_text,
                            'url': link_url,
                            'reason': 'outside_docs_root'
                        })
                        continue

                    new_location = self.find_file_new_location(str(rel_from_docs))

                    if new_location:
                        # Calculate new relative path from source file
                        source_dir = file_path.parent
                        new_abs_path = self.docs_root / new_location
                        try:
                            new_rel_path = os.path.relpath(new_abs_path, source_dir)
                            # Use forward slashes for consistency
                            new_rel_path = new_rel_path.replace('\\', '/')

                            # Replace in content
                            old_link = f'[{link_text}]({link_url})'
                            new_link = f'[{link_text}]({new_rel_path})'

                            if old_link in modified_content:
                                modified_content = modified_content.replace(old_link, new_link)
                                file_has_changes = True
                                fixed_links += 1

                                self.fixes_applied.append({
                                    'file': str(md_file),
                                    'line': line_num,
                                    'text': link_text,
                                    'old_url': link_url,
                                    'new_url': new_rel_path
                                })
                            else:
                                self.manual_review.append({
                                    'file': str(md_file),
                                    'line': line_num,
                                    'text': link_text,
                                    'url': link_url,
                                    'suggested': new_rel_path,
                                    'reason': 'pattern_not_found'
                                })
                        except Exception as e:
                            self.manual_review.append({
                                'file': str(md_file),
                                'line': line_num,
                                'text': link_text,
                                'url': link_url,
                                'reason': f'path_calculation_error: {e}'
                            })
                    else:
                        self.link_report['broken'].append({
                            'file': str(md_file),
                            'line': line_num,
                            'text': link_text,
                            'url': link_url,
                            'reason': 'file_not_found'
                        })

            # Write back modified content if changes were made
            if file_has_changes:
                try:
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.write(modified_content)
                    print(f"Fixed links in: {md_file}")
                except Exception as e:
                    print(f"Error writing {md_file}: {e}")

        return total_links, broken_links, fixed_links

    def generate_report(self, total_links: int, broken_links: int, fixed_links: int) -> str:
        """Generate markdown report"""
        report = []
        report.append("# Link Fix Report")
        report.append(f"\nGenerated: {Path.cwd()}")
        report.append("\n## Summary Statistics\n")
        report.append(f"- Total internal links scanned: {total_links}")
        report.append(f"- Broken links found: {broken_links}")
        report.append(f"- Links automatically fixed: {fixed_links}")
        report.append(f"- Links needing manual review: {len(self.manual_review)}")
        report.append(f"- Valid links confirmed: {len(self.link_report['valid'])}")

        # Fixed links section
        if self.fixes_applied:
            report.append("\n## Successfully Fixed Links\n")
            current_file = None
            for fix in sorted(self.fixes_applied, key=lambda x: (x['file'], x['line'])):
                if current_file != fix['file']:
                    current_file = fix['file']
                    report.append(f"\n### {current_file}\n")
                report.append(f"- Line {fix['line']}: `[{fix['text']}]`")
                report.append(f"  - Old: `{fix['old_url']}`")
                report.append(f"  - New: `{fix['new_url']}`")

        # Manual review section
        if self.manual_review:
            report.append("\n## Links Requiring Manual Review\n")
            current_file = None
            for item in sorted(self.manual_review, key=lambda x: (x['file'], x['line'])):
                if current_file != item['file']:
                    current_file = item['file']
                    report.append(f"\n### {current_file}\n")
                report.append(f"- Line {item['line']}: `[{item['text']}]({item['url']})`")
                report.append(f"  - Reason: {item.get('reason', 'unknown')}")
                if 'suggested' in item:
                    report.append(f"  - Suggested: `{item['suggested']}`")

        # Still broken links
        if self.link_report['broken']:
            report.append("\n## Remaining Broken Links\n")
            current_file = None
            for item in sorted(self.link_report['broken'], key=lambda x: (x['file'], x['line'])):
                if current_file != item['file']:
                    current_file = item['file']
                    report.append(f"\n### {current_file}\n")
                report.append(f"- Line {item['line']}: `[{item['text']}]({item['url']})`")
                report.append(f"  - Reason: {item.get('reason', 'unknown')}")

        # Example fixes
        if self.fixes_applied:
            report.append("\n## Before/After Examples\n")
            for i, fix in enumerate(self.fixes_applied[:5], 1):  # Show first 5 examples
                report.append(f"\n### Example {i}")
                report.append(f"**File:** `{fix['file']}` (Line {fix['line']})")
                report.append(f"\n**Before:**")
                report.append(f"```markdown")
                report.append(f"[{fix['text']}]({fix['old_url']})")
                report.append(f"```")
                report.append(f"\n**After:**")
                report.append(f"```markdown")
                report.append(f"[{fix['text']}]({fix['new_url']})")
                report.append(f"```")

        return "\n".join(report)


def main():
    docs_root = Path("/home/eirikr/Playground/gnu-hurd-docker/docs")
    scanner = LinkScanner(docs_root)

    print("Starting link scan and fix process...")
    print(f"Scanning directory: {docs_root}")

    total, broken, fixed = scanner.scan_and_fix()

    print(f"\nScan complete:")
    print(f"  Total internal links: {total}")
    print(f"  Broken links found: {broken}")
    print(f"  Links fixed: {fixed}")
    print(f"  Manual review needed: {len(scanner.manual_review)}")

    # Generate and save report
    report = scanner.generate_report(total, broken, fixed)
    report_path = docs_root / "LINK-FIX-REPORT.md"

    with open(report_path, 'w', encoding='utf-8') as f:
        f.write(report)

    print(f"\nReport saved to: {report_path}")

    # Also save JSON data for further processing if needed
    json_data = {
        'summary': {
            'total_links': total,
            'broken_links': broken,
            'fixed_links': fixed,
            'manual_review': len(scanner.manual_review)
        },
        'fixes_applied': scanner.fixes_applied,
        'manual_review': scanner.manual_review,
        'broken_links': scanner.link_report['broken']
    }

    json_path = docs_root / "link-fix-data.json"
    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(json_data, f, indent=2)

    print(f"JSON data saved to: {json_path}")


if __name__ == "__main__":
    main()