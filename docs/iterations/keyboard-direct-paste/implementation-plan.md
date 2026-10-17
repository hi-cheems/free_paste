# 实施计划

> 日期：2026-03-15
> 说明：这是该迭代启动前的实施计划，当前仅作为历史执行记录保留。

## 执行原则

这个功能应该按窄而完整的纵向切片推进，不要一次同时解决键盘 UX、权限流程和 UI 打磨。

## Phase 1：键盘导航骨架

### 目标

在引入直接粘贴之前，先让 `popover` 能在不依赖鼠标的情况下完成选择。

### 任务

1. 在 `ClipboardHistoryView` 中增加选中项状态
2. 在筛选结果变化时重置选中项
3. 在 `ClipboardItemRow` 中增加行高亮样式
4. 增加 `Up`、`Down`、`Tab`、`Shift+Tab`、`Return` 的键盘处理
5. 定义 `popover` 打开时的默认选中项

### 交付结果

- 用户可以打开 `popover` 并仅用键盘选择一项
- `Return` 可以触发现有的复制到剪切板行为

## Phase 2：确认流程挂钩

### 目标

把“某行被选中”和“某行被确认”分开处理。

### 任务

1. 让 `ClipboardHistoryView` 暴露明确的确认回调
2. 让鼠标点击和键盘确认走同一条行为路径
3. 将确认动作统一收敛到 `AppDelegate`

### 交付结果

- 鼠标点击和键盘 `Return` 都通过同一个确认入口处理

## Phase 3：记录原前台应用

### 目标

记录 FreePaste 后续应该粘贴回去的目标应用。

### 任务

1. 在打开 `popover` 之前记录 `NSWorkspace.shared.frontmostApplication`
2. 追踪恢复目标时忽略 FreePaste 自己
3. 明确无有效目标应用时的行为

### 交付结果

- `AppDelegate` 中持有可靠的原始前台应用引用

## Phase 4：Direct Paste Service

### 目标

把平台自动化能力封装成一个独立组件。

### 任务

1. 创建 `DirectPasteService`
2. 增加权限检查与申请逻辑
3. 增加应用激活逻辑
4. 增加 `Cmd+V` 事件发送逻辑
5. 如果有需要，增加激活与粘贴之间的延迟调优

### 交付结果

- 一个在权限存在时可复用的“粘贴回原应用”服务

## Phase 5：集成完整流程

### 目标

把复制、关闭、恢复应用、发送粘贴整合为一条完整链路。

### 任务

1. 确认选择时，把选中项写入剪切板
2. 关闭 `popover`
3. 重新激活目标应用
4. 执行粘贴
5. 在权限缺失时给出明确反馈

### 交付结果

- 直接粘贴端到端流程跑通

## Phase 6：稳定化

### 目标

在进入下一轮功能迭代前，清理边缘问题。

### 任务

1. 在可行处补充回归测试
2. 在多个应用中进行手工验证
3. 调整焦点行为与边界情况
4. 清理临时调试代码与无效分支

## 建议的文件改动

### 现有文件

- `FreePaste/FreePaste/AppDelegate.swift`
- `FreePaste/FreePaste/ClipboardHistoryView/ClipboardHistoryView.swift`
- `FreePaste/FreePaste/ClipboardHistoryView/ClipboardItemRow.swift`
- `FreePaste/FreePaste/ClipboardManager/ClipboardManager.swift`

### 新文件

- `FreePaste/FreePaste/DirectPaste/DirectPasteService.swift`
- 可选：
  - `FreePaste/FreePaste/DirectPaste/AccessibilityPermission.swift`
  - 如果实现支持注入，则补充直接粘贴相关测试

## 里程碑定义

### Milestone A

- 键盘导航完成
- 还没有自动化粘贴

### Milestone B

- 已授权时直接粘贴可用
- 缺权限时失败路径明确

### Milestone C

- 手工验证完成
- 测试更新完成
- 可以进入下一次迭代
