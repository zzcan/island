# island — Vibe Island 复刻（Claude Code + cmux）设计文档

- 日期：2026-06-08
- 状态：设计已确认，待 spec review → 出实现计划
- 工作名：`island`（可改）

## 1. 背景与目标

复刻 Vibe Island 的核心体验：一个 macOS 菜单栏小工具，监听 Claude Code 的 hook 事件，
在「干完 / 需要你输入」时弹通知，点通知能跳回正在运行该 agent 的终端会话。

**目标定位：自用。** 因此显式排除（v1 不做）：

- 代码签名 / 公证 / Sparkle 自动更新
- 精致 UI 打磨
- 多 agent（Codex/Gemini/Cursor 等）支持
- Token 用量仪表盘（依赖未公开接口，偏脆，往后放）
- iTerm2 / Terminal.app / VS Code 终端支持

**目标终端环境：cmux，以及 cmux + tmux。**

成功标准：在 cmux 里跑一次真实 Claude Code 会话，菜单栏图标随状态变化，
Stop / 需输入时收到系统通知，点通知能切到正确的 cmux 工作区（嵌套 tmux 时进一步定位到 pane）。

## 2. 技术栈

- Swift / SwiftUI 原生，单个 Xcode 工程，两个 target：
  - `island`（菜单栏 app，`MenuBarExtra`）
  - `vibe-hook`（命令行工具，编译进同工程）
- 不引入第三方依赖。

## 3. 架构

```
island.app  (菜单栏主程序, Swift/SwiftUI)
 ├─ MenuBarExtra UI ····· 图标状态 + 下拉会话列表
 ├─ SocketServer ········ 监听 Unix socket，收 hook 事件，解码成 HookEvent
 ├─ SessionStore ········ 内存维护各会话状态（按 sessionId），纯逻辑状态机
 ├─ Notifier ············ UserNotifications 推送 + 点击回调（协议封装）
 └─ Jumper ·············· 执行 cmux / tmux 跳转（协议封装）

vibe-hook  (命令行 target, Swift, 同工程)
 └─ 读 stdin JSON + 环境变量 → 连 socket 发一条事件 → exit 0

~/.claude/settings.json  (hook 注册，指向 vibe-hook 绝对路径)
```

**socket 路径**：`~/Library/Application Support/island/run.sock`
app 启动时 `unlink` 残留文件后重新创建并监听；`vibe-hook` 连接它。

**职责边界（每个单元可独立理解与测试）：**

- `vibe-hook`：输入 stdin + env，输出一条 JSON 消息发到 socket，不依赖 app 状态。
- `SocketServer`：只收字节 → 解码 `HookEvent` → 交给 `SessionStore`。
- `SessionStore`：纯逻辑状态机，不碰 UI、不碰系统调用（最易测）。
- `Notifier` / `Jumper`：各自封装系统副作用，其它模块通过协议调用以便 mock。

## 4. 事件模型与数据流

### 订阅的 Claude Code hook 事件（v1 精简 5 个）

| Claude Code 事件 | 动作 | 说明 |
|---|---|---|
| `SessionStart` | 注册会话 + 抓上下文 | 记录 cmux/tmux 定位、cwd、可读标题（目录名） |
| `UserPromptSubmit` | 状态 → working | 刚发 prompt，开始干活 |
| `Notification` | 状态 → needsInput + 推通知 | Claude 要权限/等输入时发，核心通知点 |
| `Stop` | 状态 → done + 推通知 | 一轮回答结束，核心通知点 |
| `SessionEnd` | 移除会话 | 从列表清掉 |

> `PreToolUse/PostToolUse` v1 不订阅（working→done 已覆盖循环），后续想看「正在调哪个工具」再加。

### vibe-hook 消息格式（JSON over unix socket，一行一条）

```json
{
  "event": "Notification",
  "sessionId": "abc123",
  "cwd": "/Users/zzcan/proj",
  "title": "proj",
  "message": "Claude needs your permission…",
  "cmux": { "workspaceId": "...", "surfaceId": "...", "socketPath": "/tmp/cmux.sock" },
  "tmux": { "pane": "%3", "window": "1", "session": "main" }
}
```

- `message` 仅 `Notification` 事件有；`tmux` 仅当 `$TMUX` 存在时有。
- cmux 三件套（`CMUX_WORKSPACE_ID` / `CMUX_SURFACE_ID` / `CMUX_SOCKET_PATH`）直接读 hook 进程的环境变量
  （hook 是 agent shell 的子进程，天然继承）。
- tmux：`$TMUX` 存在时执行一次 `tmux display-message -p '#{pane_id}/#{window_index}/#{session_name}'` 抓取。

### 会话状态机（SessionStore，纯逻辑）

```
idle → (UserPromptSubmit) → working → (Stop)         → done*
                                    └→ (Notification) → needsInput*
*done / needsInput 触发通知；再次 UserPromptSubmit 回到 working
```

### 菜单栏图标聚合

所有会话状态聚合：

- 有任意 needsInput / done 未读 → 「需注意」
- 否则有 working → 「忙」
- 否则 → 「空闲」

每条通知带 `sessionId`，点击交给 Jumper。下拉菜单列出当前活跃会话（标题 + 状态 + cwd）。

## 5. 跳转模块（Jumper）

点通知后按顺序执行：

1. **切 cmux 工作区**：`cmux select-workspace <workspaceId>`，并把事件里的 `CMUX_SOCKET_PATH`
   设进子进程环境；若 cmux 支持选 surface，带上 `surfaceId`。
2. **（若有 tmux）钻进 pane**：`tmux select-pane -t <pane_id>`（用全局唯一 pane id，跨 window 直接定位；
   必要时先 `select-window`）。
3. **窗口置顶**：`NSWorkspace` 按 bundle id `com.cmuxterm.app` 激活 cmux 到前台。无需 TCC 授权。

> **待核实（实现第一步）**：`cmux select-workspace` 的确切参数、能否选 surface/split。
> 先用真实 cmux 验证一条命令再封进 Jumper。非阻塞项。

## 6. 错误处理

原则：**hook 绝不拖累 Claude Code。**

- `vibe-hook` 永远 `exit 0`、永不阻塞：连 socket 设短超时（~200ms），app 未运行/连不上则静默退出；
  任何异常一律吞掉。
- app 启动时先 `unlink` 残留 socket 文件再监听，避免「地址被占用」。
- 跳转失败（workspace 不存在 / cmux 未运行 / tmux 命令失败）→ 记日志、降级为不操作，不向用户抛错。
- 会话清理：`SessionEnd` 移除；app 启动清空旧会话；兜底：超过 12 小时无活动自动 prune。
- 通知权限：首次启动申请；被拒不影响菜单栏状态显示（优雅降级）。
- 多 agent 并发：全程按 `sessionId` 区分，天然支持多会话并存。

## 7. 测试策略

「纯逻辑严测，系统副作用薄封装 + 手动冒烟」分层：

| 模块 | 方法 |
|---|---|
| SessionStore（状态机） | 单元测试，TDD 重点。事件序列 → 断言状态转换与聚合图标状态 |
| HookEvent 解码 | 单元测试：各种 JSON → struct，含缺字段/脏数据 |
| vibe-hook 消息构造 | 抽 `buildMessage(stdin, env) → JSON` 纯函数测；socket 发送层很薄 |
| Jumper | 注入 `CommandRunner` 协议，断言构造出的 cmux/tmux 命令正确（不真跑）；真实命令手动验证一次 |
| Notifier | 协议封装，断言用正确 sessionId 发通知；真实横幅手动看 |
| SocketServer | 集成测试：临时 socket 起 server，连上发一行 JSON，断言 SessionStore 收到并更新 |
| 端到端 | 手动冒烟：注册 hook → cmux 里跑真实 Claude Code → 看图标/通知/点击跳转 |

原则：能做成纯函数的（状态机、消息构造、命令构造）TDD 严测；带系统副作用的
（通知、跳转、socket）用协议留缝 + 少量集成测试 + 一次手动验证。

## 8. 明确不在 v1 范围（YAGNI）

- 签名 / 公证 / 自动更新
- 多 agent（Codex/Gemini/Cursor/opencode 等）
- Token 用量仪表盘
- iTerm2 / Terminal.app / VS Code 终端
- 偏好设置 UI（路径/阈值先写死或用 UserDefaults 默认值）

## 9. 待实现时核实的开放项

1. `cmux` CLI 切换工作区/surface 的确切命令与参数。
2. Claude Code `Notification` 事件的实际触发时机与 payload 字段（用真实会话确认）。
3. hook 进程是否稳定继承 `CMUX_*` 与 `$TMUX`（应当继承，需实测确认）。
