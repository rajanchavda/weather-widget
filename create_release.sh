#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: ./create_release.sh <version>"
    echo "Example: ./create_release.sh 1.0.1"
    exit 1
fi

VERSION=$1

# Strip 'v' if user provided it to keep tag formatting clean
CLEAN_VERSION="${VERSION#v}"
TAG_NAME="v${CLEAN_VERSION}"

echo "Building the app and creating zip for version $CLEAN_VERSION..."
./build_app.sh "$CLEAN_VERSION"

echo "Adding built artifacts to git..."
git add WeatherOverlay.zip WeatherOverlay.app

echo "Committing to git..."
# using || true because if there's no change, commit would return non-zero
git commit -m "Release $TAG_NAME" || echo "No changes to commit."

echo "Creating tag ${TAG_NAME}..."
# In case the tag already exists, delete it first locally
if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
    echo "Tag $TAG_NAME already exists locally, deleting..."
    git tag -d "$TAG_NAME"
fi

git tag -a "$TAG_NAME" -m "Release $TAG_NAME"

echo "Pushing changes and tag to remote..."
git push origin main || echo "Failed to push to main, continuing anyway..."

# Push the tag (use -f in case it was deleted and recreated)
git push origin "$TAG_NAME" -f

echo "========================================================"
echo "Release $TAG_NAME successfully created and pushed!"
echo "========================================================"
