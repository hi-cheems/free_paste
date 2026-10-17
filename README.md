# FreePaste

FreePaste 是一个 macOS 原生菜单栏剪贴板工具，支持文本、图片和文件 URL，提供历史搜索、带 Key 的收藏和批量粘贴。数据保存在本机，当前没有云同步，也不记录复制内容的来源应用。

## 使用方式

启动后，FreePaste 常驻菜单栏，正常复制的内容会自动进入历史。通过菜单栏图标或快捷键打开屏幕底部的历史面板。

以下为常用操作和默认快捷键，部分绑定可在设置中调整：

| 操作 | 快捷键 |
| --- | --- |
| 显示 / 隐藏历史面板 | `Command + Shift + V` |
| 快速搜索 | 面板打开后直接输入 |
| 选择下一项 / 上一项 | `Control + F` / `Control + B` |
| 切换全部记录 / 仅收藏 | `Tab` |
| 粘贴选中记录 | `Return`，或鼠标双击条目 |
| 将选中文本以纯文本粘贴 | `Shift + Return` |
| 收藏 / 取消收藏选中记录 | `Command + D` |
| 进入搜索内容的详细编辑 | `Command + F` |
| 删除选中记录 | `Command + Backspace` |
| 开始批量收集 | `Command + Shift + C` |

默认搜索模式下不显示闪烁光标，方向键和记录导航快捷键仍用于选择历史记录。按 `Command + F` 或点击搜索框进入详细编辑后，按键优先用于文本编辑；按 `Esc` 返回默认模式，保留查询内容。默认模式下再按 `Esc` 关闭面板。

### 收藏搜索

选中记录并按 `Command + D`，填写 Key 后保存收藏。例如，将多个邮箱地址都设置为 `email`，之后搜索 `email` 就能找到这些记录。同一个 Key 可以对应多个 Value，右键菜单可修改 Key。

默认搜索包含普通历史和收藏，`Tab` 切换为仅搜索收藏，并保留当前查询。搜索同时匹配 Key 和内容，Key 命中排在仅内容命中之前；空查询按记录时间倒序显示。图片可通过手动设置的 Key 查找，不支持图片 OCR。

### 批量粘贴

在其他应用中选中第一条内容，按 `Command + Shift + C`。FreePaste 会先复制当前选区，再开启置顶浮窗；继续复制即可追加条目。不能复制有效选区时不会用旧历史代替。

浮窗可以拖动，队列支持正序 / 倒序切换和鼠标拖动排序。按 `Command + V` 逐条粘贴并移除条目，也可在浮窗内按回车或双击条目输出。队列清空后自动结束，关闭浮窗则放弃剩余队列。批量模式期间不能打开历史或收藏面板。

## 系统与权限

- 运行环境：macOS 14.6 或更高版本。
- 直接粘贴需要辅助功能授权；批量模式还需要输入监控授权，请按应用提示在系统设置中允许。
- 历史保存在本机，但数据库未加密，也不会自动识别或排除密码。可在设置中暂停记录、配置应用黑名单和历史保留策略。
- 文件条目保存文件 URL，不复制文件内容；安装包不包含开发机的剪贴板历史。

## 从源码构建

需要完整的 Xcode 和 macOS SDK，不需要安装第三方库或额外的 DMG 打包工具。开发验证环境为 Xcode 26.3，当前仅验证过 Apple Silicon；脚本按本机架构构建，不生成 Universal 应用。

下载或克隆项目后，在项目根目录执行下面的命令。

### 1. 配置自己的签名团队

在 Xcode 中配置自己的 Apple 开发账号，确保钥匙串内有该团队可用的 Apple Development 签名证书。

首次构建时，从示例创建本地配置；已有本地配置时不要覆盖：

```bash
cp FreePaste/Config/Signing.local.xcconfig.example FreePaste/Config/Signing.local.xcconfig
```

编辑新文件，将占位符替换为自己的 Team ID：

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

本地配置已被 Git 忽略，不应提交。不要将证书私钥、密码或访问令牌写进配置或公共工程。公共工程会自动读取本地配置，无须修改 `.pbxproj`。

### 2. 编译并生成安装包

```bash
./scripts/build-fixed-debug.sh
```

成功后生成两个文件，都位于脚本同级目录：

- `scripts/FreePaste.app`：应用程序。
- `scripts/FreePaste.dmg`：包含应用和 Applications 链接的安装镜像。

未配置团队或证书不可用时，需要先修复本机签名配置。脚本不会自动降级为 ad-hoc 签名。

### 3. 启动或安装

直接运行开发产物：

```bash
open scripts/FreePaste.app
```

也可退出旧应用，打开 `scripts/FreePaste.dmg`，将应用拖到 Applications，推出镜像后从 Applications 启动。不要同时运行开发目录和 Applications 中的两个副本。

当前脚本生成 Apple Development 签名的 Debug 包，不是经过 Developer ID 签名和 Apple 公证的公开发行版。公开分发需要单独准备发布构建、签名和公证，详见[开发、安装与验证](docs/development-workflow.md)。

## 运行测试

以下命令关闭测试签名，不需要本地签名配置：

```bash
xcodebuild test \
  -project FreePaste/FreePaste.xcodeproj \
  -scheme FreePaste \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .deriveddata-test \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=''
```

构建缓存统一使用 `.deriveddata/`，测试缓存和报告使用 `.deriveddata-test/`，均不进入 Git。键盘焦点、输入法、目标应用粘贴和批量交互仍需实机验证。

## 更多文档

- [文档总览](docs/README.md)
- [项目说明与功能边界](docs/project-notes.md)
- [架构说明](docs/architecture.md)
- [开发、安装与验证](docs/development-workflow.md)
- [隐私功能说明](docs/privacy-notes.md)

## 许可证

本项目采用 [MIT License](LICENSE)。
