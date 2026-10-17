# FreePaste DMG 打包调研

> 最后更新：2026-10-17
> 范围：DMG 包装、安装入口、签名与验证。实现已落地，当前构建命令见 [开发文档](development-workflow.md)。

## 结论

FreePaste 是单一 .app，可打包为拖拽安装的 DMG，无需第三方工具。镜像根目录包含已签名的 `FreePaste.app` 和 `Applications -> /Applications` 链接；用户挂载后拖拽安装。Apple 官方提供源目录加 `hdiutil create` 的方案，推荐用 `ditto` 保留符号链接，并把 Applications 链接列为常见定制内容。[Apple：Packaging Mac software for distribution][packaging]

采用 HFS+ 文件系统和只读压缩 UDIF 格式 UDZO。显式指定格式、卷名和文件系统，避免默认值影响结果；HFS+ 是项目的保守选择，不是所有 DMG 的强制要求。[本机 hdiutil(1)][hdiutil]

**包装不等于公开发行。** 当前内层应用是 Apple Development 签名的 Debug、包含调试 entitlement；没有执行外层 DMG 分发签名或 Apple 公证。公开发布需合格的 Developer ID 签名和公证流程，不能仅换扩展名或配置名。[Apple：分发签名][distribution]；[Apple：公证要求][notarizing]

## 当前实现

| 脚本 | 行为 |
| --- | --- |
| [build-fixed-debug.sh](../scripts/build-fixed-debug.sh) | 从本地覆盖或命令行取得签名团队，Xcode Debug 构建后发布 `scripts/FreePaste.app`，验证签名与配置一致，再调用包装脚本 |
| [package-dmg.sh](../scripts/package-dmg.sh) | 单独包装已有签名应用，默认生成脚本同级 `FreePaste.dmg`，支持自定义输入 / 输出路径 |
| [rebuild-and-run.sh](../scripts/rebuild-and-run.sh) | 退出旧应用、重建 .app 和 DMG，仍从固定 .app 路径启动，不挂载镜像 |

包装脚本只读取源应用，不重新签名：

1. 验证源包结构与应用签名。
2. 在输出目录建立唯一暂存目录，避免旧文件合并或跨文件系统发布。
3. 用 `ditto` 复制应用，加入镜像根目录的 Applications 符号链接，验证副本签名。
4. 创建 HFS+ / UDZO 镜像并校验内部校验和。
5. 成功后原子替换最终同名 DMG，失败保留旧镜像，退出时清理本次暂存目录。

`ditto` 默认保留相关资源和扩展属性；不移除 quarantine，不修改包内文件。Applications 只是链接，不会复制本机整个 Applications 目录。[ditto(1)][ditto]；[ln(1)][ln]；[Apple：封存资源与签名][tn2206]

构建与包装不能并发改写同一源应用或同一输出。包装脚本验证完整性，不判定输入一定是 Developer ID 发行应用，也不保证通过 Gatekeeper。版本 / 配置说明见开发文档；固定文件名不代表 Release。

## 产物与签名快照

2026-10-15 本机读取和验证的应用：

```text
Identifier=com.cheems.FreePaste
Authority=Apple Development: ...
TeamIdentifier=<LOCAL_TEAM_ID>
Architecture=arm64
LSMinimumSystemVersion=14.6
Hardened Runtime enabled
com.apple.security.app-sandbox=true
com.apple.security.files.user-selected.read-only=true
com.apple.security.get-task-allow=true
```

证书个人显示名称和团队值已脱敏。公共工程不固定团队，个人值保存在 Git 忽略的本地签名配置中。以上是本机构建快照，不代表以后每次构建，也不能据此宣称支持 Intel / Universal。团队一致本身不足以证明证书类别、公证或辅助功能授权。

`codesign --display` 读取信息，`--verify` 才验证封存内容；Hardened Runtime 不等于公证完成。Apple 的新软件公证要求包括 Developer ID、有效签名、安全时间戳、Hardened Runtime，并禁止 true 的 `get-task-allow`，当前 Debug 包不满足该发行流程。[codesign(1)][codesign]；[Apple：Prepare your software for notarization][notarizing]

## 校验选项与边界

| 操作 | 用法 | 边界 |
| --- | --- | --- |
| 创建 | `-srcfolder -fs HFS+ -format UDZO -volname FreePaste` | 按内容估算容量；临时文件名无需覆盖选项 |
| 镜像校验 | `hdiutil verify` | 校验压缩镜像内部校验和，不认证来源或公证 |
| 格式读取 | `hdiutil imageinfo -format` | 应返回 UDZO |
| 只读挂载 | `-readonly -verify -noignorebadchecksums` | 显式校验，校验和不符时中止 |
| 验包挂载 | `-nobrowse -noautoopen -mountpoint ... -plist` | 不自动打开 Finder，返回结构化设备 / 挂载信息，不运行应用 |
| 卸载 | `hdiutil detach <本次挂载点>` | 不默认强制卸载；失败时保留诊断和挂载点 |
| 应用验证 | `codesign --verify --deep --strict` | 包含嵌套代码的完整性检查，不是重新签名或系统授权 |

选项依据本机 `man hdiutil` 与 `man codesign`。复杂挂载流程应解析 plist，不能按空格猜设备名；只清理自己创建的暂存目录，卸载失败不要递归删除挂载路径。[hdiutil(1)][hdiutil]；[codesign(1)][codesign]

## 本次验证

2026-10-15 已完成：

- 更新后的构建入口真实构建成功，同时生成脚本同级 .app 与 DMG。
- 源应用、暂存副本、只读挂载后的应用签名验证通过。
- DMG 校验和有效，格式读取为 UDZO。
- 镜像内 Applications 链接指向 `/Applications`，挂载后的主可执行文件与源文件逐字节一致。
- 只读挂载已正常卸载；没有安装到 Applications、运行镜像内应用或改变系统授权。
- 从其他工作目录、使用含空格的输入 / 输出路径打包成功。
- 缺失应用、失效签名、错误输出扩展名、目录形式的输出均拒绝；模拟创建 / 校验失败后旧 DMG 哈希不变，暂存目录无残留。
- 三个脚本的 shell 语法检查通过。

未完成或不属于本次验收：真实拖拽替换已安装应用、安装后首次启动、跨路径权限延续、互联网下载后的 Gatekeeper 检查、公证服务及另一台 Mac / 架构验证。没有把本地打包成功写成公开发布完成。

## 公开发布的后续流程

另行准备 Release archive / export，通过 Xcode 导出 Developer ID 分发应用，核对所有可执行代码的身份、时间戳、Hardened Runtime 与 entitlement；应用签名完成后将其视为只读。不要用 ad hoc 或 `--deep --force` 重签掩盖包装错误。[Apple：Creating distribution-signed code for macOS][distribution]

之后创建并签名最终 DMG，提交最外层容器公证。以下是未来发行顺序，不是当前构建脚本已执行的操作；`SIGN_ID` 应为真实的 Developer ID Application 身份，凭据使用预先配置的 Keychain profile。[Apple：包装与容器签名][packaging]；[Apple：自定义公证流程][notary-workflow]

```sh
codesign --sign "$SIGN_ID" --timestamp \
  --identifier com.cheems.FreePaste.dmg "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile FreePaste-notary --wait
# Confirm Accepted and inspect the submission log before stapling.
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
hdiutil verify "$DMG"
```

DMG 使用 Developer ID Application，不是 Developer ID Installer；签外层不会修正内层 Debug entitlement。上传公证使用 `notarytool`，不用已停止接受的 `altool`。Stapling 附上票据以支持离线使用，仍需在独立 Mac 或测试用户上验证正常下载、首次安装、更新和离线行为。[Apple：包装格式与签名][packaging]；[Apple：公证流程][notary-workflow]

Gatekeeper 按系统策略检查下载软件的开发者身份、公证及完整性。不要通过移除隔离属性、关闭 Gatekeeper 或修改 TCC 数据库替代正确发行流程。[Apple Platform Security：Gatekeeper][gatekeeper]

## 安装与权限限制

固定签名与固定安装路径是开发约定，不是永久免授权保证。移动到 Applications、更换证书或系统更新后，需要检查**实际运行实例**的辅助功能信任；设置中有同名条目不等于当前进程已获授权。Apple 的接口检查当前进程，授权提示是异步的。[Apple：AXIsProcessTrustedWithOptions][ax-trust]；[Apple：辅助功能设置][accessibility]

DMG 不执行用户数据迁移、自动更新、卸载或权限配置，也不包含数据库。简单镜像没有额外固定 Finder 图标坐标或背景，当前需求无需引入第三方工具。手动安装与数据位置见 [开发文档](development-workflow.md)。

## 第一手来源

Apple 当前文档用于发行政策，历史 TN2206 仅补充签名机制；本机手册用于命令选项，不把旧手册日期当作最新公证政策。

- [Packaging Mac software for distribution][packaging]
- [Creating distribution-signed code for macOS][distribution]
- [Notarizing macOS software before distribution][notarizing]
- [Customizing the notarization workflow][notary-workflow]
- [Gatekeeper and runtime protection][gatekeeper]
- [TN2206: macOS Code Signing In Depth][tn2206]
- [AXIsProcessTrustedWithOptions][ax-trust]、[辅助功能授权设置][accessibility]
- 本机 `man hdiutil`、`man codesign`、`man ditto`、`man ln`、`man stapler`。

[packaging]: https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution
[distribution]: https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac
[notarizing]: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
[notary-workflow]: https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
[gatekeeper]: https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web
[tn2206]: https://developer.apple.com/library/archive/technotes/tn2206/_index.html
[ax-trust]: https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
[accessibility]: https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac
[hdiutil]: /usr/share/man/man1/hdiutil.1
[codesign]: /usr/share/man/man1/codesign.1
[ditto]: /usr/share/man/man1/ditto.1
[ln]: /usr/share/man/man1/ln.1
