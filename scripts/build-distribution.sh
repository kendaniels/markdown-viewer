#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MarkdownViewer"
PRODUCTS_DIR="${ROOT_DIR}/.build/apple/Products/Release"
DIST_DIR="${ROOT_DIR}/dist"
ICON_SOURCE="${ROOT_DIR}/Resources/AppIcon.icns"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
DSYM_DIR="${DIST_DIR}/${APP_NAME}.dSYM"
ZIP_PATH="${DIST_DIR}/${APP_NAME}-macOS-universal.zip"
DSYM_ZIP_PATH="${DIST_DIR}/${APP_NAME}-dSYM.zip"

BUNDLE_IDENTIFIER="${MARKDOWN_VIEWER_BUNDLE_ID:-com.example.MarkdownViewer}"
MARKETING_VERSION="${MARKDOWN_VIEWER_VERSION:-1.0.0}"
BUILD_VERSION="${MARKDOWN_VIEWER_BUILD_NUMBER:-1}"
SIGN_IDENTITY="${MARKDOWN_VIEWER_SIGN_IDENTITY:--}"

cd "${ROOT_DIR}"

echo "Building universal release binary..."
swift build -c release --arch arm64 --arch x86_64

rm -rf "${APP_DIR}" "${DSYM_DIR}" "${ZIP_PATH}" "${DSYM_ZIP_PATH}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${PRODUCTS_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp -R "${PRODUCTS_DIR}/${APP_NAME}.dSYM" "${DSYM_DIR}"

if [[ -f "${ICON_SOURCE}" ]]; then
  cp "${ICON_SOURCE}" "${RESOURCES_DIR}/AppIcon.icns"
fi

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>md</string>
                <string>markdown</string>
                <string>mdown</string>
            </array>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
        </dict>
    </array>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_IDENTIFIER}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_VERSION}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "Code signing app bundle with identity: ${SIGN_IDENTITY}"
codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_DIR}"

echo "Creating ZIP archives..."
ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${DSYM_DIR}" "${DSYM_ZIP_PATH}"

echo
echo "Distribution artifacts created:"
echo "  ${APP_DIR}"
echo "  ${ZIP_PATH}"
echo "  ${DSYM_DIR}"
echo "  ${DSYM_ZIP_PATH}"
echo
echo "Bundle identifier: ${BUNDLE_IDENTIFIER}"
echo "Version: ${MARKETING_VERSION} (${BUILD_VERSION})"
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
  echo "Signing: ad-hoc"
else
  echo "Signing identity: ${SIGN_IDENTITY}"
fi
