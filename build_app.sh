#!/bin/bash
# build_app.sh - Package WeatherOverlay as a native macOS App Bundle & generate Cask config

set -e

VERSION=${1:-"1.0.0"}
APP_NAME="WeatherOverlay"
BUILD_DIR=".build/release"
APP_DIR="${APP_NAME}.app"
ZIP_NAME="${APP_NAME}.zip"

echo "=== Step 1: Compiling Swift Code in Release Mode ==="
swift build -c release

echo "=== Step 2: Creating macOS App Bundle Structure ==="
rm -rf "$APP_DIR"
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

echo "=== Step 5: Packaging App Bundle into ZIP ==="
codesign --force --deep --sign - "$APP_DIR"
rm -f "$ZIP_NAME"
zip -q -r "$ZIP_NAME" "$APP_DIR"

echo "=== Step 6: Computing SHA-256 Checksum ==="
SHA_VAL=$(shasum -a 256 "$ZIP_NAME" | cut -d' ' -f1)

echo "=== Success ==="
echo "Native macOS App Bundle created: ${APP_DIR}"
echo "Distribution archive created: ${ZIP_NAME}"
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

  postflight do
    system_command "xattr",
                   args: ["-cr", "#{appdir}/WeatherOverlay.app"]
  end

  zap trash: "~/Library/Preferences/com.weatheroverlay.WeatherOverlay.plist"
end
EOF
echo "========================================================================="
