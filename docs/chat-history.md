# 聊天记录

> 说明：这份文档保留早期讨论和实现过程，主要用于回溯背景，不代表当前项目现状。
> 当前事实请优先参考 [文档总览](README.md)、[项目说明](project-notes.md)、[架构](architecture.md) 和 [后续方向](next-steps-roadmap.md)。

## 2026-03-12

### 话题：开发环境准备

Q: 如何准备 macOS 剪切板软件的开发环境？

结论：
- 技术栈选 Swift + SwiftUI + CloudKit（性能最优，原生 iCloud 支持）
- 安装 Xcode、Homebrew、Git
- 免费账号可开发，付费账号才能用 CloudKit 和发布

---

### 话题：iCloud 付费账号

Q: 没有付费账号是否无法开发 iCloud 同步？
A: 是。CloudKit 需要付费账号。分阶段开发：阶段一做核心功能，阶段二再接 CloudKit。局域网同步无需付费可提前做。

Q: 发布应用是否必须付费？
A: App Store 和公证分发都需要付费账号（$99/年）。

Q: 付费到期后已安装用户还能用 iCloud 同步吗？
A: 可以。CloudKit 数据在用户 iCloud 空间，不依赖开发者账号有效性。到期后只影响发布更新能力。

---

### 话题：架构决策

结论：
- iCloud 同步作为后续更新选项
- 同步层与核心逻辑分离，设计可插拔的第三方同步接口
- 局域网同步优先开发

---

### 话题：需求挖掘（进行中）

Q: 目标用户？
A: 开源，面向普通用户，考虑上架 App Store

Q: 入口方式？
A: 菜单栏常驻图标 + 全局快捷键弹出 + Spotlight 风格搜索框

Q: 历史记录保存上限？
A: 用户自定义

Q: 敏感内容处理？
A: 提供自定义选项，让用户自己选择处理方式

> 需求挖掘尚未完成，后续对话继续补充。

---

### 话题：第一个模块选择 —— ClipboardMonitor

**背景知识确认：**

Q: NSPasteboard 是什么？为什么要问轮询间隔？
A:
- NSPasteboard 是 macOS 系统剪切板 API，⌘C 写入、⌘V 读取
- macOS 不提供剪切板变化的推送通知，只能定时主动检查 changeCount 是否变化（轮询）
- 间隔决定"多久检查一次"，0.5s 响应快且性能开销可忽略

**设计选择讨论：**

| 选项 | 候选 | 说明 |
|------|------|------|
| 通知方式 | Combine Publisher vs 闭包回调 | Combine 更现代，与 SwiftUI 天然集成；闭包更简单 |
| 内容类型 | 文本 / 图片 / 文件 URL | 互不排斥，第一版先做文本 |
| 轮询间隔 | 固定 0.5s vs 可配置 | 固定够用，后续可开放配置 |

> 设计决策最终确认：Combine Publisher + 纯文本 + 固定 0.5s。

---

## 2026-03-13

### 话题：ClipboardMonitor 模块实现

**设计决策（最终）：**
- 通知方式：Combine Publisher（`PassthroughSubject<ClipboardItem, Never>`）
- 内容类型：纯文本，预留图片/文件 URL 扩展位置
- 轮询间隔：固定 0.5s

**交付文件：**
- `FreePaste/ClipboardMonitor/ClipboardItem.swift` - 数据模型
- `FreePaste/ClipboardMonitor/ClipboardMonitor.swift` - 核心监听器
- `FreePasteTests/ClipboardMonitorTests.swift` - 7 个单元测试，全部通过

**测试覆盖：**
- 内容变化时正确发出条目
- changeCount 不变时不触发
- 多次复制各自触发
- 空字符串和 nil 被过滤
- 重复调用 start() 不会重复监听
- stop() 后不再发出条目
- 每条记录有唯一 UUID

---

### 遇到的问题：Xcode 测试 Target 配置（visionOS vs macOS）

**问题根本原因：**
项目创建时默认以 visionOS 为主平台（SDKROOT = xros），导致测试 Target 无法在 macOS 上运行。

**错误链及解决过程：**

| 错误 | 原因 | 解法 |
|------|------|------|
| `TEST_HOST evaluates to Debug-xros/...` | 测试 Target 的 TEST_HOST 硬编码了 xros 路径 | 改为 `$(BUILT_PRODUCTS_DIR)/FreePaste.app/FreePaste` |
| `FreePasteTests does not support My Mac's platform` | 测试 Target 没有添加 macOS 支持 | General → Supported Destinations → 添加 Mac |
| `macOS 15.7.3 doesn't match deployment target 26.2` | 测试 Target 部署目标版本过高 | Build Settings → macOS Deployment Target 改为 14.0 |
| 仍然指向 `Debug-xros/...` | 主 App（FreePaste）本身 SDKROOT = xros，没有 macOS 构建产物 | 主 App Build Settings → Base SDK 改为 macOS，Deployment Target 改为 14.0 |

**最终解法：将主 App Target 的 Base SDK 改为 macOS。**

**教训：**
- 新建 Xcode 项目时，如果目标是 macOS App，创建向导里要明确选择 **macOS** 平台，避免后续平台配置混乱
- 测试 Target 的平台配置依赖主 App 的构建产物，主 App 不支持 macOS，测试也无法在 macOS 上跑

---

### 话题：ClipboardHistoryStore 模块实现

**交付文件：**
- `FreePaste/ClipboardHistory/ClipboardHistoryStore.swift`
- `FreePasteTests/ClipboardHistoryStoreTests.swift` - 14 个测试，全部通过

**核心设计：**
- Core Data + 编程方式构建模型（无需 .xcdatamodeld 文件）
- `init(inMemory: Bool)` 支持测试隔离
- 功能：add（含去重）、delete、deleteAll、enforceLimit、fetchAll、search、count

---

### 话题：ClipboardManager 协调层实现

**交付文件：**
- `FreePaste/ClipboardManager/ClipboardManager.swift`
- `FreePasteTests/ClipboardManagerTests.swift` - 12 个测试，全部通过

**核心设计：**
- Monitor.newItem → 自动 add 到 Store → 刷新 @Published items
- 暴露：maxItems、deduplicateEnabled、delete、deleteAll、search、copyToPasteboard

**遇到的问题：Xcode 16 project.pbxproj 格式**
- ClipboardItem/Monitor/HistoryStore 被意外排除出 FreePaste Target
- 根本原因：Xcode 16 新格式中 `membershipExceptions` = 被排除的文件
- 解法：直接编辑 project.pbxproj，清空 FreePaste Target 的 membershipExceptions

---

### 话题：菜单栏 UI 实现

**交付文件：**
- `FreePaste/FreePasteApp.swift` - 改为 MenuBarExtra，无 Dock 图标
- `FreePaste/ClipboardHistoryView/ClipboardHistoryView.swift`
- `FreePaste/ClipboardHistoryView/ClipboardItemRow.swift`

**功能：**
- 菜单栏图标点击弹出面板（320×400）
- 搜索框实时过滤
- 列表：hover 显示删除按钮，点击条目复制回剪切板
- 底部：条目计数 + 清空按钮
- 空状态提示

**编译验证：** BUILD SUCCEEDED ✅

---

### 话题：全局快捷键实现

**方案：** 放弃 `MenuBarExtra`，改用 `AppDelegate` + `NSStatusItem` + `NSPopover` + Carbon `RegisterEventHotKey`

**交付文件：**
- `FreePaste/AppDelegate.swift` — 新建，管理状态栏图标、弹出面板、全局快捷键
- `FreePaste/FreePasteApp.swift` — 改为 `@NSApplicationDelegateAdaptor`，移除 `MenuBarExtra`
- `project.pbxproj` — 两个 target 配置加入 `INFOPLIST_KEY_LSUIElement = YES`（隐藏 Dock 图标）

**遇到的问题：** `InstallApplicationEventHandler` 是 Carbon 函数式宏，Swift 不支持，需展开为 `InstallEventHandler(GetApplicationEventTarget(), ...)`

**编译验证：** BUILD SUCCEEDED ✅

**功能：**
- 左键菜单栏图标 → 弹出/关闭面板
- `⌘⇧V` 全局快捷键（任意 App 内可用）→ 弹出/关闭面板
- 右键图标 → 显示快捷键说明 + 退出按钮

---

### 话题：已知问题记录（待实现）

**UI-1：弹出窗口样式需调整**
- 现状：NSPopover 默认外观
- 期望待明确

**UI-2：键盘导航 + 直接粘贴（高优先级）**
- 呼出面板后用 ↑↓ 键导航历史条目
- 按 Enter 确认 → 写入剪切板 → 关闭面板 → 自动向前台应用发送 ⌘V
- 技术难点：需记录呼出前的前台应用，用 CGEvent 模拟 ⌘V，可能需要 Accessibility 权限
