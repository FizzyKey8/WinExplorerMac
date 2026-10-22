#!/usr/bin/env bash
set -euo pipefail

APP_NAME="WinExplorerMac"
BUNDLE_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 Compilando ${APP_NAME} en modo Release para macOS..."
swift build -c release

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

echo "✅ ¡Listo! Aplicación creada en: ${BUNDLE_DIR}"
echo "📦 Paquete para Release listo en: build/${APP_NAME}-macOS.zip"
echo "Puedes abrirla con: open \"${BUNDLE_DIR}\""
