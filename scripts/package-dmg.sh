#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: package-dmg.sh [app_path [dmg_path]]"
  echo "Defaults: $SCRIPT_DIR/FreePaste.app -> $SCRIPT_DIR/FreePaste.dmg"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi
if (( $# > 2 )); then
  usage >&2
  exit 2
fi

APP_PATH="${1:-$SCRIPT_DIR/FreePaste.app}"
DMG_PATH="${2:-$SCRIPT_DIR/FreePaste.dmg}"

if [[ ! -d "$APP_PATH" || ! -f "$APP_PATH/Contents/Info.plist" ]]; then
  echo "错误：找不到有效的应用包：$APP_PATH" >&2
  exit 1
fi
if [[ "$DMG_PATH" != *.dmg || ( -e "$DMG_PATH" && ! -f "$DMG_PATH" ) ]]; then
  echo "错误：输出路径必须是 .dmg 文件：$DMG_PATH" >&2
  exit 2
fi

codesign --verify --deep --strict "$APP_PATH"

OUTPUT_DIR="$(dirname "$DMG_PATH")"
mkdir -p "$OUTPUT_DIR"
WORK_DIR="$(mktemp -d "$OUTPUT_DIR/.FreePaste-dmg.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

STAGING_DIR="$WORK_DIR/staging"
mkdir -p "$STAGING_DIR"
ditto "$APP_PATH" "$STAGING_DIR/FreePaste.app"
ln -s /Applications "$STAGING_DIR/Applications"
codesign --verify --deep --strict "$STAGING_DIR/FreePaste.app"

hdiutil create \
  -volname FreePaste \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDZO \
  "$WORK_DIR/FreePaste.dmg"

hdiutil verify "$WORK_DIR/FreePaste.dmg"

# Publish only after verification, so a failed build keeps the last usable installer.
mv -f "$WORK_DIR/FreePaste.dmg" "$DMG_PATH"
echo "安装镜像：$DMG_PATH"
