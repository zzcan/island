# island v1.1 — Floating Island (Dynamic-Island-style overlay) design

- 日期：2026-06-08
- 状态：设计已确认，待实现
- 依赖：v1（菜单栏 + 通知 + 跳转）已完成；本特性复用 `AppModel` / `SessionStore` 状态层

## 背景与目标

v1 只做了菜单栏 + 系统通知，缺了产品同名的招牌——屏幕上的"灵动岛"。
本特性补一个贴在屏幕顶部的悬浮岛：收起时一颗状态胶囊，hover 展开成会话列表，
点击跳转。数据直接绑 v1 的 `AppModel`（`@Published sessions` / `icon`），不改底层逻辑。

成功标准：app 运行时主屏顶部居中出现胶囊；有活跃会话时显示聚合状态 + 数量；
鼠标移上去平滑展开为会话列表；点某行跳到对应 cmux workspace；新通知事件时自动短暂展开；
零会话时整体隐藏；浮岛不抢焦点（不打断终端输入）。

## 组件

```
IslandCore (新增，纯逻辑，可单测)
 └─ IslandViewModel.swift
      struct IslandRow { id, title, status }            // 展开后每行
      struct IslandDisplay { hidden, pillSymbol, pillCount, rows }
      static func IslandDisplay.from(_ sessions:[Session]) -> IslandDisplay

island target (新增，系统副作用，构建+手动冒烟)
 ├─ FloatingIslandPanel.swift   配置 nonactivating NSPanel + NSHostingView(IslandView)
 └─ IslandView.swift            SwiftUI：胶囊 ↔ 列表，.onHover，spring 动画，自动展开

island target (改动)
 ├─ AppModel.swift     新增 @Published var display: IslandDisplay；@Published var eventTick: Int
 │                     refresh() 同时更新 display；handle() 在 post 通知时 eventTick += 1
 └─ IslandApp.swift    启动时创建并显示 FloatingIslandPanel，注入 AppModel
```

## IslandViewModel（纯逻辑，TDD 重点）

`IslandDisplay.from(sessions:)`：
- `hidden = sessions.isEmpty`
- `pillSymbol = IconState.aggregate(sessions).symbolName`
- `pillCount = sessions.count`
- `rows = sessions 按 lastActivity 倒序 → IslandRow(id, title, status)`

## 窗口载体（FloatingIslandPanel）

- `NSPanel`，style `[.nonactivatingPanel, .borderless]`
- `level = .statusBar`（浮在普通窗口之上，菜单栏之下亦可）
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`
- `isOpaque = false`，`backgroundColor = .clear`，`hasShadow = false`
- `isFloatingPanel = true`，`hidesOnDeactivate = false`
- 内容：`NSHostingView(rootView: IslandView().environmentObject(appModel))`
- **不抢焦点**：nonactivating panel，hover/点击不会让 island app 变成前台、不打断终端。

### 定位与尺寸

- 定位主屏（`NSScreen.main`）顶部居中，紧贴菜单栏下方。
- 采用**动态 resize**避开点击穿透难题：面板 frame 跟随当前形态：
  - 收起：胶囊尺寸（约 120×30）
  - 展开：约 320 × (顶部胶囊 + 每行 ~40pt)
- IslandView 通过回调把"期望尺寸/形态"告诉 panel 控制器，由它 `setFrame(_:display:animate:)` 调整并保持顶部居中。
- 这样面板只覆盖可见的岛区域，透明区域不拦截点击。

## IslandView（SwiftUI）

- `@EnvironmentObject var model: AppModel`，`@State private var expanded = false`
- 收起：胶囊 = `Image(systemName: model.display.pillSymbol)` + 若 `pillCount>1` 显示数字，圆角胶囊背景（.ultraThinMaterial / 黑底）。
- 展开：胶囊 + 下方 `ForEach(model.display.rows)`，每行 = 状态点 + 标题，`Button { model.jump(sessionId: row.id) }`。
- 交互：
  - `.onHover { expanded = $0 }`，离开后 ~0.4s 收起（防抖）。
  - 自动展开：`.onChange(of: model.eventTick)` → `expanded = true`，3s 后若未 hover 则收起。
  - `model.display.hidden == true` → 视图空（panel 也隐藏）。
- 动画：`withAnimation(.spring(response: 0.35, dampingFraction: 0.8))` 包裹 expanded 切换；尺寸变化驱动 panel resize。

## AppModel 改动

- 新增 `@Published private(set) var display: IslandDisplay = .from([])`
- 新增 `@Published private(set) var eventTick: Int = 0`
- `refresh()` 末尾：`display = IslandDisplay.from(Array(store.sessions.values).sorted{...})`（或在 from 内排序，二选一，保持单一来源）
- `handle()`：当 `apply` 返回非 nil（要通知）时，`eventTick += 1`（除了 post 通知）
- panel 的显示/隐藏：由 IslandView 依据 `display.hidden` 自行处理，AppModel 不直接操作 panel（保持 AppModel 不依赖 AppKit 窗口）。

## 与菜单栏关系

菜单栏保留（Quit + 兜底列表）。浮岛成为主界面。两者绑同一个 AppModel，自动同步。

## 不在范围（YAGNI）

- 多屏跟随 / 活动屏切换（只主屏）
- 拖动改位置、记忆位置
- 刘海精确贴合形状动画
- 点击面板外部自动收起的全局事件监听（用 hover + 自动收起即可）
- 浮岛内的用量/进度细节（v1 已把用量仪表盘整体推后）

## 测试策略

- **IslandViewModel**：单元测试（Swift Testing）。空→hidden；多会话→pillCount/symbol/rows 排序正确；rows 标题/状态映射正确。
- **FloatingIslandPanel / IslandView**：纯系统副作用，`swift build` 通过 + 手动冒烟（启动 → 合成事件 → 看胶囊出现/展开/点击跳转）。沿用 v1 胶水层的验证方式。

## 开放项（实现时核实）

1. nonactivating + borderless panel 上 SwiftUI `.onHover` 是否稳定触发（borderless panel 的 key/hover 行为）。若不稳，退化为 `NSTrackingArea`。
2. 动态 resize 面板时 SwiftUI spring 动画与 `setFrame(animate:)` 的协调（可能其一即可，避免双重动画打架）。
