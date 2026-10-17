# 当前进展

> 更新日期：2026-03-16
> 说明：本文描述的是该迭代收尾时的状态，不代表当前全局优先级。公开整理时仅将个人绝对路径改为仓库相对路径，功能与验证结论不变。

本文档记录本次“键盘导航 + 直接粘贴”迭代目前已经落地的内容、验证结果，以及后续接手时应继续推进的方向。

补充说明：
- 本迭代收尾后，项目已经继续完成“设置系统最小闭环”
- 因此本文档里的“建议下一步”已不再是当前项目全局优先级，只代表当时的迭代收尾建议

## 已完成

当前已完成 `Phase 1` 到 `Phase 5` 的主链路实现，并已完成本轮手工验证。

### 已落地能力

- `popover` 打开后搜索框可获得焦点
- 列表存在默认选中项
- 支持 `Up Arrow` / `Down Arrow` 在历史项之间移动
- 支持 `Tab` 从搜索框切到列表
- 支持 `Shift+Tab` 从列表回到搜索框
- 支持 `Return` 对当前选中项执行确认
- 列表项已有选中高亮态
- 鼠标点击和键盘确认已统一收口到 `AppDelegate`
- 打开 `popover` 前会记录原前台应用，并过滤掉 FreePaste 自身
- 已新增 `DirectPasteService` 处理权限检查、恢复应用、发送 `Cmd+V`
- 确认条目后会复制内容、关闭 `popover`、恢复目标应用并尝试直接粘贴
- 缺少 `Accessibility` 权限时，面板会保留并显示内联提示
- 权限提示现在带 `去授权` 按钮，可直接跳到系统设置的辅助功能页

### 当前行为说明

- 直接粘贴主链路已经接通，当前以文本场景作为已验证基线
- 缺少权限时不会假装成功；用户需要先在系统设置中授予辅助功能权限
- 为减少重复授权成本，后续手工验证应固定运行仓库内 `.deriveddata/Build/Products/Debug/FreePaste.app`
- 最近一轮手工验证确认：曾出现“已切回原应用但没有粘贴”的现象，最终定位为外部软件快捷键冲突，而不是 FreePaste 当前主链路失效
- 当前这轮测试结束时，未再发现新的功能问题

## 代码改动

### 新增文件

- `FreePaste/FreePaste/ClipboardHistoryView/KeyboardEventMonitor.swift`
  - 用于在 `popover` 窗口激活时捕获本地键盘事件

- `FreePaste/FreePaste/ClipboardHistoryView/ClipboardHistoryNavigation.swift`
  - 抽离出的纯状态对象
  - 负责管理焦点位置、选中项、方向键/Tab 的导航逻辑
  - 这是后续继续扩展交互逻辑的推荐入口

- `FreePaste/FreePasteTests/ClipboardHistoryNavigationTests.swift`
  - 针对本轮新增导航逻辑的单元测试

- `FreePaste/FreePaste/DirectPaste/DirectPasteService.swift`
  - 封装辅助功能权限、应用恢复与 `Cmd+V` 发送逻辑

- `FreePaste/FreePaste/AppUIState.swift`
  - 管理 `popover` 内联提示及“去授权”动作

- `FreePaste/FreePasteTests/AppDelegateAndDirectPasteServiceTests.swift`
  - 覆盖前台应用捕获、权限分支与 direct paste 关键路径

- `scripts/build-fixed-debug.sh`
  - 固定构建到仓库内 `.deriveddata`，用于稳定手工验证产物路径

### 修改文件

- `FreePaste/FreePaste/ClipboardHistoryView/ClipboardHistoryView.swift`
  - 接入导航状态
  - 接入键盘事件处理
  - 接入默认选中、搜索结果变化后的重置、确认行为
  - 接入内联错误提示与“去授权”按钮

- `FreePaste/FreePaste/ClipboardHistoryView/ClipboardItemRow.swift`
  - 增加选中态高亮
  - 鼠标点击时同步选中态并触发确认

- `FreePaste/FreePaste/AppDelegate.swift`
  - 统一处理确认动作
  - 记录前台应用
  - 接通 direct paste 流程
  - 接通系统设置跳转

- `FreePaste/FreePaste.xcodeproj/project.pbxproj`
  - 修正测试 target 配置，确保新测试文件被真正纳入 `FreePasteTests`

## 验证结果

### 构建

- `xcodebuild build` 在默认签名配置下会因证书缺失失败
- 已补充固定构建脚本：`./scripts/build-fixed-debug.sh`
- 固定产物路径为 `.deriveddata/Build/Products/Debug/FreePaste.app`

### 测试

- `xcodebuild test` 已通过
- 原有测试保持通过
- 新增 `ClipboardHistoryNavigationTests` 已确认被执行且通过
- 新增 `AppDelegateAndDirectPasteServiceTests` 已确认被执行且通过
- 当前没有为“外部应用快捷键冲突”新增自动化测试，因为该问题属于桌面环境配置冲突，不是应用内可稳定复现的业务分支

### 手工验证

- 本轮手工验证已完成
- 当前未发现新的功能问题
- 已确认需要把“第三方应用快捷键冲突”视为环境排查项，而不是产品缺陷

### 新增测试覆盖点

- 重置时默认选中第一项
- 从搜索框按方向键进入列表
- 列表内部上下移动且不循环
- `Tab` 切换到列表
- `Shift+Tab` 返回搜索框
- 仅当选中项仍然可见时确认才有效
- 忽略 FreePaste 自身前台状态
- 记录有效前台应用作为恢复目标
- 无目标应用时 direct paste 返回明确结果
- 缺少权限时会暴露明确状态与提示
- 权限提示动作会触发系统设置跳转

## 当前未完成

本轮迭代核心目标已完成，以下内容转入后续阶段候选项：

- 评估 direct paste 失败时是否需要更强的用户反馈
- 评估是否需要为权限状态增加首次引导或帮助文案
- 继续扩大真实应用覆盖面，但这不再阻塞本迭代收尾

## 建议下一步

本迭代本身不建议继续追加大改。项目全局的后续优先级已经切换到“弹窗体验与视觉优化”。

### 推荐顺序

1. 用 `./scripts/build-fixed-debug.sh` 构建固定路径产物
2. 若要验证主链路，优先走固定产物路径和当前设置窗口
3. 后续主要精力应投入 `popover` 体验优化，而不是重写 direct paste
4. 视需要再回头补 direct paste 的更强反馈

### 原因

- 本轮核心闭环已经验证通过
- 继续在这一轮迭代上追加实现，收益开始递减
- 当前更缺的是“界面体验完成度”，不是 direct paste 主链路本身

## 接手提示

- 导航逻辑优先改 `ClipboardHistoryNavigation.swift`
- direct paste 相关逻辑优先改 `DirectPasteService.swift`
- View 层只保留状态绑定和事件转发
- 自动化粘贴不要塞进 `ClipboardManager`
- 如果新增测试文件，记得检查 `project.pbxproj` 中 `membershipExceptions` 的 target 配置
- 手工验证时不要再直接运行系统 `DerivedData` 里的临时 `.app`
