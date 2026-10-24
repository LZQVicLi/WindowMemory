#!/usr/bin/env python3
"""Extract a committed, version-specific changelog entry for a GitHub Release."""
import pathlib,re,sys
version=sys.argv[1]
text=(pathlib.Path(__file__).resolve().parent.parent/'CHANGELOG.md').read_text()
match=re.search(r'^## \['+re.escape(version)+r'\][^\n]*\n(.*?)(?=^## |\Z)',text,re.M|re.S)
if not match:raise SystemExit('Missing CHANGELOG entry for '+version)
print(match.group(1).strip())
print('\n### Download / 下载\n\n- ZIP / DMG: macOS 14+, Apple Silicon + Intel.\n- Verify the download using `shasum -a 256 -c SHA256SUMS.txt`.\n- This release is ad-hoc signed, not Apple notarized. See README for installation and permission notes.\n- Layout files and user data are never bundled with the app.')
