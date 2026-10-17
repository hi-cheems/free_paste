# FreePaste 架构说明

> 最后更新：2026-10-17

## 概览

FreePaste 是本地优先的 macOS 菜单栏剪贴板工具。应用入口协调底部历史面板、批量浮窗、全局热键和直接粘贴；业务层负责采集、过滤、存储与发布状态。文本、图片和文件 URL 共用条目模型。

主要框架为 Swift / SwiftUI、AppKit、Combine、Carbon、Core Data、ImageIO 和 ApplicationServices，无必需第三方运行时依赖。

## 主链路

```text
NSPasteboard
  -> ClipboardMonitor.newItem
  -> ClipboardManager: 前台来源黑名单过滤
       -> capturedItem -> 活跃的 BatchPasteSession
       -> 暂停记录检查 -> ClipboardHistoryStore
                            -> mutation + prune removed IDs
                            -> 增量发布历史摘要
                            -> ClipboardHistoryView

AppDelegate
  -> 历史面板 / 批量浮窗 / 设置 / 预览
  -> 全局热键 / 目标应用跟踪 / 权限引导
  -> ClipboardManager 回写原始数据
  -> DirectPasteService 恢复目标应用并派发 Cmd+V
```

启动时加载历史摘要快照；后续新增、删除、收藏和淘汰更新已发布的数组，不在每次复制后完整重载所有原始载荷。搜索仍由 Store 查询摘要并排序。

## 数据与监听

代码入口：[ClipboardItem.swift](../FreePaste/FreePaste/ClipboardMonitor/ClipboardItem.swift)、[ClipboardMonitor.swift](../FreePaste/FreePaste/ClipboardMonitor/ClipboardMonitor.swift)。

`ClipboardContent` 包含 `.text(String)`、`.image(Data)`（原始 TIFF）、`.fileURLs([URL])`。

`ClipboardItem` 包含：

- `id`、`timestamp`、`content`
- `isPinned`、可选的 `favoriteKey`
- 文本原始格式 `richData`，按 pasteboard 类型保存 RTF / RTFD / HTML 数据
- `payloadAvailability`：完整载荷或 UI 摘要
- `imagePixelSize`：原图尺寸，摘要缩略图不替代该元数据

监听层轮询 `NSPasteboard.changeCount`，识别顺序为文件 URL、TIFF 图片、文本，通过 Combine 发布。它只观察内容，不负责隐私策略和存储。`PasteboardReading` 支持隔离测试；回写剪贴板后通过 `syncChangeCount()` 避免自采集。

## 存储与迁移

代码入口：[ClipboardHistoryStore.swift](../FreePaste/FreePaste/ClipboardHistory/ClipboardHistoryStore.swift)。

Store 使用代码构建 Core Data 模型，持久化到 Application Support 下的 SQLite；App Sandbox 环境由系统映射到容器。测试支持内存 Store。

Debug 和 Release 共用 `Config/FreePaste.entitlements` 及相同应用标识，均使用沙盒存储。旧的非沙盒构建可能在真实用户目录 `~/Library/Application Support/FreePaste/` 留下数据库，因此首次升级不能只根据 Bundle ID 判断数据已共享：Store 通过 POSIX 用户信息定位真实主目录，避免 Foundation 在沙盒内仍返回容器路径，再将旧库只读复制到临时位置，完成必要的模型迁移后按记录 ID 合并到当前库，不覆盖当前记录、不删除旧库。图片外部载荷和 SQLite WAL 由 Core Data 一并复制；成功后写入一次性标记，避免再次导入用户已删除的记录，失败则保留原数据并允许重试。只读权限例外仅覆盖旧 FreePaste 数据目录，不允许写入旧库。

持久化字段按职责分组：

| 职责 | 字段 |
| --- | --- |
| 身份与排序 | `id`、`timestamp` |
| 收藏 | `isPinned`、`favoriteKey` |
| 原始内容 | `text`、`imageData`、`fileURLsJSON`、`richDataBlob` |
| 摘要与裁剪 | `imageThumbnailData`、`imagePixelWidth`、`imagePixelHeight`、`payloadByteCount`、`metadataPrepared` |

大图片与富文本二进制允许外部存储。列表使用 dictionary 摘要查询，完整载荷只在 `fetch(id:)` 等明确需要的读取中加载。旧条目的缩略图、尺寸和容量元数据按批补齐，避免一次保留所有大图。

代码模型不能依赖 .momd 自动发现旧版本：当前显式识别已知旧模型，通过 `NSMigrationManager` 迁移到临时数据库后替换。加载或迁移失败时保留原数据库并临时使用内存 Store，不再以删除历史换取启动成功；内存回退期间的新记录不保证跨重启保留。

去重开关启用时，相同文本或相同序列化文件 URL 列表只去重未收藏项；图片不去重，收藏不会被复制去重替换。文件保存的是 URL，不是文件内容副本。

淘汰顺序为过期、最大条数、最大容量，均排除收藏。容量按保存载荷计量，不是进程内存上限，也不是文件 URL 指向的文件大小。

## 搜索与收藏

Store 提供 `search(query:)`（全部记录）、`searchPinned(query:)`（仅收藏）和 `searchUnpinned(query:)`（未收藏）。主面板的“最近”使用全部记录，包含收藏。

空查询按 `timestamp` 倒序显示；当前没有单独的收藏时间字段。非空查询匹配文本、文件 URL JSON 和收藏 Key，忽略大小写与变音符号。命中 Key 的记录稳定排列在仅内容命中之前，组内保持时间排序，一条记录只展示一次。

图片内容不进行 OCR，只有手动设置的收藏 Key 可提供文字检索入口。

收藏绑定原条目，不是独立 KV 内容库。新增收藏需要非空 Key，同一 Key 可以对应多个条目；取消收藏清除 Key。右键编辑支持修改或清空 Key，旧收藏没有 Key 时仍可按内容搜索。

## 协调与性能

代码入口：[ClipboardManager.swift](../FreePaste/FreePaste/ClipboardManager/ClipboardManager.swift)、[ClipboardImageThumbnail.swift](../FreePaste/FreePaste/ClipboardHistory/ClipboardImageThumbnail.swift)。

Manager 是 UI 的单一业务入口，发布 `items`、`unpinnedItems`、`pinnedItems`，负责保存、搜索、收藏、删除、剪贴板回写与设置联动。

- 来源过滤通过前台应用 bundle ID 判断，仅在内存使用，不存储或展示来源应用。
- `capturedItem` 在来源过滤后、历史暂停检查前发送。批量队列遵守黑名单，但不受历史暂停影响。
- `ClipboardHistoryMutation` 返回新增摘要与已删除 ID；淘汰同样返回删除 ID，Manager 增量更新状态。
- `materializedItem(for:)` 在粘贴 / 预览前解析摘要为完整数据；纯文本粘贴只写字符串。
- 设置变更异步转到主队列后应用，避免读取 `@Published` 的旧值。

图像列表保存最长边 512 像素的 JPEG 缩略图，ImageIO 先降采样；独立预览最长边为 1600 像素。原始 TIFF 保留用于粘贴。缩略图 `NSCache` 的限制为 128 项、64 MiB 成本，系统可提前回收，这些限制不构成整个进程的硬内存上限。

## 历史面板与按键路由

代码入口：

- [ClipboardHistoryView.swift](../FreePaste/FreePaste/ClipboardHistoryView/ClipboardHistoryView.swift)
- [ClipboardHistoryNavigation.swift](../FreePaste/FreePaste/ClipboardHistoryView/ClipboardHistoryNavigation.swift)
- [ClipboardHistoryKeyAction.swift](../FreePaste/FreePaste/ClipboardHistoryView/ClipboardHistoryKeyAction.swift)
- [KeyboardEventMonitor.swift](../FreePaste/FreePaste/ClipboardHistoryView/KeyboardEventMonitor.swift)
- [ClipboardItemRow.swift](../FreePaste/FreePaste/ClipboardHistoryView/ClipboardItemRow.swift)
- [FavoriteKeyEditorView.swift](../FreePaste/FreePaste/ClipboardHistoryView/FavoriteKeyEditorView.swift)

`AppDelegate` 在鼠标所在屏幕的可用区域底部定位整宽 `NSPanel`。高度目标为可用高度 20%，限制在 180 到 260 点，最终不超过可用区域。历史和收藏复用横向卡片，不提供网址预览或来源应用图标。

单击选中记录，不将边缘卡片强制居中；双击或回车请求直接粘贴。键盘导航会按需要滚动到选中项。默认模式下，配置的预览快捷键（默认裸空格）切换选中项预览，长按的重复事件不反复开关；没有有效选中项时不执行预览，也不将该按键交给查询。更换绑定后释放原快捷键，右键菜单仍可进入预览。

两种逻辑搜索模式独立于原生搜索框是否为 first responder：

| 模式 | 输入与按键 |
| --- | --- |
| 默认快速模式 | 唤起即接收查询；方向键 / 配置的上一项下一项选择记录；回车粘贴；预览快捷键（默认空格）切换预览；Tab 切换全部与收藏；Esc 关闭面板 |
| 详细编辑模式 | Cmd+F、配置搜索键或点击搜索框进入；空格、导航、Tab、回车、复制粘贴和撤销用于文本；只有 Esc 回默认模式，保留查询与有效选择 |

原生输入控件承接文字和输入法；默认模式隐藏 field editor 插入光标，并在搜索栏末尾显示“⌘F 编辑”，详细模式恢复原光标颜色。光标隐藏不改变输入焦点、选择或组词状态，离开该 editor / 结束监听时恢复颜色。存在 marked text 时先交还输入法处理，不能把组词确认误判为粘贴。纯状态机负责选择和模式，按键路由负责判断动作，视图通过闭包上抛确认、预览和设置请求。

## 批量粘贴

代码入口为 [BatchPaste](../FreePaste/FreePaste/BatchPaste/) 下的四个文件：

| 模块 | 职责 |
| --- | --- |
| `BatchPasteSession` | 临时队列、输出方向、选择、重排、容量与生命周期 |
| `BatchPasteKeyInterceptor` | 仅活跃会话期间拦截 Cmd+V |
| `BatchPastePanelController` | 置顶浮窗、位置、动态高度与平台按键 |
| `BatchPastePanelView` | 摘要列表、缩略图 / 文件图标、方向切换、拖动排序与关闭 |

全局 Cmd+Shift+C 在快捷键释放后触发选区复制，等待新剪贴板内容，再通过 `currentItemForBatchPaste()` 取得首项。无有效选区复制时启动失败，不拿旧历史或旧剪贴板替代首项。首项读取同步监听计数，避免随后重复收集。

会话活跃时锁闭历史 / 收藏面板入口，显示可拖动顶部栏的竖向置顶浮窗。高度随条数增长，达到上限后滚动；拖动排序使用位移反馈与换位阈值控制，避免边界往返抖动。

`items[0]` 是默认下一项，显式选中可覆盖。正序追加、倒序插入头部，切换方向反转当前队列；鼠标拖动和上下键调整输出顺序。Cmd+V、浮窗回车、双击都使用同一输出路径，取出条目、回写剪贴板并请求目标应用粘贴。当前在目标粘贴结果返回前已经移除条目，因此派发失败不自动回滚队列。

删除选中项后选择同位置的下一项，末尾则选前一项；Esc 仅清选择。最后一项移除自动结束，关闭按钮放弃剩余队列。会话不持久化；输出方向设置持久化。

队列上限为 200 项及 256 MiB 估算载荷，包含文本 / 图像 / 富文本数据与文件 URL 字符串，不包含实际文件大小，也不是总进程内存限制。

## 平台、预览与设置

[AppDelegate.swift](../FreePaste/FreePaste/AppDelegate.swift) 管理状态栏、窗口、全局 Carbon 热键、目标应用跟踪与权限引导，避免这些桌面生命周期行为进入 Store。

[DirectPasteService.swift](../FreePaste/FreePaste/DirectPaste/DirectPasteService.swift) 通过可注入的权限、前台应用和事件发送接口恢复目标应用，再发送 Cmd+V。显式结果包括无目标、缺少辅助功能权限、激活失败、派发失败；事件发送成功不证明目标实际接收了内容。批量模式另需输入监控权限。

[ItemPreviewPresenter.swift](../FreePaste/FreePaste/ItemPreviewPresenter.swift) 与 [ItemPreviewView.swift](../FreePaste/FreePaste/ItemPreviewView.swift) 使用独立面板，按需读取文本、图片和文件 URL；图片是有界预览而非始终完整解码。

[AppSettings.swift](../FreePaste/FreePaste/AppSettings.swift) 保存历史策略、黑名单、暂停状态、快捷键与批量方向；快捷键录制 / 冲突检测由 `KeyboardShortcut` 和 `ShortcutRecorderRow` 配合设置页完成，开机自启使用 `LaunchAtLoginController`。

预览绑定使用 `settings.shortcuts.preview` 持久化，缺失或无法解码时回退为空格，不改写其他绑定。预览与其他已配置动作共用冲突检测和恢复默认入口；录制器支持裸空格和带修饰键的组合，路由只匹配当前绑定，不额外保留固定空格入口。详细编辑与输入法组词仍优先处理文本。

## 构建与安装包

项目通过 `FreePaste/Config/Signing.xcconfig` 可选加载 Git 忽略的本地签名覆盖，公共工程不固定开发团队。`scripts/build-fixed-debug.sh` 读取生效的团队（支持环境变量覆盖）、构建 Debug、发布脚本同级的 `FreePaste.app` 并验证签名团队与配置一致，然后调用 `scripts/package-dmg.sh`。后者用全新暂存目录、`ditto` 和 `Applications -> /Applications` 链接创建 HFS+ / UDZO 镜像，验证后才替换 `scripts/FreePaste.dmg`，失败保留旧镜像。

包装不会改变应用签名、不内置用户历史，不执行安装、重签名或公证。`rebuild-and-run.sh` 继续从固定 .app 路径启动。具体命令见 [开发文档](development-workflow.md)，公开发行限制见 [调研](dmg-packaging-research.md)。

## 目录与验证

```text
paste/
  FreePaste/
    FreePaste/          # Swift app, including BatchPaste and history modules
    FreePasteTests/     # unit and platform-boundary tests
    FreePaste.xcodeproj/
  scripts/              # build, rebuild/run, standalone DMG packaging
  docs/                 # current docs, research, historical iteration records
```

测试覆盖 Store 查询、迁移与载荷、Manager 增量发布、输入法 / 快捷键路由、导航状态机、批量生命周期与重排，以及平台权限和预览边界。系统授权、真实目标应用粘贴和长时间运行的内存曲线仍需桌面验证；测试命令与日期快照见开发文档。

建议阅读顺序：AppDelegate -> ClipboardManager -> ClipboardMonitor -> ClipboardHistoryStore -> 搜索路由 / 导航 -> BatchPasteSession -> DirectPasteService。当前未实现 OCR、历史加密或同步，后续方向见 [路线图](next-steps-roadmap.md)。
