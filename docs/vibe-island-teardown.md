# Vibe Island 逆向梳理 & 我们可借鉴清单

> 分析对象：`/Applications/Vibe Island.app` v1.0.37 (build `18d77aaf`)
> 方法：Mach-O / 字符串 / 资源 / 本地化 / 内嵌脚本静态分析（未运行、未脱壳）。
> Bundle ID `app.vibeisland.macos`，作者 edwluo（vibeisland.app）。

---

## 1. 它是什么

一个常驻菜单栏（`LSUIElement=1`）的 macOS "灵动岛" 应用，把多个 AI 编码 CLI（Claude Code / Codex / Gemini / OpenCode 等）的会话状态聚合到刘海下的悬浮面板里：

- **一眼看全部会话**：每个会话的状态、标题、当前动作、任务进度。
- **点击跳转**：点会话卡 → 跳到对应终端窗口/标签/IDE。
- **就地审批**：权限请求、AskUserQuestion、ExitPlanMode 直接在岛里 Approve/Deny/答题，不用切回终端。
- **声音 + 通知**：会话开始/完成/需要输入/用量告警等事件播音效。
- **付费授权**：一次性买断 $19.99（LemonSqueezy + Early Bird），2 天试用。
- **SSH 远程**：把会话从远程服务器/Docker 转发回本机岛里。
- **用量监控**：读取 Claude / Codex / Kimi / 智谱 的订阅额度。

我们的 `island` 项目是它的精简重写：核心的"会话聚合 + 悬浮岛 + 跳转 + 音效"都有，但**审批、多 CLI、远程、用量、授权、声音包**等大块功能还没有。

---

## 2. 技术栈 & 系统 API

来自 `otool -L` 的链接库，推断各自用途：

| Framework | 用途 |
|---|---|
| SwiftUI / AppKit / QuartzCore | 全部 UI、悬浮 NSPanel、动画 |
| Combine / Observation | 状态驱动（`@Observable`） |
| AVFAudio / CoreAudio | 音效播放 + 声音包 |
| UserNotifications | 系统通知横幅 |
| **ApplicationServices / Carbon** | **Accessibility 扫描**（检测 Codex Desktop 审批弹窗）、全局快捷键（Carbon HotKey） |
| **ServiceManagement** | 开机自启（SMAppService） |
| **Security / CryptoKit** | License 校验、签名验证（trust chain）、密钥存储 |
| **CoreData / libsqlite3** | 会话/事件持久化 |
| **SystemConfiguration** | 网络可达性（license/usage 网络错误分类） |
| **Sparkle.framework** | 自动更新（appcast + EdDSA 公钥签名） |
| MetricKit / IOKit | 崩溃/能耗指标、硬件 ID（机器指纹用于授权） |

**第三方/外部服务**（字符串里挖到的 endpoint）：

- 更新：`updates.vibeisland.app/appcast.xml`、hook 二进制走 GitHub Releases（`github.com/edwluo/vibe-island-updates`）。
- 遥测：**PostHog**（`us.i.posthog.com/capture/`）+ **Sentry**（菜单里有 "Test Sentry"）。
- 授权：**LemonSqueezy**（`app.lemonsqueezy.com/my-orders`）。
- 用量 API：`api.anthropic.com/api/oauth/usage`、`api.kimi.com`、`api.z.ai` / `bigmodel.cn`（智谱）。
- 声音包注册表：**PeonPing Registry**（GitHub Pages，社区贡献的 CESP 声音包）。
- 社区：Discord、微信群、飞书群（二维码图片随包）。

---

## 3. 核心架构：事件如何从 CLI 流到岛里

```
┌─────────────────────────────────────────────────────────────────┐
│  AI CLI (Claude Code / Codex / Gemini / OpenCode / Cursor ...)    │
│                                                                   │
│  Vibe Island 自动往各 CLI 的配置里注入 hook：                       │
│   ~/.claude/settings.json      (JS/py 脚本)                        │
│   ~/.codex/hooks.json          (base64 内嵌)                       │
│   ~/.gemini/settings.json                                         │
│   ~/.cursor/hooks.json  + .factory/.qoder/.qwen/.copilot ...      │
│   ~/.config/opencode/plugins/vibe-island.js  (插件)               │
└───────────────┬───────────────────────────────────────────────────┘
                │ hook 事件 (PreToolUse/PostToolUse/SessionStart/
                │           Stop/UserPromptSubmit/Notification/
                │           SessionEnd/PermissionRequest)
                │ 统一成 Claude 风格 JSON: {hook_event_name, session_id,
                │   cwd, tool_name, tool_input, prompt, ...}
                ▼
   本地：HTTP POST  →  http://127.0.0.1:4096/global/event
                       (端口可配 VIBE_ISLAND_PORTS；也有 unix socket
                        /tmp/.vi-<hash>.sock 兜底)
                ▼
┌───────────────────────────────────────────────────────────────────┐
│  Vibe Island.app（Swift 主进程）                                    │
│  · 内置 HTTP server :4096，收事件 → 更新会话模型 → 刷新悬浮岛        │
│  · 反向回调：审批/答题结果发回                                       │
│      POST /permission/{id}/reply                                   │
│      POST /question/{id}/reply                                     │
└───────────────────────────────────────────────────────────────────┘

   远程(SSH)：Go 写的 vibe-island-hook-{darwin,linux,freebsd}-{amd64,arm64}
              上传到远端 → 远端 CLI 事件经它转发 → SSH 隧道(TCP 17892 可配
              或 Unix Socket) → fan-out 回本机 :4096
```

要点：

- **本地 hook 用内嵌脚本**（JS / Python，直接写进各 CLI 配置），不是单独二进制；事件走 **HTTP POST 到 127.0.0.1:4096**。
- **远程 hook 是 Go 静态二进制**（`go1.25.7`，6 平台全覆盖），定位 `vibeisland.app/remote-hook/forward.go`，是个**转发器**：`--source claude|codex|gemini`、`--host`、`--listen`、`--setup`（Docker/Podman 专用）。环境变量 `VIBE_ISLAND_HOST/PORT(S)/SOCKET`。
- **HookWatcher**：监测自己的 hook 被别的工具改掉/删掉，自动恢复（`hookWatcher.restored`）。
- **Codex 信任**：Codex 新版本要求插件 opt-in，应用会通过 Codex 自己的 config API 自动授权，失败则提示 `/hooks` 手动信任。

> 对比我们：`island` 用 **Unix socket（`~/Library/Application Support/island/run.sock`）+ 单独的 `vibe-hook` Swift 二进制**，只对接 Claude Code，事件靠 tmux/cmux 环境变量补全。架构更简单，但耦合在 Claude + tmux/cmux。

---

## 4. 完整功能清单（按本地化 key 还原，756 行 strings 全覆盖）

### 4.1 会话面板
- 折叠岛：状态字形 + 会话数；展开面板：每会话标题/cwd/模型徽章/终端徽章/耗时/当前动作/任务进度。
- 状态机：`waitingForInput / processing / thinking / runningTool / waitingForApproval / question / compacting / ended`。
- 任务块：`Tasks (X done, Y in progress, Z open)`，对接 Claude 的 TodoWrite。
- 子代理：`Running %d agent(s)`、Agent Team 成员完成可选触发展开/音效。
- 空态文案、"Show all N sessions"、右键卡片可隐藏会话。
- **两种布局**：Clean（省菜单栏空间）/ Detailed（标题+状态）。

### 4.2 跳转（点击 → 终端/IDE 定位）
集成的目标（来自 bundle id 字符串）：Apple Terminal、iTerm2、Ghostty、Kitty、Warp、Termius、VSCode/Insiders、Cursor、Codex Desktop、cmux。
- 机制混合：**AppleScript/JXA**（`osascript -l JavaScript`）+ **URL scheme**（`codex://threads/`、`warp://`）+ **IDE 扩展**（精确跳标签，需装扩展）+ **Kitty 改 kitty.conf 2 行** + 自定义 URL scheme 注册（第三方终端可接入，`docs/custom-jump-rules`）。
- 需要 **Automation 权限**（`NSAppleEventsUsageDescription`）；有 Warp Tab Jumping 实验开关。

### 4.3 就地审批 / 答题（我们完全没有的核心能力）
- **权限审批卡**：Continue in Terminal / Deny / Allow Once / Always Allow / Allow All / Bypass / Auto。
- **AskUserQuestion 向导**：多问题分步、单选/多选、Submit All。
- **ExitPlanMode**：Bypass Permissions / Auto-accept Edits / Manually Approve + 给 Claude 反馈输入框。
- 审批目标可路由：Claude/Codex 可选"原生终端审批"或"岛内卡片"；Codex 支持 **Accessibility 扫描** Desktop 审批弹窗；Cursor 读它的 YOLO 配置自动决策；Kiro 有"工具运行 N 秒后提示审批"。

### 4.4 声音
- 10 类事件音（sessionStart/taskComplete/taskError/inputRequired/idleReminder/userSpam/usageWarning/usageReset/...），每类可选音源：Off / 内置 8-bit / Apple 系统音 / 自定义导入。
- **声音包（v2）**：主题切换、Editor's Picks、CESP 包导入（.zip/文件夹）、PeonPing 社区注册表。
- **静音时段 Quiet Hours**（跨午夜）、音量、**探针会话自动静音**（CodexBar/ClaudeProbe 健康检查）。

### 4.5 通知过滤（Admission / Silence）
- 内置过滤器（Codex 记忆整理、Memory Writer、Guardian/AutoReview、Chronicle、Claude-Mem 等后台会话默认隐藏）。
- 自定义过滤：按 **工作目录** 或 **首条 prompt**（前缀/包含）；右键会话即可加规则；**实时预览命中数**。
- 按启动器 App Bundle 屏蔽（后台探针类）。

### 4.6 用量监控（Usage）
- 在岛头显示订阅额度（Used/Remaining，阈值告警一次性 peek）。
- 多 provider：Claude / Codex / Kimi / 智谱，Auto 跟随当前会话。
- **Claude Usage Bridge**：Claude 用量只在 statusline 里，应用会**可逆地**往 statusline 脚本插一段标记块来读取（兼容 Claude HUD，备份+一键移除）。

### 4.7 授权 / 商业化
- 一次性买断（1/2/3 Mac 档），Early Bird 锁定到安装；2 天试用；机器指纹 + 设备管理（Manage Devices / Deactivate）；LemonSqueezy 下单 → 邮件发 key → 粘贴激活。
- License 网络错误细分（timeout/no internet/TLS/trust chain/...）。彩蛋版本号（FOUNDER/PIONEER/...）。

### 4.8 SSH 远程
- 添加 Host → Set Up（上传 Go 二进制 + 配 CLI hook）→ Connect（SSH 隧道）。
- 支持 bastion/ProxyCommand/MFA(ControlMaster)/非标端口/指定 key；TCP（通用，配 GUI SSH 客户端）或 Unix Socket（仅命令行 ssh）；多 Mac fan-out；离线/air-gapped 手动安装；Docker/Podman 容器一键脚本；远端 hook 自动更新。

### 4.9 其它
- Sparkle 自动更新（自动检查/自动安装可关，面板上有 ↑ 按钮）、Beta 通道、Beta 过期提示。
- 诊断报告导出（系统信息+匿名日志）、PostHog/Sentry 遥测（可关 "Help Improve"）。
- 全局快捷键：Alfred 风格 Switcher（↑↓+Enter）、⌘Tab 风格循环、反向切换；面板内审批/导航/折叠全可绑快捷键。
- 多显示器（主屏/跟随焦点/指定屏）、刘海尺寸微调、字号、Pass（凭证展示）、5 国本地化（en/zh-Hans/ja/ko/fr）。
- "Remove All Auto-Configuration"：一键卸载所有 CLI hook + IDE 扩展 + 运行时文件，干净退出。
- 自定义 CLI 分支路径（Claude Code fork / Codex branch / Hermes / Antigravity / Kiro / Factory / Qoder / Qwen / Copilot / CodeBuddy）。
- Labs：高内存自动重启、空闲会话清理（针对无关闭信号的 Codex/OpenCode/Cursor）。

---

## 5. 我们 island 可借鉴的（按性价比排序）

### 🟢 投入小、收益大（建议先做）

1. **就地审批 / 答题** — Vibe Island 最核心的差异化。我们目前只读不写、纯展示 permission mode。
   做法：`vibe-hook` 在 `PreToolUse`/`Notification` 时**阻塞等待** socket 回包，岛里加 Allow/Deny 按钮，结果经反向通道写回。是把 island 从"看板"变成"控制台"的关键一跃。

2. **通知过滤（目录 / 首条 prompt + 右键加规则 + 实时预览）** — 我们已有 `cwdFilters/promptFilters`，但缺右键快捷加规则和命中数预览，补齐成本低、日常体验提升明显。

3. **探针/后台会话自动静音** — 内置一组规则（memory writer、guardian、health probe 等），避免后台 agent 刷屏。纯规则，几乎零成本。

4. **Quiet Hours** — 我们已有！可对齐"跨午夜 + 当前静音中"提示文案。（已具备，仅打磨）

5. **诊断导出 + 一键移除所有配置** — `Remove All Auto-Configuration` 这种"干净卸载"对早期用户信任很重要，实现简单。

### 🟡 中等投入（看路线）

6. **多 CLI 支持（至少 Codex + Gemini）** — 我们只接 Claude。可学它的"统一成 Claude 风格事件 + 各 CLI 注入 hook"。注意 Codex 的信任/授权坑。

7. **HTTP 本地端口替代/补充 Unix socket** — socket 简单但跨进程/远程不友好。Vibe 用 `:4096` HTTP 让远程转发、多端 fan-out 成为可能。若以后要做远程，HTTP 更顺。

8. **HookWatcher（自愈）** — 监测自己的 hook 被别的工具覆盖并自动恢复，对"hook 互相打架"很实用。

9. **音源可选 + 声音包** — 我们现在是固定合成音。先做"每事件可选 Off/内置/Apple 系统音"，声音包注册表可后置。

10. **全局快捷键 Switcher（⌘Tab/Alfred 风格）** — 用 Carbon HotKey，能脱离鼠标 hover 快速切会话/审批。

### 🔴 大工程（按需）

11. **SSH 远程转发** — 价值高但复杂（Go 转发器 + 隧道 + Docker + air-gap）。只在确实有远程开发场景时做。

12. **用量监控 + Usage Bridge** — 涉及多家 API + 改 statusline，维护成本高。

13. **授权/商业化（Sparkle + LemonSqueezy + 设备指纹）** — 只有要卖钱才做。Sparkle 自动更新可以单独先上（开源免费也用得上）。

### 体验小抄（顺手就能抄）
- **两种布局 Clean/Detailed** 切换；多显示器/跟随焦点；刘海尺寸微调（应对非标机型）。
- **状态文案体系**（thinking/compacting/needs approval/...）比我们现在的状态更细。
- **Sprite/主题** 我们已经做得比它丰富（10 套像素主题），这是我们的长板，保持。

---

## 6. 备注 / 取证边界
- 全部结论来自静态分析（Mach-O 头、`strings`、bundle 资源、本地化文件、内嵌 JS/shell 片段）。**未运行、未脱壳、未抓包**，端口/协议/字段名以二进制里出现的字面量为准，实际运行时行为可能有出入。
- License/设备指纹/遥测仅为"识别存在"，未做绕过分析。
- 仅供我们自研 island 的功能参考，勿直接拷贝其商标资源（图标/二维码/声音包）。
