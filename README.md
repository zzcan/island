# island

[![release](https://img.shields.io/github/v/release/zzcan/island)](https://github.com/zzcan/island/releases/latest)
![platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

把 Mac 刘海变成 Claude Code 的「灵动岛」:一个常驻屏幕顶部的悬浮胶囊,聚合所有正在运行的
Claude Code 会话状态。哪个会话在干活、哪个在等你输入、哪个已经完成,一眼看清;点一下直接跳回
对应的终端窗口。

## 功能

- **会话聚合** — 同时跑多个 Claude Code 会话时,每个会话的状态(工作中 / 等待输入 / 已完成 /
  空闲)、项目名、最近一条你的提问、Claude 的最新回复、任务清单进度、模型与权限模式,全部汇总
  在刘海下的面板里。
- **像素小人状态指示** — 折叠态的胶囊上,每个会话是一只按状态着色的像素精灵(可选 4 套主题:
  invaders / ghosts / mario / slime,4 种配色:原色 / 荧光绿 / 琥珀 / Game Boy)。
- **点击跳转终端** — 点会话行,自动激活它所在的终端窗口和标签页。支持 iTerm2、Terminal.app
  (AppleScript)、Ghostty(OSC 2 标题 + Accessibility 定位)、tmux(切换 pane)、cmux。
- **计划审查(实验性)** — 拦截 ExitPlanMode,在岛里直接阅读并批准/驳回 Claude 的计划,
  不用切回终端。默认关闭,可在设置中开启。
- **声音与通知** — 会话开始 / 需要输入 / 任务完成时播放合成音效(可分事件开关、调音量、设
  安静时段);需要输入和完成事件可同时发 macOS 横幅通知。
- **菜单栏快速切换** — 菜单栏图标按紧急程度列出全部会话(等待输入的排最前),前 9 个有
  ⌘1–⌘9 快捷键直达。
- **可调外观与行为** — 岛的宽度、位置(可横向拖动)、目标显示器、自动收起时间、字体缩放、
  会话保留时长、按 cwd / 提问前缀过滤会话等,都在设置窗口里。

## 安装

### Homebrew(推荐)

```bash
brew install --cask --no-quarantine zzcan/island/island
```

> `--no-quarantine` 是必需的:island 目前是 ad-hoc 签名(没有 Apple 开发者证书),带隔离
> 标记安装会被 Gatekeeper 拦下。升级用 `brew upgrade --cask island`。

### 直接下载

从 [Releases](https://github.com/zzcan/island/releases/latest) 下载 `island.app.zip`,解压后
拖进「应用程序」,然后清除隔离标记:

```bash
xattr -dr com.apple.quarantine /Applications/island.app
```

### 源码构建

```bash
git clone https://github.com/zzcan/island.git && cd island
./Scripts/bundle.sh        # 产出 build/island.app
```

> 本机默认 Xcode 工具链对本包不可用时,脚本默认走 Homebrew Swift
> (`/opt/homebrew/opt/swift/bin/swift`),可用 `SWIFT=<path>` 覆盖。

## 接入 Claude Code

零配置。island 启动时会自动把随包附带的 `vibe-hook` 注册进 `~/.claude/settings.json`
(`SessionStart` / `UserPromptSubmit` / `Notification` / `Stop` / `SessionEnd` /
`PostToolUse` 六个事件),并在每次启动时自检自愈:app 挪了位置、从源码构建换成 Homebrew
安装,旧路径的残留条目都会被替换成当前路径。注册是幂等的,只动属于 island 的条目,改写前
会留 `settings.json.island.bak` 备份。

启动 island 后新开一个 Claude Code 会话,胶囊里就会出现它。

> 计划审查的 `PermissionRequest` 事件跟随设置中的「计划审查」开关:打开即注册、关闭即摘除
> (对新会话生效)。岛未响应时自动回落到 Claude 自己的终端确认,不会卡住会话。

## 工作原理

```
Claude Code(每个事件调用一次 hook)
   │
   ▼
vibe-hook(Swift 二进制,常驻 app 包内)
   │  · 读 stdin 的事件 JSON(session_id / cwd / tool_name / prompt ...)
   │  · 补全上下文:tmux pane、GUI 终端识别(iTerm2/Terminal/Ghostty)、
   │    会话 tty(沿进程树向上找)、transcript 里的最新回复与模型、
   │    ~/.claude/tasks/<session_id>/ 的任务清单
   │  · 永远 exit 0,绝不阻塞或破坏 Claude 会话
   ▼
Unix socket(~/Library/Application Support/island/run.sock,newline-delimited JSON)
   │
   ▼
island.app(SwiftUI 常驻进程,LSUIElement)
   · SocketServer 收事件 → SessionStore 更新会话模型 → 悬浮岛 / 菜单栏刷新
   · 悬浮窗是置于菜单栏之上的 NSPanel,逐光标 hit-test:只有岛本体接收点击,
     周围区域完全点击穿透
   · 计划审查是唯一的反向通道:vibe-hook 发出请求后阻塞等待,你在岛里
     批准/驳回,结果原路写回,vibe-hook 按 Claude 的协议输出决定
```

会话状态由事件推导:`UserPromptSubmit` → working,`Notification` → needs-input,
`Stop` → done,超过保留时长(默认 30 分钟)的 done/idle 会话自动清出面板;hover 会话行
出现的垃圾桶可手动移除。

## 权限说明

首次使用时 macOS 会请求两项授权:

- **自动化(Apple Events)** — 跳转 iTerm2 / Terminal.app 的窗口和标签页需要。
- **辅助功能(Accessibility)** — 仅 Ghostty 跳转需要(它没有脚本接口,只能按窗口标题定位)。

island 不联网、无遥测,事件数据只在本机的 Unix socket 上流动。

## 开发

```bash
swift build                # 编译(见上文工具链说明)
swift test                 # 跑测试
./Scripts/bundle.sh        # 打包 build/island.app(版本号自动取自 git tag)
```

仓库布局:

| 路径 | 内容 |
|---|---|
| `Sources/IslandCore` | 平台无关核心:会话模型、hook 消息、transcript 解析、跳转计划 |
| `Sources/island` | app 本体:悬浮窗、SwiftUI 视图、socket server、跳转执行、设置 |
| `Sources/vibe-hook` | Claude Code hook 端二进制 |
| `Scripts/` | 打包、hook 安装脚本 |

### 发布流程

版本管理由 [release-please](https://github.com/googleapis/release-please) 全自动驱动:
按 [Conventional Commits](https://www.conventionalcommits.org/)(`feat:` / `fix:`)提交到
main,机器人维护一个累积 changelog 的 Release PR;合并该 PR 即发版——自动打 tag、出
GitHub Release、CI 构建并上传 `island.app.zip`、同步更新
[Homebrew tap](https://github.com/zzcan/homebrew-island)。版本号在打包时由 `git describe`
注入,源码里没有硬编码。

## License

[MIT](LICENSE)
