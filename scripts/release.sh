#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
VERSION="$(<VERSION)"
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit all changes before releasing.' >&2; exit 1; }
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo 'VERSION must be x.y.z.' >&2; exit 1; }
git rev-parse "v$VERSION" >/dev/null 2>&1 && { echo 'Version tag already exists. Bump VERSION and CHANGELOG first.' >&2; exit 1; }
python3 scripts/release-notes.py "$VERSION" >/dev/null
zsh build.sh
zsh scripts/package.sh
git tag -a "v$VERSION" -m "WindowMemory $VERSION"
git push origin main
git push origin "v$VERSION"
echo "GitHub Actions will publish the versioned ZIP, DMG and checksums."
