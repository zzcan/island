# island v1.2 — Full Vibe Island UI parity

- 日期：2026-06-09
- 目标：展开面板视觉上尽量等同真品 Vibe Island（参照用户提供的真品展开截图 image 3）。
- 用量条决策：**先做外观 + 占位数字**，真实 Anthropic 用量接口以后再接。

## 真品展开面板结构（参照）

```
┌───────────────────────────────────────────────────────────────┐
│ ✳ 5h 37% 46m   7d 7% 5d9h                          🔊  ⚙️       │  ← 用量条
│                                                                 │
│ [▣]  island · ~/proj/login        [自动批准][Claude][cmux] <1m  │  ← 头像+标题·cwd+徽章+时长
│      你：重构登录模块的鉴权逻辑                              ●    │  ← prompt + 状态点
│      ⌁ Read /tmp/island-top.png                                 │  ← 当前动作(蓝)
│ ─────────────────────────────────────────────────────────────  │
│ [▣]  api  · ~/proj/api            [自动批准][Claude][cmux] 3m    │
│      你：加个限流中间件                                      ●    │
└───────────────────────────────────────────────────────────────┘
```

## 部件与数据来源

| 部件 | 来源 | 备注 |
|---|---|---|
| 用量条 | 占位（"5h --% --   7d --% --" 或示例值）+ 🔊 ⚙️ 图标 | 真接口以后接；图标可不绑动作 |
| 像素头像 identicon | `Identicon.make(seed:)` 纯函数（IslandCore，可测） | seed = sessionId 或 cwd；生成对称像素格 + 色相 |
| 标题 · cwd | `IslandRow.title` + `IslandRow.cwd`（缩写 ~ 路径） | cwd 已在 Session |
| 徽章 自动批准/Claude/终端/时长 | 自动批准=静态显示；Claude 静态；终端=cmux/tmux；时长=lastActivity | 自动批准先静态（用户用自动批准模式） |
| prompt 行 | `IslandRow.prompt`（已有） | |
| 当前动作行 | `IslandRow.action`（新，来自 PostToolUse） | 蓝色，"⌁ Read <arg>" |
| 状态点 | `IslandRow.status`（已有） | |

## 数据管线新增

1. **PostToolUse 事件**：
   - `IslandEvent` 增 `.postToolUse = "PostToolUse"`。
   - `ClaudeHookInput` 增 `tool_name: String?` 和 `tool_input: ToolInput?`（`ToolInput { file_path, command, pattern, path: String? }`）。
   - `HookMessage` 增 `action: String?`；`build` 对 postToolUse 组装 action = `tool_name + " " + 短化(arg)`，arg 取 file_path ?? command ?? pattern ?? path。
   - `Session` 增 `lastAction: String?`；`apply` 对 `.postToolUse`：status=.working、存 lastAction、**不发通知**。
   - `install-hooks.sh` events 列表加 `PostToolUse`。

2. **cwd / action 上行到行模型**：`IslandRow` 增 `cwd: String?`、`action: String?`（默认值，避免破坏既有构造）。`IslandDisplay.from` 映射。

3. **Identicon（纯逻辑，可测）**：
   - `Identicon.make(seed: String, size: Int = 5) -> IdenticonGrid`
   - `IdenticonGrid { let cells: [[Bool]]; let hue: Double }`（左右对称；hue 0..1 由 seed 哈希得到）
   - 确定性：同 seed 同结果（可单测）。

## 视图（island target）

重建 `IslandView.expandedPanel`：
- 顶部用量条 row：✳ 图标 + 占位文本（绿色百分比样式）+ Spacer + 🔊 + ⚙️。
- 每行：HStack[ 头像(IdenticonView ~28pt 渲染 grid) | VStack[ 标题·cwd + 徽章 + 时长 ; prompt ; action(蓝, 有则显示) ] | 状态点 ]。
- 深色半透明、圆角 ~22、宽 ~460、行间细分隔。
- 收起态保持 v1.1 的彩色点胶囊（已完成）。

## 不变 / 不做
- 收起态已是方案 A（彩色点），保留。
- 用量条真实数据、自动批准真实判定 → 以后。
- 多屏 / 其它终端 / 其它 agent → 仍不做。

## 测试
- `Identicon.make` 纯函数：确定性、对称性、hue 范围。
- `HookMessage.build` postToolUse → action 组装正确（含取 arg 优先级、短化）。
- `SessionStore.apply` postToolUse → lastAction 存储、status=working、无通知。
- `IslandDisplay.from` 映射 cwd/action。
- 视图：构建 + 截图人工对照。
