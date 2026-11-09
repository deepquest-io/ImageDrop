#!/usr/bin/env bash
# ImageDrop by deepquest | https://deepquest.code511.com/blog
# First-time publish to GitHub: creates the repo, pushes the code and tags the
# current version, which makes GitHub Actions build and publish a Release.
#
#   bash publish.sh                 public repo named "ImageDrop"
#   bash publish.sh MyRepoName      custom repo name
#   VISIBILITY=private bash publish.sh
set -euo pipefail
cd "$(dirname "$0")"

REPO_NAME="${1:-ImageDrop}"
VISIBILITY="${VISIBILITY:-public}"
VERSION="$(tr -d '[:space:]' < VERSION)"
DESCRIPTION="Native macOS drag-and-drop image converter. WebP (small size, high quality), JPEG, PNG, HEIC, AVIF, TIFF, GIF, BMP."

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI not found. Install it with:  brew install gh"
  echo "(no Homebrew? see https://cli.github.com)"
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "▸ Logging in to GitHub…"
  gh auth login --hostname github.com --git-protocol https --web
fi

OWNER="$(gh api user -q .login)"
FULL="$OWNER/$REPO_NAME"
echo "▸ Publishing ImageDrop v$VERSION to github.com/$FULL ($VISIBILITY)"

# Fill in the repo name used by the README badges and links.
if grep -q "__GITHUB_REPO__" README.md; then
  sed -i '' "s#__GITHUB_REPO__#$FULL#g" README.md
fi

# Local git repository.
if [ ! -d .git ]; then
  git init -b main >/dev/null
fi
git add -A
if ! git diff --cached --quiet; then
  git commit -m "ImageDrop v$VERSION" >/dev/null
fi
git branch -M main

# Remote repository.
if gh repo view "$FULL" >/dev/null 2>&1; then
  echo "▸ Repo already exists, pushing to it"
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$FULL.git"
  git push -u origin main
else
  gh repo create "$FULL" --"$VISIBILITY" --source=. --remote=origin --push \
    --description "$DESCRIPTION" --homepage "https://deepquest.code511.com/blog"
fi

gh repo edit "$FULL" --add-topic macos,swift,swiftui,webp,image-converter,drag-and-drop,heic,avif,libwebp >/dev/null || true

# Tag the version, which triggers the Release build.
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  echo "▸ Tag v$VERSION already exists locally"
else
  git tag -a "v$VERSION" -m "ImageDrop v$VERSION"
fi
git push origin "v$VERSION"

echo
echo "✓ Published: https://github.com/$FULL"
echo "  Build progress: https://github.com/$FULL/actions"
echo "  The Release with the ready-to-use app appears in ~5 min: https://github.com/$FULL/releases"
