#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Uso: ./release_version.sh <version> [mensaje]"
    echo "Ejemplo: ./release_version.sh 1.0.0 \"Lanzamiento inicial con auto-update\""
    exit 1
fi

RAW_VER="$1"
CLEAN_VER="${RAW_VER#v}"
TAG_NAME="v${CLEAN_VER}"
RELEASE_MSG="${2:-Versión ${TAG_NAME}}"

echo "📌 Configurando versión ${CLEAN_VER} en Resources/Info.plist..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${CLEAN_VER}" Resources/Info.plist

echo "🔨 Compilando y empaquetando aplicación local..."
./build_mac_app.sh

echo "📝 Guardando cambios (incluyendo build/WinExplorerMac.dmg) en Git y creando tag ${TAG_NAME}..."
git add -A
git add -f build/WinExplorerMac.dmg
git commit -m "chore(release): ${TAG_NAME} - ${RELEASE_MSG}" || echo "ℹ️ Sin cambios nuevos por commitear."
git tag -f -a "${TAG_NAME}" -m "${RELEASE_MSG}"

echo "🚀 Subiendo rama master y tag ${TAG_NAME} a GitHub (origin)..."
git push origin master
git push origin "${TAG_NAME}" --force

echo ""
echo "✅ ¡Versión ${TAG_NAME} publicada en GitHub!"
echo "💿 Instalador DMG subido al repositorio en: build/WinExplorerMac.dmg"
echo "🔗 GitHub Actions también adjuntará el .dmg y .zip en:"
echo "   https://github.com/FizzyKey8/WinExplorerMac/releases/tag/${TAG_NAME}"
