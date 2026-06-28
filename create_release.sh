#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: ./create_release.sh <version>"
    echo "Example: ./create_release.sh 1.0.1"
    exit 1
fi

VERSION=$1
CLEAN_VERSION="${VERSION#v}"
TAG_NAME="v${CLEAN_VERSION}"

# Validate we're on main
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
    echo "Error: Releases must be created from the 'main' branch (currently on '$BRANCH')."
    echo "Switch to main, merge your changes, then re-run this script."
    exit 1
fi

# Ensure working tree is clean
if [ -n "$(git status --porcelain)" ]; then
    echo "Error: Working tree is not clean. Commit or stash changes first."
    exit 1
fi

echo "Creating tag ${TAG_NAME} on main..."
git tag -a "$TAG_NAME" -m "Release $TAG_NAME"
git push origin "$TAG_NAME"

echo "========================================================"
echo "Tag $TAG_NAME pushed to origin."
echo "GitHub Actions will now build the app and create the release."
echo "Monitor progress at: https://github.com/$(git remote get-url origin | sed 's/.*:\(.*\)\.git/\1/')/actions"
echo "========================================================"
