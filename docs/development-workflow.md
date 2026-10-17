# FreePaste 开发、安装与验证

> 最后更新：2026-10-17
> 命令从仓库根目录执行。构建脚本自行解析路径，不依赖调用时的工作目录。

## 环境与产物

- 需要 macOS、Xcode 和已有的 Apple Development 签名证书。
- 应用最低部署版本为 macOS 14.6；Debug 构建面向当前机器架构。本机验证的产物为 `arm64`，不是 Universal 二进制。
- 开发中间文件固定在 `.deriveddata/`，测试中间文件固定在 `.deriveddata-test/`。
- 构建同时生成 `scripts/FreePaste.app` 和 `scripts/FreePaste.dmg`，两者均不进入 Git。
- DMG 使用系统自带的 `hdiutil` 打包，不需要 Homebrew 或第三方打包工具。
- 当前是 Apple Development 签名的 Debug 安装包，不是经过 Developer ID 签名、公证的公开发行版。DMG 不会自动改变这一点。

上述是原 Debug 入口的行为。现已新增 `./scripts/build-release.sh`，生成独立的优化 Release：`scripts/FreePaste-Release.app` 和 `scripts/FreePaste-Release.dmg`，不替换 Debug。构建与切换使用见 [Release 构建](releasing.md)。`rebuild-and-run.sh` 仍是原 Debug 调试入口，不会自动切换或安装 Release。

构建与测试请复用上述两个固定缓存目录，不要为每轮验证创建新的 `.deriveddata-*` 目录。旧的独立构建目录可在确认没有相关编译、测试或应用运行后删除；其中的中间文件、模块缓存和索引可以重新生成，不需要删除源码、签名配置或 `scripts/` 中的安装包。

## 本机签名配置

公共工程不包含固定开发团队。Debug、Release 和测试目标共同继承 `FreePaste/Config/Signing.xcconfig`，它可选加载同目录的 `Signing.local.xcconfig`；本地文件由 Git 忽略，不作为应用资源打包。

首次进行签名构建前：

```bash
cp FreePaste/Config/Signing.local.xcconfig.example FreePaste/Config/Signing.local.xcconfig
```

在本地文件中将 `YOUR_TEAM_ID` 替换为自己的 Apple 开发团队 ID。不要修改公共 `.pbxproj` 写入个人团队，也不要将证书私钥、公证密码或 API 密钥写入配置文件；这些凭据继续保存在钥匙串或专用凭据管理中。

也可以仅为一次脚本构建传入团队：

```bash
DEVELOPMENT_TEAM=YOUR_TEAM_ID ./scripts/build-fixed-debug.sh
```

脚本将该值作为 Xcode 命令行构建设置传入，覆盖本地配置，并验证最终产物来自同一团队。未配置团队时会在实际编译、替换产物之前退出，提示如何配置，不会自动改用 ad-hoc 签名。

从 Xcode 直接构建时同样读取本地配置。没有签名证书时仍可按下文关闭签名运行测试。Bundle ID 是公开的应用标识，不是凭据；保持现有值以避免影响本机历史数据和授权身份。

配置分层和可选 include 机制见 [Apple 构建配置说明](https://developer.apple.com/documentation/xcode/adding-a-build-configuration-file-to-your-project)。

## 构建与打包

### 构建应用和 DMG

```bash
./scripts/build-fixed-debug.sh
```

脚本依次执行：

1. 读取 Xcode 最终生效的签名团队，再用相同配置构建 Debug 应用。
2. 用 `ditto` 发布 `.app` 到脚本目录。
3. 验证应用签名，并确认团队与本次构建设置一致。
4. 调用 `package-dmg.sh`，将应用和指向 `/Applications` 的链接放入只读压缩 DMG。
5. 验证 DMG 校验和，成功后才替换同名安装包。

DMG 打包失败不会覆盖上一次成功的 DMG。应用构建阶段已经完成时，新的 `.app` 仍然保留，便于排查打包问题。

### 单独打包已有应用

不需要重新编译时：

```bash
./scripts/package-dmg.sh
```

也可指定输入和输出，例如给另行构建的 Release 应用打包：

```bash
./scripts/package-dmg.sh "/path/to/FreePaste.app" "/path/to/FreePaste.dmg"
```

输入必须是可通过 `codesign --verify --deep --strict` 的应用包。脚本保留输入应用的签名，不进行重新签名或公证；包含空格的路径需要加引号。

### 重建并运行

```bash
./scripts/rebuild-and-run.sh
```

该脚本退出正在运行的 FreePaste，重新生成 `.app` 和 DMG，然后直接运行 `scripts/FreePaste.app`，不会挂载或从 DMG 内运行应用。

如果只需打开已有开发产物：

```bash
open scripts/FreePaste.app
```

## 用 DMG 安装

1. 退出正在运行的 FreePaste。
2. 双击 `scripts/FreePaste.dmg`。
3. 将 `FreePaste.app` 拖到镜像内的 `Applications` 链接，安装到 `/Applications/FreePaste.app`。
4. 推出磁盘镜像，从 Applications 启动应用，不要直接运行镜像里的副本。
5. 后续更新时退出旧应用，再用同一安装路径替换。

不要同时运行开发目录和 Applications 中的两个副本。固定签名身份与安装路径有助于维持辅助功能授权，但从开发目录迁到 Applications 后仍可能需要重新授权，不能保证所有系统版本上永远免授权。

应用历史与设置不在 `.app` 内；拖拽安装不会将开发机的剪贴板记录打进 DMG。数据库在应用的 Application Support 路径，启用 App Sandbox 时由系统映射到应用容器。

Debug 和 Release 共用 `FreePaste/Config/FreePaste.entitlements`，不可为了构建方便单独关闭某一配置的沙盒。旧非沙盒历史由 Store 在启动时只读迁入当前容器；已经创建过空容器也能迁入，不依赖系统仅在第一次创建容器时执行的迁移机制。验证升级时应同时检查旧目录与容器目录，并覆盖文本、收藏、外部图片 / 富文本载荷、已有新记录合并和迁移后删除不复活。

当前安装包主要用于本机安装和验证。给其他人公开分发之前，还需规划 Release 构建、目标架构、Developer ID 签名和 Apple 公证流程。依据及限制见 [DMG 打包调研](dmg-packaging-research.md)。

## 自动化测试

运行测试前退出实际使用的 FreePaste，避免回写系统剪贴板的测试被真实应用采集。XCTest 宿主使用独立设置和内存历史，不启动真实剪贴板监听或注册全局快捷键，不读取用户数据库。

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

结果存放在 `.deriveddata-test/Logs/Test/`。2026-10-17 最近一次全量验证为 **208 项通过、0 项失败**，关闭测试签名；新增覆盖旧数据目录合并、外部载荷、收藏、迁移失败重试、删除不复活和 XCTest 宿主隔离。最终测试前后额外核对了两份真实数据库的记录摘要，确认均未被改写。这是验证快照，后续改动以实际运行结果为准。

测试覆盖设置与迁移、键盘路由和搜索模式、Core Data 存储、管理器、剪贴板监听、直接粘贴与预览边界，以及批量会话、拖动重排和按键拦截。不要用固定的测试文件数量判断覆盖范围。

## DMG 验证

打包脚本会验证应用签名、暂存副本签名和镜像校验和。完整验证还应检查挂载后的内容：

```bash
hdiutil verify scripts/FreePaste.dmg
hdiutil attach -readonly -verify -noignorebadchecksums -nobrowse -noautoopen scripts/FreePaste.dmg
codesign --verify --deep --strict /Volumes/FreePaste/FreePaste.app
readlink /Volumes/FreePaste/Applications
hdiutil detach /Volumes/FreePaste
```

`Applications` 链接应指向 `/Applications`。如果同名卷已经挂载，系统可能分配其他卷名，应使用 `hdiutil attach` 实际返回的挂载路径，且只卸载本次挂载的镜像。

`hdiutil verify` 校验镜像数据，`codesign` 校验应用签名；两者都不等同于 Gatekeeper 公证验收。

2026-10-15 本轮验证：更新后的构建脚本成功生成 .app / DMG；镜像格式为 UDZO，校验和、只读挂载后的应用签名、Applications 链接和可执行文件一致性均通过，镜像已正常卸载。另验证含空格路径及不同工作目录，并模拟创建 / 校验失败，确认旧安装包不被覆盖、暂存目录无残留。本轮未执行实际安装或公开分发验收。

## 桌面验证

建议用隔离测试数据，避免测试内容进入实际历史；实机验证仍不能完全被单元测试替代。

1. 验证面板唤起后直接输入、方向键和自定义导航快捷键选择、回车与纯文本粘贴；默认模式无闪烁光标，搜索栏右侧显示“⌘F 编辑”，收藏范围行为相同。
2. 验证 Command + F 后恢复编辑光标并隐藏提示，详细模式下复制、粘贴、撤销和中文组词正常，Esc 返回后再次隐藏光标并恢复列表操作。
3. 验证收藏 Key 保存、取消、修改和搜索排序。
4. 验证批量模式选区复制、窗口拖动、重排、正逆序切换和逐项粘贴。
5. 在 TextEdit 或 Notes 验证目标应用恢复，再检查复杂应用的热键兼容性。
6. 清理测试窗口，不留下临时输入覆盖或测试进程。

## 常见阻塞

### 签名或构建环境

“尚未配置签名团队”表示缺少本地覆盖文件或没有填写团队；先按本文创建本地配置。`No signing certificate` 通常表示该团队的钥匙串证书不可用。应修复本地配置或证书，不用 ad-hoc 签名掩盖问题，也不要把签名失败当作源码编译失败。

### 受限执行环境

`com.apple.testmanagerd.control ... Sandbox restriction`、无法连接 Xcode 系统服务，或 `hdiutil` 无法创建 / 挂载镜像，可能是执行环境限制。需要在有相应本机权限的环境下重试；这些权限用于构建和验证，不会给 FreePaste 增加辅助功能或输入监控授权。

### 直接粘贴或批量模式

直接粘贴需要辅助功能授权；批量模式还涉及输入监控及当前选区复制。授权、输入法、第三方热键工具和目标应用行为都可能影响结果，应先在简单文本应用复现。

### 安装包被系统阻止

本脚本没有执行 Developer ID 公证流程。公开分发应采用正确的签名和公证方案，不应通过移除隔离属性或关闭 Gatekeeper 来解决。

## 公开仓库与隐私边界

源码、测试、图标、图片、公共配置及构建脚本可以纳入版本控制。本地签名覆盖、私钥 / 令牌、剪贴板数据库、日志、编译缓存、应用、DMG 和打包暂存目录均由 `.gitignore` 排除；示例配置保留，便于其他开发者填写自己的信息。

Git 忽略规则只排除未跟踪文件，不会删除已经提交的文件或历史。首次发布前应检查待提交清单和提交作者的公开姓名、邮箱；后续若误提交敏感内容，需要单独处理已提交内容与历史，不能仅依赖补充忽略规则。不要直接压缩整个开发目录作为公开源码包，以免绕过忽略规则带入本地配置和缓存。

应用签名本身会携带开发者身份，`.gitignore` 不能让已签名的公开安装包匿名。DMG 仍应作为版本附件分发，而非提交到源码历史。

2026-10-17 已验证：本地覆盖前后的签名团队、Bundle ID 和最终应用签名指定要求一致；签名构建与 DMG 校验通过；公共源码副本没有本地配置仍可通过完整测试；未配置团队时提示清楚且保留已有产物。未推送代码、重写 Git 历史、重新授权或替换正在运行的应用。
