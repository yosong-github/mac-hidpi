#!/bin/bash
# Tag vMAJOR.MINOR.PATCH and push it. The tag push runs the release workflow.
# Usage: scripts/cut-release.sh 1.2.3
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"
cd "$ROOT"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: scripts/cut-release.sh 1.2.3" >&2
  exit 1
fi
validate_version "$VERSION"
TAG="v${VERSION}"

if git rev-parse --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
  echo "Tag ${TAG} already exists." >&2
  exit 1
fi

git tag -a "$TAG" -m "HiDPI ${VERSION}"
git push origin "$TAG"
echo "Pushed ${TAG}. GitHub Actions will build the app, attach the dmg and zip, and publish the release."
