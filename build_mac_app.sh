#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Win11ExplorerMac"
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

cp ".build/release/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp "Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"

echo "🔏 Firmando localmente la aplicación con entitlements..."
codesign --force --deep --sign - --entitlements "Resources/Win11ExplorerMac.entitlements" "${BUNDLE_DIR}"

echo "✅ ¡Listo! Aplicación creada en: ${BUNDLE_DIR}"
echo "Puedes abrirla con: open \"${BUNDLE_DIR}\""
