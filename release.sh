#!/bin/bash
# Cut a release: build the .app, zip it, publish a GitHub Release, and print the
# url + sha256 you paste into the Homebrew cask.
#
#   ./release.sh 1.0.1
#
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version>}"
REPO="sebastianbreguel/softfocus"
APP="SoftFocus.app"
ZIP="dist/SoftFocus-$VERSION.zip"

./build-app.sh
mkdir -p dist
rm -f "$ZIP"
# ditto --keepParent => the zip contains SoftFocus.app at its root (what the cask expects).
ditto -c -k --keepParent "$APP" "$ZIP"

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
URL="https://github.com/$REPO/releases/download/v$VERSION/SoftFocus-$VERSION.zip"

# Create the release if it doesn't exist, then upload (clobber to allow re-runs).
gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1 \
  || gh release create "v$VERSION" --repo "$REPO" --title "SoftFocus $VERSION" --notes "SoftFocus $VERSION"
gh release upload "v$VERSION" "$ZIP" --repo "$REPO" --clobber

echo
echo "Released v$VERSION"
echo "  url:    $URL"
echo "  sha256: $SHA"
echo "Now bump version/url/sha256 in the tap's Casks/softfocus.rb and push."
