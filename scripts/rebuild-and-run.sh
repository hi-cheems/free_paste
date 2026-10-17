#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$SCRIPT_DIR/FreePaste.app"

# 1. 退出正在运行的应用
if pgrep -x FreePaste > /dev/null 2>&1; then
  echo "正在退出 FreePaste..."
  pkill -x FreePaste
  while pgrep -x FreePaste > /dev/null 2>&1; do
    sleep 0.2
  done
  echo "已退出"
fi

# 2. 构建应用与安装镜像
echo "开始构建应用与 DMG..."
"$SCRIPT_DIR/build-fixed-debug.sh"

echo "应用与 DMG 构建完成"

# 3. 启动
echo "启动 FreePaste..."
open "$APP_PATH"
