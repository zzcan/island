# Changelog

## [0.1.5](https://github.com/zzcan/island/compare/v0.1.4...v0.1.5) (2026-06-16)


### Bug Fixes

* **app:** restart audio engine after config changes so sounds keep playing ([114024c](https://github.com/zzcan/island/commit/114024cfdad368cd55425cc7cc4e27be2ec43692))

## [0.1.4](https://github.com/zzcan/island/compare/v0.1.3...v0.1.4) (2026-06-12)


### Features

* **app:** auto-expand mode picker in behaviour settings ([f4d0e11](https://github.com/zzcan/island/commit/f4d0e11083fea61221be36c92f6725c840de68ee))
* **app:** gate event auto-expand behind AutoExpandMode setting ([ae068c0](https://github.com/zzcan/island/commit/ae068c0f7eef7b7c2b6ac48377e371b4e6516690))
* **core:** AutoExpandMode policy enum ([18dc67c](https://github.com/zzcan/island/commit/18dc67c1f2a1b00bd25af089acb0cf1d1ed100a5))

## [0.1.3](https://github.com/zzcan/island/compare/v0.1.2...v0.1.3) (2026-06-11)


### Features

* **app:** Sparkle auto-updates ([97842bb](https://github.com/zzcan/island/commit/97842bb850f8f7201ccb29404b64d99cc3f79d31))

## [0.1.2](https://github.com/zzcan/island/compare/v0.1.1...v0.1.2) (2026-06-11)


### Features

* **app:** auto-register Claude Code hooks on launch ([deab0a9](https://github.com/zzcan/island/commit/deab0a9ea58e05ae1ebd2339ff11798a8ea3c205))
* **dist:** move Homebrew cask to zzcan/homebrew-island tap ([9aae57a](https://github.com/zzcan/island/commit/9aae57a31ca42d79b42a9fb659e3e7ab553be5ed))

## [0.1.1](https://github.com/zzcan/island/compare/v0.1.0...v0.1.1) (2026-06-11)


### Features

* **dist:** distribute via Homebrew cask, auto-bumped on each release ([e9e9d70](https://github.com/zzcan/island/commit/e9e9d70ac17b6a8fba59c0b841908bfd06b5e1b2))

## 0.1.0 (2026-06-11)


### Features

* **app:** AF_UNIX SocketServer delivering HookMessage on main queue ([19e5bcf](https://github.com/zzcan/island/commit/19e5bcfcf51ef0b7de402fcf8cc7086916b2eba9))
* **app:** AppModel publishes IslandDisplay + eventTick for floating island ([5b9489e](https://github.com/zzcan/island/commit/5b9489e8d6af93b1a32c4c80610d0adbd6bdb598))
* **app:** AppModel wires socket -&gt; SessionStore -&gt; UI + notifications ([bc47fd3](https://github.com/zzcan/island/commit/bc47fd37a552cda40555d0f820ba3b3cfeff3d41))
* **app:** collapsed bar corner radius 8 ([1b0eb36](https://github.com/zzcan/island/commit/1b0eb36cf5ea1bb68532e7e811a89ceb46e940a8))
* **app:** collapsed bar height 40, uniform corner radius ([a63d1d5](https://github.com/zzcan/island/commit/a63d1d55a91602b11ef0455873c0092006b3febe))
* **app:** collapsed bar matches Vibe Island — narrower, shorter, notch-hanging shape (square top, rounded bottom) ([68f75c3](https://github.com/zzcan/island/commit/68f75c304d01a08be30a408648dd129067f13141))
* **app:** collapsed bar shows only the latest session's status glyph + count ([d722267](https://github.com/zzcan/island/commit/d722267e29b8da434d002801c08a82b2274b4b2a))
* **app:** collapsed bar width 240, height 34 ([8e70c5c](https://github.com/zzcan/island/commit/8e70c5ccec27ac340e56dee9382f5d068f30dc8b))
* **app:** collapsed island = wide black bar (equalizer glyphs + count), like Vibe Island ([4930843](https://github.com/zzcan/island/commit/4930843196e2e3586b4b3aa5b54b8f7098230f0d))
* **app:** drag the island horizontally to reposition it ([09c9ca1](https://github.com/zzcan/island/commit/09c9ca16f3c4ef9882ff7d4727e51a4a3cb6c7a3))
* **app:** Dynamic-Island-style morph animation (single container, bouncy spring, scale+fade) ([03fb03f](https://github.com/zzcan/island/commit/03fb03f9cf67282bdb4e30eda2c995170f3ec7b1))
* **app:** expanded panel solid black background (match Vibe Island) ([5c48018](https://github.com/zzcan/island/commit/5c480188eeb2b5c9a71dbc4cb711617f80663413))
* **app:** expanded rows show equalizer avatar + assistant line + live task block ([21a9a11](https://github.com/zzcan/island/commit/21a9a1111ffd21a3046eed6a95e3f9dc289a526d))
* **app:** floating Dynamic-Island-style panel (top capsule, hover-expand) ([14f868c](https://github.com/zzcan/island/commit/14f868cfee2f38aa45be22d4ec645788e6fa4864))
* **app:** handle token expiry by skipping the request (no self-refresh) ([6be94ec](https://github.com/zzcan/island/commit/6be94ec1755c4174e7ed1814a3de3932168c7780))
* **app:** hover trash icon to dismiss a session from the panel ([259a7a5](https://github.com/zzcan/island/commit/259a7a5c2fb6ea88f161c7aba95f163cfae65684))
* **app:** Jumper runs cmux/tmux commands + activates cmux ([80ca17a](https://github.com/zzcan/island/commit/80ca17a0dfcda905b7a8e582c9203e4a11a7d260))
* **app:** MenuBarExtra UI + App entry point (idempotent start) ([85a6018](https://github.com/zzcan/island/commit/85a6018f598b762e295bc1080561fd07b69b0b84))
* **app:** Notifier (UNUserNotificationCenter) with click -&gt; sessionId ([479efaa](https://github.com/zzcan/island/commit/479efaa3e4af528a27e41617ce2dfdb7ac837c7f))
* **app:** only prune residual done/idle sessions, keep active ones forever ([9ef6a20](https://github.com/zzcan/island/commit/9ef6a2090083c8c8bfdc649cd6a427c65aa3798a))
* **app:** periodically prune residual sessions ([9a04781](https://github.com/zzcan/island/commit/9a047818ccffa2e3c6ee545bea3926fbba4b3a28))
* **app:** polish collapsed island — per-session status dots, black notch pill, pulse/glow ([8f364ce](https://github.com/zzcan/island/commit/8f364ce6c2cc2902f51abb273eb7fb83fb802ada))
* **app:** polish floating island UI to match Vibe Island (status glyph, elapsed time, translucent) ([ab5194a](https://github.com/zzcan/island/commit/ab5194a622f39a861fae51df78db01aaffb0f7f5))
* **app:** raise island to the very top (notch/menu-bar strip) like a Dynamic Island ([ce0e975](https://github.com/zzcan/island/commit/ce0e975c9095edeb00557b716587c02b6146fe4d))
* **app:** real auto-approve badge from permission_mode ([4fabfdd](https://github.com/zzcan/island/commit/4fabfdd7714590f7040f1fe3f1c5df9e3e4e2d08))
* **app:** real model badge from transcript instead of hardcoded 'Claude' ([1c2c77d](https://github.com/zzcan/island/commit/1c2c77db1f756db5a4e1806c7e75add0e6d5c004))
* **app:** real usage bar from /api/oauth/usage (route A) ([57a0221](https://github.com/zzcan/island/commit/57a022133ee0a41c7bfd1d9ecf17d0e20dfc68ab))
* **app:** rebuild expanded island panel to match Vibe Island (usage bar, avatars, full rows) ([f8d4ef0](https://github.com/zzcan/island/commit/f8d4ef0ee67b3c8b1a0b6c8b9b2d09542ebb36c8))
* **app:** refine expand/collapse motion — asymmetric springs, curtain clip reveal, decoupled opacity, staggered row cascade ([00d1eed](https://github.com/zzcan/island/commit/00d1eed6ca30e8090a3c900afbefeaff0ff3aa12))
* **app:** remove subscription usage stats from the expanded panel ([0e01538](https://github.com/zzcan/island/commit/0e0153867893071003ff46a4e6603e48d9dbb136))
* **app:** settings window, plan review, terminal jump, app icon, and sound ([42890f6](https://github.com/zzcan/island/commit/42890f64de8fd1302cd0e231ed103fc3a6bad94a))
* **app:** status-coded equalizer — 4 distinct colors + per-state motion (working bounce / needsInput blink / done settle / idle low) ([372fb95](https://github.com/zzcan/island/commit/372fb95a5a414f21efaa3d06e0c65f14d1dcd911))
* **app:** tune morph to match real Vibe Island (faster ~0.3s, less bounce) ([348ecad](https://github.com/zzcan/island/commit/348ecade19d71ed8566a79451160db3db1efb55d))
* **app:** widen and enlarge the expanded panel, add row hover highlight ([dae373d](https://github.com/zzcan/island/commit/dae373d6fe1fe9c1f8812d7c69a15104aa7c994a))
* **core:** add deterministic Identicon generator (TDD) ([7ec0b35](https://github.com/zzcan/island/commit/7ec0b354b6c70a7db28716e7fb8619740f0eaf92))
* **core:** add TaskItem, TaskSummary, and TranscriptParser pure types ([50a5734](https://github.com/zzcan/island/commit/50a5734fc0ae90d5d42b07cbd699047bdb75785a))
* **core:** Command, CommandRunner protocol, JumpPlan command builder ([877a57c](https://github.com/zzcan/island/commit/877a57c769edc7880f03074717cf7dcd2aceef5a))
* **core:** HookMessage wire format + pure build(stdin,env,tmux) ([e7e2def](https://github.com/zzcan/island/commit/e7e2def46547b78741e53996e1646a6f0a65481e))
* **core:** IslandEvent + ClaudeHookInput decoding ([7eae939](https://github.com/zzcan/island/commit/7eae939eb074aa09d721dfcf5c994b242a5056c2))
* **core:** IslandViewModel (IslandDisplay/IslandRow) pure mapping ([66c05a0](https://github.com/zzcan/island/commit/66c05a0c244b6dd9b93a6c3df05407bcd76ee107))
* **core:** plumb assistantText + tasks through HookMessage → Session → IslandRow ([0820048](https://github.com/zzcan/island/commit/0820048e1f4d13630f5816b085c115373698cc7a))
* **core:** PostToolUse event → current-action capture + IslandRow plumbing ([f446c07](https://github.com/zzcan/island/commit/f446c07ce837340a5cc0fcac16b8c2adbb1d8b2d))
* **core:** Session, SessionStatus, contexts, IconState.aggregate ([a546f7a](https://github.com/zzcan/island/commit/a546f7ad8c274968216f9fbce74df3e6bad16cbc))
* **core:** SessionStore state machine + NotificationRequest ([4dadba8](https://github.com/zzcan/island/commit/4dadba8b7884de833604ad5904cdb242e642c833))
* **core:** SocketPath, ProcessRunner, UnixSocketClient helpers ([8e26291](https://github.com/zzcan/island/commit/8e26291e6e6e76e81a824afd3584bc2a3d03450b))
* **hook:** vibe-hook reads stdin+env -&gt; JSON line over unix socket ([ab0216e](https://github.com/zzcan/island/commit/ab0216e02f1eafe2f37a106b70a4067c2ac4a907))
* island rows show prompt text + Claude/cmux badges + elapsed (Vibe Island layout) ([5ee385a](https://github.com/zzcan/island/commit/5ee385aba868b77890a0e20a1571bb14ec408d6f))
* **vibe-hook:** load live tasks + latest assistant text per session ([f2657c3](https://github.com/zzcan/island/commit/f2657c3e2727383046a9dfee87fe53a937e5ea18))


### Bug Fixes

* **app:** actually overlay the notch — bypass menu-bar frame clamp + set level after isFloatingPanel ([1ca9dd2](https://github.com/zzcan/island/commit/1ca9dd23a00fdf47e3890192cd7464551e703e50))
* **app:** address glue-layer review (start at launch, non-blocking jump, socket path guard) ([5cd2956](https://github.com/zzcan/island/commit/5cd295621bb8adc134334cd0dc686532fcb1d902))
* **app:** expanded-panel avatars now animate (drop TimelineView subtree rebuild; refresh elapsed via timer) ([79698c8](https://github.com/zzcan/island/commit/79698c80264bc61e7deb0a2a2f6286cf8ff8a3c5))
* **app:** hang the capsule just below the notch instead of over it ([497b8f3](https://github.com/zzcan/island/commit/497b8f39080bb45682795e4609c7ea768f9749c1))
* **app:** hit-test only the island, pass clicks through the transparent canvas (route 2) ([80e7f92](https://github.com/zzcan/island/commit/80e7f921d03772d6106100392867ed610540d31a))
* **app:** hug the notch — capsule top flush with screen top, centered on the notch ([af36a9e](https://github.com/zzcan/island/commit/af36a9e6bfbcf2043501ce5f4e4d4a00b500117c))
* **app:** pin island to primary display (menu-bar screen), not the focused screen ([08969df](https://github.com/zzcan/island/commit/08969df5a40f4dc800e774c122836b5bb2d39dd0))
* **app:** place capsule at the notch position but BELOW it in z-order ([352390b](https://github.com/zzcan/island/commit/352390bd94fc71e192c979952cc7c576413f564c))
* **app:** raise island above the menu bar so hover works again (notch &gt; island &gt; menu bar) ([b67dff0](https://github.com/zzcan/island/commit/b67dff0c15e331a4d1aa00c4e464fb44b2dfbc3b))
* **app:** real click-through via per-cursor ignoresMouseEvents toggle ([2acc558](https://github.com/zzcan/island/commit/2acc558a44fc344300ad10a2f309f3985ded5f89))
* **app:** reliable equalizer motion via TimelineView(.animation) sine wave (working ripples, needsInput blinks) ([5ad8755](https://github.com/zzcan/island/commit/5ad8755ff89415216f22c0645273ef465893e4d6))
* **app:** report island rect directly (was stuck at .zero, blocking all clicks) ([221b96a](https://github.com/zzcan/island/commit/221b96ac9f869c47996683c2ed28d10d04243ed4))
* **core:** cmux select-workspace requires --workspace flag (verified live) ([439fb50](https://github.com/zzcan/island/commit/439fb50b549caea3295f9a0c9bf61788ed1f1f66))


### Miscellaneous Chores

* bootstrap first release as 0.1.0 ([d1d4e4c](https://github.com/zzcan/island/commit/d1d4e4ce6391f2600f86dac9718075b18e6c2b2d))
