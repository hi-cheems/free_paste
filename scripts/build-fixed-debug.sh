#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.deriveddata"
BUILT_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/FreePaste.app"
APP_PATH="$SCRIPT_DIR/FreePaste.app"
SIGNING_OVERRIDES=()
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  SIGNING_OVERRIDES+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
fi

BUILD_SETTINGS="$(xcodebuild \
  -project "$ROOT_DIR/FreePaste/FreePaste.xcodeproj" \
  -target FreePaste \
  -configuration Debug \
  -sdk macosx \
  "${SIGNING_OVERRIDES[@]}" \
  -showBuildSettings -json)"
EXPECTED_TEAM_IDENTIFIER="$(printf '%s\n' "$BUILD_SETTINGS" | \
  /usr/bin/plutil -extract 0.buildSettings.DEVELOPMENT_TEAM raw -o - - 2>/dev/null || true)"

if [[ -z "$EXPECTED_TEAM_IDENTIFIER" || "$EXPECTED_TEAM_IDENTIFIER" == "YOUR_TEAM_ID" ]]; then
  echo "错误：尚未配置签名团队，未构建或替换已有产物。" >&2
  echo "请将 FreePaste/Config/Signing.local.xcconfig.example 复制为 Signing.local.xcconfig，填写自己的 Team ID。" >&2
  echo "也可通过 DEVELOPMENT_TEAM 环境变量传入团队；详见 docs/development-workflow.md。" >&2
  exit 1
fi

xcodebuild build \
  -project "$ROOT_DIR/FreePaste/FreePaste.xcodeproj" \
  -scheme FreePaste \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  "${SIGNING_OVERRIDES[@]}"

rm -rf "$APP_PATH"
ditto "$BUILT_APP_PATH" "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH"
SIGNING_INFO="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
if [[ "$SIGNING_INFO" != *"TeamIdentifier=$EXPECTED_TEAM_IDENTIFIER"* ]]; then
  echo "错误：构建产物签名团队与本次构建配置不一致。" >&2
  echo "请检查本地签名配置与可用证书后重试。" >&2
  exit 1
fi

echo "签名团队：$EXPECTED_TEAM_IDENTIFIER"
echo "构建产物：$APP_PATH"
"$SCRIPT_DIR/package-dmg.sh" "$APP_PATH" "$SCRIPT_DIR/FreePaste.dmg"
