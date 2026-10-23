#!/usr/bin/env bash
set -euo pipefail

APP_NAME="WinExplorerMac"
BUNDLE_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 Compilando ${APP_NAME} en modo Release para macOS..."
swift build -c release --disable-sandbox

echo "📦 Creando estructura de aplicación ${BUNDLE_DIR}..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

BIN_DIR="$(swift build -c release --show-bin-path)"
cp "${BIN_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp "Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

echo "🔏 Firmando localmente la aplicación con entitlements..."
codesign --force --deep --sign - --entitlements "Resources/WinExplorerMac.entitlements" "${BUNDLE_DIR}"

echo "🗜️ Generando paquete comprimido para GitHub Releases (build/${APP_NAME}-macOS.zip)..."
rm -f "build/${APP_NAME}-macOS.zip"
ditto -c -k --keepParent "${BUNDLE_DIR}" "build/${APP_NAME}-macOS.zip"

echo "💿 Creando instalador de disco macOS (build/${APP_NAME}.dmg)..."
DMG_STAGING="build/dmg_staging"
DMG_PATH="build/${APP_NAME}.dmg"
rm -rf "${DMG_STAGING}" "${DMG_PATH}"
mkdir -p "${DMG_STAGING}"
cp -R "${BUNDLE_DIR}" "${DMG_STAGING}/${APP_NAME}.app"
ln -s /Applications "${DMG_STAGING}/Applications"
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_STAGING}" -ov -format UDZO "${DMG_PATH}" >/dev/null
rm -rf "${DMG_STAGING}"

echo "✅ ¡Listo! Aplicación creada en: ${BUNDLE_DIR}"
echo "💿 Instalador DMG creado en: ${DMG_PATH}"
echo "📦 Paquete ZIP para Release en: build/${APP_NAME}-macOS.zip"
echo "Puedes abrirla con: open \"${BUNDLE_DIR}\""
