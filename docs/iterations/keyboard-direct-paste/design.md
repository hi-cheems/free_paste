# 设计文档：键盘导航与直接粘贴

> 版本：draft 1
> 日期：2026-03-15
> 说明：这是迭代开始时的设计草稿，部分“未实现”表述已经过期，仅用于回看当时设计意图。

## 问题

FreePaste 现在已经可以保存并展示剪切板历史，但还没有真正完成用户的工作流。用户仍然需要：
- 用鼠标选择一条记录
- 切回原来的应用
- 手动按一次 `Cmd+V`

这让产品已经“有用”，但还不够快，不足以成为默认的日常效率工具。

## 设计目标

从唤起到最终粘贴，整个交互链路都可以由键盘完成。

## 目标用户流程

1. 用户正在应用 A 中工作。
2. 用户按下 `Cmd+Shift+V`。
3. FreePaste 打开，并记录应用 A 作为恢复目标。
4. 搜索框默认获得焦点。
5. 用户可以直接输入筛选，也可以按 `Down Arrow` / `Tab` 进入列表。
6. 用户通过 `Up Arrow` / `Down Arrow` 在条目之间导航。
7. 用户按下 `Return`。
8. FreePaste 将选中内容写入系统剪切板。
9. FreePaste 关闭 `popover`。
10. FreePaste 重新激活应用 A。
11. FreePaste 向应用 A 发送 `Cmd+V`。

## 交互规则

### 打开 Popover

- 打开 FreePaste 时，在 `popover` 成为活动窗口之前记录当前前台应用。
- 搜索框成为 `first responder`。
- 如果列表不为空，则第一条可见记录成为默认选中项。

### 搜索行为

- 输入时立即筛选列表。
- 搜索结果变化时，选中项重置为当前可见列表的第一条。
- 如果没有结果，选中状态为空。

### 键盘导航

- 在搜索框中按 `Down Arrow` 会把焦点移入列表。
- 在搜索框中按 `Tab` 也会把焦点移入列表。
- `Up Arrow` 和 `Down Arrow` 用于在列表内部移动。
- 到达第一条或最后一条时不循环。
- 在列表中按 `Shift+Tab` 返回搜索框。

### 确认选择

- 在选中某一行时按 `Return`，确认该项。
- 在搜索框中按 `Return`，如果存在可见结果，则默认确认第一项。
- 确认动作会触发直接粘贴流程。

### 权限处理

- 直接粘贴依赖 `Accessibility` 权限。
- 如果权限缺失，FreePaste 会触发系统权限申请对话框。
- 在此状态下，不会尝试发送粘贴事件。
- `popover` 保持可用，用户授权后可以再次尝试。

## 架构决策

当前架构整体不需要大改：

- `ClipboardManager` 继续负责剪切板数据与存储协调。
- `AppDelegate` 继续负责应用级集成：状态栏图标、`popover`、全局快捷键、应用激活。
- 直接粘贴自动化逻辑不应放进 `ClipboardManager`，因为它属于平台集成行为，而不是剪切板领域逻辑。

## 建议的职责划分

### `AppDelegate`

负责：
- `popover` 生命周期
- 全局快捷键处理
- 记录之前的前台应用
- 将 UI 的确认动作接到直接粘贴流程

### `ClipboardHistoryView`

负责：
- 搜索文本
- 键盘焦点状态
- 当前选中行状态
- 选中行的视觉反馈
- 在用户确认条目时触发回调

### 新增辅助组件：`DirectPasteService`

建议新增一个独立组件。

负责：
- 检查 `Accessibility` 权限
- 触发权限申请
- 激活原始应用
- 发送模拟 `Cmd+V`

这样可以把自动化逻辑从 View 和 `ClipboardManager` 中隔离出去。

## 建议的数据 / 控制流

```text
Cmd+Shift+V
  -> AppDelegate.togglePopover()
  -> capture frontmost app
  -> show ClipboardHistoryView

Return on selected item
  -> ClipboardHistoryView confirm(item)
  -> AppDelegate handles confirmation
  -> ClipboardManager.copyToPasteboard(item)
  -> AppDelegate closes popover
  -> DirectPasteService.pasteBack(to: previousApp)
```

## 需要的 UI 变更

- 给 `ClipboardItemRow` 增加选中态样式
- 给 `popover` 内容增加键盘事件处理
- 保持搜索框与列表焦点行为可预测
- 在无法直接粘贴时提供最小化的权限提示信息

## 文件级影响

预计会修改的文件：
- `FreePaste/FreePaste/AppDelegate.swift`
- `FreePaste/FreePaste/ClipboardHistoryView/ClipboardHistoryView.swift`
- `FreePaste/FreePaste/ClipboardHistoryView/ClipboardItemRow.swift`
- `FreePaste/FreePaste/ClipboardManager/ClipboardManager.swift`

预计会新增的文件：
- `FreePaste/FreePaste/DirectPaste/DirectPasteService.swift`
- 以及可选的直接粘贴边界测试

## 非目标

这次迭代不应该同时扩展存储模型、加入图片支持，或重做整套 UI。那样会把太多风险混在一次升级里。
