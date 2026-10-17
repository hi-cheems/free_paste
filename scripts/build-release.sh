#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.deriveddata"
APP_PATH="$SCRIPT_DIR/FreePaste-Release.app"
DMG_PATH="$SCRIPT_DIR/FreePaste-Release.dmg"
SIGNING_OVERRIDES=()
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  SIGNING_OVERRIDES+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
fi
if (( $# > 0 )); then
  echo "用法：./scripts/build-release.sh" >&2
  exit 2
fi

BUILD_SETTINGS="$(xcodebuild -project "$ROOT_DIR/FreePaste/FreePaste.xcodeproj" \
  -target FreePaste -configuration Release -sdk macosx \
  "${SIGNING_OVERRIDES[@]}" -showBuildSettings -json)"
TEAM_IDENTIFIER="$(printf '%s\n' "$BUILD_SETTINGS" | \
  plutil -extract 0.buildSettings.DEVELOPMENT_TEAM raw -o - - 2>/dev/null || true)"
if [[ -z "$TEAM_IDENTIFIER" || "$TEAM_IDENTIFIER" == YOUR_TEAM_ID ]]; then
  echo "错误：请先配置 Signing.local.xcconfig 中的签名团队。" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "$SCRIPT_DIR/.FreePaste-release.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

echo "开始构建 Release..."
xcodebuild -quiet build -project "$ROOT_DIR/FreePaste/FreePaste.xcodeproj" \
  -scheme FreePaste -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" "${SIGNING_OVERRIDES[@]}" \
  "CODE_SIGN_IDENTITY=Apple Development" "ARCHS=arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  SWIFT_OPTIMIZATION_LEVEL=-O ENABLE_DEBUG_DYLIB=NO ENABLE_TESTABILITY=NO \
  ENABLE_HARDENED_RUNTIME=YES DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  "CODE_SIGN_ENTITLEMENTS=$ROOT_DIR/FreePaste/Config/FreePaste.entitlements"

ditto "$DERIVED_DATA_PATH/Build/Products/Release/FreePaste.app" "$WORK_DIR/FreePaste.app"
codesign --verify --deep --strict "$WORK_DIR/FreePaste.app"
SIGNING_INFO="$(codesign -dv --verbose=4 "$WORK_DIR/FreePaste.app" 2>&1)"
[[ "$SIGNING_INFO" == *"TeamIdentifier=$TEAM_IDENTIFIER"* ]] || { echo "错误：签名团队不一致。" >&2; exit 1; }
codesign -d --entitlements :- "$WORK_DIR/FreePaste.app" >"$WORK_DIR/entitlements.plist" 2>/dev/null
SANDBOX_ENABLED="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$WORK_DIR/entitlements.plist")"
DEBUG_ALLOWED="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$WORK_DIR/entitlements.plist" 2>/dev/null || true)"
if [[ "$SANDBOX_ENABLED" != true || "$DEBUG_ALLOWED" == true || -e "$WORK_DIR/FreePaste.app/Contents/MacOS/FreePaste.debug.dylib" ]]; then
  echo "错误：Release 的沙盒或调试权限不符合预期，未替换已有产物。" >&2
  exit 1
fi

"$SCRIPT_DIR/package-dmg.sh" "$WORK_DIR/FreePaste.app" "$WORK_DIR/FreePaste-Release.dmg"

# Replace only the separate Release outputs after successful build and packaging.
rm -rf "$APP_PATH"
mv "$WORK_DIR/FreePaste.app" "$APP_PATH"
mv -f "$WORK_DIR/FreePaste-Release.dmg" "$DMG_PATH"
echo "Release 应用：$APP_PATH"
echo "Release 安装包：$DMG_PATH"
echo "沿用本机开发签名，未执行 Apple 公证。"
