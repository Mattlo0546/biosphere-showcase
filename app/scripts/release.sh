#!/bin/zsh
# Publish a Biosphere release to GitHub. Her app (stable channel) or your app (beta channel) picks it up.
#
#   scripts/release.sh 0.7.1 --beta   # from dev: pre-release, only "Beta updates" users get it
#   scripts/release.sh 0.7.1          # from main: stable, everyone gets it
#
# Steps: checks the working tree is clean → makes sure the paper pack release exists → bumps VERSION,
# commits and tags vX.Y.Z → builds + signs → pushes → creates the GitHub release with Biosphere.zip.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:?usage: scripts/release.sh X.Y.Z [--beta]}
BETA=${2:-}
BRANCH=$(git rev-parse --abbrev-ref HEAD)

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must look like 1.2.3" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first." >&2; exit 1; }
if [[ "$BETA" != "--beta" && "$BRANCH" != "main" ]]; then
  echo "Stable releases come from main (you're on $BRANCH). Merge dev → main first, or add --beta." >&2; exit 1
fi
tr -d '[:space:]' < "$HOME/.biosphere-update-token" 2>/dev/null | grep -qE '^github_pat_' || { echo "~/.biosphere-update-token is missing or isn't a fine-grained GitHub token (see README › Releasing)." >&2; exit 1; }
git rev-parse "v$VERSION" >/dev/null 2>&1 && { echo "v$VERSION already exists." >&2; exit 1; }

# The paper PDFs are their own release; publish it if this version of the pack isn't up yet.
scripts/release_papers.sh

git fetch -q --tags origin
PREV=$(git describe --tags --match 'v*' --abbrev=0 2>/dev/null || true)
echo "$VERSION" > VERSION
git add VERSION
git diff --cached --quiet || git commit -q -m "Release v$VERSION"
git tag -a "v$VERSION" -m "Biosphere $VERSION"

./scripts/build_app.sh

NOTES=$(git log --pretty='- %s' ${PREV:+$PREV..}HEAD -- . ':!VERSION' | grep -v '^- Release v' | head -20 || true)
git push -q origin "$BRANCH" "v$VERSION"
gh release create "v$VERSION" dist/Biosphere.zip \
  --title "Biosphere $VERSION${BETA:+ (beta)}" \
  --notes "${NOTES:-Bug fixes and improvements.}" \
  ${BETA:+--prerelease} --verify-tag
echo "Published v$VERSION${BETA:+ (beta)}."
