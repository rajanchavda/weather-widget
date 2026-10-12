#!/bin/bash
# build_app.sh - Package WeatherOverlay as a native macOS App Bundle & generate Cask config
#
# Usage: ./build_app.sh [version]
#
# With nothing set in the environment the app is ad-hoc signed and not notarized.
# Developer ID signing and notarization switch on through these variables:
#
#   CODESIGN_IDENTITY        Signing identity, e.g. "Developer ID Application: Name (TEAMID)".
#                            Signs with the hardened runtime and a secure timestamp.
#   NOTARY_KEY_ID            App Store Connect API key ID.
#   NOTARY_KEY_PATH          Path to that key's AuthKey_<id>.p8 file.
#   NOTARY_ISSUER_ID         Issuer ID of a team API key (leave unset for an individual key).
#   NOTARY_KEYCHAIN_PROFILE  Instead of the three NOTARY_KEY_* variables: a profile saved with
#                            `xcrun notarytool store-credentials`.
#   NOTARY_TIMEOUT           How long to wait for the notary service (default: 30m).
#
# Notarization needs CODESIGN_IDENTITY. When $GITHUB_OUTPUT is set, "notarized=true|false"
# is appended to it so the release workflow can generate the matching cask.

set -euo pipefail

VERSION=${1:-"1.0.0"}
APP_NAME="WeatherOverlay"
BUILD_DIR=".build/release"
APP_DIR="${APP_NAME}.app"
ZIP_NAME="${APP_NAME}.zip"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:-}"
NOTARY_KEY_PATH="${NOTARY_KEY_PATH:-}"
NOTARY_ISSUER_ID="${NOTARY_ISSUER_ID:-}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
NOTARY_TIMEOUT="${NOTARY_TIMEOUT:-30m}"

fail() {
    echo "Error: $*" >&2
    exit 1
}

# ditto stores symlinks as symlinks, where `zip -r` would follow them. --norsrc is required:
# without it ditto adds an AppleDouble "._*" entry for every file carrying an extended
# attribute, and unzip (which Homebrew uses) unpacks those into the bundle as real files,
# breaking the signature.
make_archive() {
    rm -f "$1"
    ditto -c -k --keepParent --norsrc "$APP_DIR" "$1"
}

# Checked before the build so that a bad configuration fails in seconds.
if [ "$CODESIGN_IDENTITY" = "-" ]; then
    CODESIGN_IDENTITY=""
fi

NOTARY_AUTH=()
if [ -n "$NOTARY_KEYCHAIN_PROFILE" ]; then
    if [ -n "${NOTARY_KEY_ID}${NOTARY_KEY_PATH}${NOTARY_ISSUER_ID}" ]; then
        fail "Set either NOTARY_KEYCHAIN_PROFILE or the NOTARY_KEY_* variables, not both."
    fi
    NOTARY_AUTH=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
elif [ -n "${NOTARY_KEY_ID}${NOTARY_KEY_PATH}${NOTARY_ISSUER_ID}" ]; then
    if [ -z "$NOTARY_KEY_ID" ] || [ -z "$NOTARY_KEY_PATH" ]; then
        fail "Notarizing with an API key needs both NOTARY_KEY_ID and NOTARY_KEY_PATH."
    fi
    if [ ! -f "$NOTARY_KEY_PATH" ]; then
        fail "NOTARY_KEY_PATH is not a file: ${NOTARY_KEY_PATH}"
    fi
    NOTARY_AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID")
    if [ -n "$NOTARY_ISSUER_ID" ]; then
        NOTARY_AUTH+=(--issuer "$NOTARY_ISSUER_ID")
    fi
fi

NOTARIZE=false
if [ "${#NOTARY_AUTH[@]}" -gt 0 ]; then
    if [ -z "$CODESIGN_IDENTITY" ]; then
        fail "Notarization credentials are set but CODESIGN_IDENTITY is not. Apple only notarizes Developer ID signed code, so an ad-hoc build cannot be submitted."
    fi
    NOTARIZE=true
fi
NOTARIZED=false

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "=== Step 1: Compiling Swift Code in Release Mode ==="
swift build -c release

echo "=== Step 2: Creating macOS App Bundle Structure ==="
# The old archive goes too, so a run that fails later cannot leave a stale one behind.
rm -rf "$APP_DIR" "$ZIP_NAME"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

echo "=== Step 3: Copying Binary & Resources ==="
cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/"
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "${APP_DIR}/Contents/Resources/"
fi

echo "=== Step 4: Generating Info.plist Metadata ==="
cat <<EOF > "${APP_DIR}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.weatheroverlay.${APP_NAME}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "=== Step 5: Signing App Bundle ==="
if [ -n "$CODESIGN_IDENTITY" ]; then
    # No entitlements: the app is not sandboxed and uses nothing the hardened runtime gates.
    # No --deep either: the bundle holds a single executable and no nested code.
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
    SIGNATURE="${CODESIGN_IDENTITY} (hardened runtime, timestamped)"
else
    codesign --force --deep --sign - "$APP_DIR"
    SIGNATURE="ad-hoc"
fi
codesign --verify --deep --strict "$APP_DIR"

if [ "$NOTARIZE" = true ]; then
    echo "=== Step 6: Notarizing ==="
    SUBMISSION_ZIP="${WORK_DIR}/submission.zip"
    NOTARY_RESULT="${WORK_DIR}/notary-result.json"
    make_archive "$SUBMISSION_ZIP"

    # Judged by the reported status, not the exit code, and without stopping here on failure,
    # so that the notary log can be fetched and printed.
    xcrun notarytool submit "$SUBMISSION_ZIP" "${NOTARY_AUTH[@]}" \
        --wait --timeout "$NOTARY_TIMEOUT" --output-format json > "$NOTARY_RESULT" || true
    SUBMISSION_ID=$(plutil -extract id raw -o - "$NOTARY_RESULT" 2>/dev/null || true)
    NOTARY_STATUS=$(plutil -extract status raw -o - "$NOTARY_RESULT" 2>/dev/null || true)

    if [ "$NOTARY_STATUS" != "Accepted" ]; then
        echo "Error: notarization did not succeed (status: ${NOTARY_STATUS:-unknown})." >&2
        cat "$NOTARY_RESULT" >&2
        if [ -n "$SUBMISSION_ID" ]; then
            echo "--- Notary log for submission ${SUBMISSION_ID} ---" >&2
            xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_AUTH[@]}" >&2 \
                || echo "(the notary log could not be fetched)" >&2
        fi
        exit 1
    fi
    echo "Notarization accepted (submission ${SUBMISSION_ID})."

    # Stapled to the .app, so the ticket travels inside the archive built in the next step.
    xcrun stapler staple "$APP_DIR"
    NOTARIZED=true
else
    echo "=== Step 6: Notarizing (skipped, no notarization credentials) ==="
fi

echo "=== Step 7: Packaging App Bundle into ZIP ==="
make_archive "$ZIP_NAME"

# Verify what users receive: the archive unpacked the way Homebrew unpacks it.
unzip -q "$ZIP_NAME" -d "${WORK_DIR}/unpacked"
codesign --verify --deep --strict "${WORK_DIR}/unpacked/${APP_DIR}"
if [ "$NOTARIZED" = true ]; then
    xcrun stapler validate "${WORK_DIR}/unpacked/${APP_DIR}"
fi

echo "=== Step 8: Computing SHA-256 Checksum ==="
SHA_VAL=$(shasum -a 256 "$ZIP_NAME" | cut -d' ' -f1)

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "notarized=${NOTARIZED}" >> "$GITHUB_OUTPUT"
fi

echo "=== Success ==="
echo "Native macOS App Bundle created: ${APP_DIR}"
echo "Distribution archive created: ${ZIP_NAME}"
echo "Signature: ${SIGNATURE}"
echo "Notarized: ${NOTARIZED}"
echo "SHA-256 Checksum: ${SHA_VAL}"
echo ""
echo "========================================================================="
echo "HOMEBREW CASK (rajanchavda/homebrew-tap, Casks/weatheroverlay.rb)."
echo "The release workflow generates and pushes this; keep the two in sync:"
echo "========================================================================="
cat <<EOF
cask "weatheroverlay" do
  version "${VERSION}"
  sha256 "${SHA_VAL}"

  url "https://github.com/rajanchavda/weather-widget/releases/download/v#{version}/${ZIP_NAME}"
  name "WeatherOverlay"
  desc "Ambient weather menu bar overlay for macOS"
  homepage "https://github.com/rajanchavda/weather-widget"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "WeatherOverlay.app"
EOF
# Gatekeeper accepts a notarized app as it is. Any other build is blocked while it carries
# the quarantine attribute, so the cask has to strip it.
if [ "$NOTARIZED" != true ]; then
    cat <<'EOF'

  postflight do
    system_command "xattr",
                   args: ["-cr", "#{appdir}/WeatherOverlay.app"]
  end
EOF
fi
cat <<'EOF'

  zap trash: "~/Library/Preferences/com.weatheroverlay.WeatherOverlay.plist"
end
EOF
echo "========================================================================="
