import SwiftUI
import AppKit
import Combine
import IslandCore

struct IslandView: View {
    let hitRegion: IslandHitRegion
    let drag: IslandDragProxy
    @ObservedObject var proximity: IslandProximity
    @ObservedObject private var settings = Settings.shared
    @EnvironmentObject var model: AppModel
    @State private var autoExpand = false
    @State private var autoExpandToken = 0  // invalidates stale retract timers
    @State private var rowsIn = false   // drives the staggered row cascade
    @State private var now = Date()     // refreshed by a timer for elapsed labels
    @State private var hoveredRow: String?  // id of the row the cursor is over
    @State private var expandedHeight: CGFloat = 220  // measured natural panel height

    // Continuous open amount (0…1). Proximity tracks the cursor directly (the
    // "follow-the-cursor" feel); an event briefly forces it fully open via autoExpand;
    // a pending plan review pins it fully open until the user decides.
    private var openness: CGFloat {
        max(proximity.value, autoExpand ? 1 : 0, model.pendingPlan != nil ? 1 : 0)
    }
    // Eased version used for geometry so the open accelerates near the end.
    private var eased: CGFloat { let o = min(max(openness, 0), 1); return o * o * (3 - 2 * o) }
    // Boolean view of the same state for bits that only need on/off (the row cascade).
    private var expanded: Bool { openness > 0.5 }

    // Spring used ONLY for the discrete autoExpand (event) transition. Proximity
    // changes are deliberately NOT animated — they snap to each cursor position so
    // the island geometry tracks the pointer instead of lagging behind a spring.
    private var expandSpring: Animation { .spring(response: 0.34, dampingFraction: 0.78) }

    /// Ceiling for the expanded panel: half the host screen's height. Taller content
    /// scrolls inside the box (see expandedPanel) instead of tiling the panel down.
    private var maxPanelHeight: CGFloat {
        let screenH = (settings.targetScreen() ?? NSScreen.main)?.visibleFrame.height ?? 900
        // Also stay within the host panel's fixed 720pt canvas (top-flush) so the box is
        // never clipped by the window itself on very tall external displays.
        return min(screenH * 0.5, 660)
    }

    /// Scaled font for expanded-panel text (honours the content font-size setting).
    private func fs(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * CGFloat(settings.fontScale), weight: weight)
    }

    /// The sprite for a status under the selected character theme.
    private func spriteFor(_ status: SessionStatus) -> PixelSprite {
        (SpriteTheme(rawValue: settings.spriteTheme) ?? .invaders).sprite(for: status)
    }

    /// Colour-mode override for a status glyph; nil = use the sprite's own ("原色")
    /// palette. Idle is dimmed in the monochrome modes.
    private func glyphColor(_ status: SessionStatus) -> Color? {
        let dim: Double = status == .idle ? 0.45 : 1.0
        switch settings.colorMode {
        case 1: return Color(red: 0.30, green: 1.0, blue: 0.55).opacity(dim)   // phosphor green
        case 2: return Color(red: 1.0, green: 0.75, blue: 0.20).opacity(dim)   // amber
        case 3: return Color(red: 0.55, green: 0.78, blue: 0.20).opacity(dim)  // Game Boy DMG green
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Show the island when there are sessions to display, or when a plan is
            // waiting for review (which must surface even if the panel is auto-hidden).
            if !model.display.hidden || model.pendingPlan != nil { island }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
        .environment(\.colorScheme, .dark)
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded {
                // Shape leads, rows cascade in once the box is clearly growing.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    if expanded { rowsIn = true }
                }
            } else {
                rowsIn = false
            }
        }
        .onChange(of: model.eventTick) { _, _ in
            autoExpand = true
            // Retract unconditionally after the flash. If the cursor is still near, the
            // proximity term of `openness` keeps the panel open — so this never gets
            // "stuck" the way a proximity-gated retract could. The token makes only the
            // most-recent event's timer fire, so rapid events extend the window cleanly.
            autoExpandToken &+= 1
            let token = autoExpandToken
            DispatchQueue.main.asyncAfter(deadline: .now() + settings.autoCollapseDwell) {
                if token == autoExpandToken { autoExpand = false }
            }
        }
    }

    private var island: some View {
        // Geometry is a continuous function of `openness` so the box tracks the
        // cursor as it approaches (proximity), rather than snapping between two
        // discrete states.
        let e = eased
        let cw = CGFloat(settings.collapsedWidth)
        let ew = CGFloat(settings.expandedWidth)
        let w = cw + (ew - cw) * e
        // The panel grows with its content but is capped at half the host screen;
        // beyond that the content scrolls inside the box (see expandedPanel).
        let panelHeight = min(expandedHeight, maxPanelHeight)
        let h = 34 + (max(panelHeight, 34) - 34) * e
        let corner = 8 + (16 - 8) * e
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        // Content crossfade: collapsed pill fades out over the first third of the
        // open; the expanded panel fades in over the back three-quarters. The box
        // also clips both (curtain reveal), so the panel unfurls from the top.
        let collapsedOpacity = Double(max(0, 1 - e / 0.33))
        let expandedOpacity = Double(max(0, (e - 0.22) / 0.78))
        return ZStack(alignment: .top) {
            expandedPanel
                .opacity(expandedOpacity)
            collapsedCapsule
                .opacity(collapsedOpacity)
        }
        .frame(width: w, height: h, alignment: .top)
        .background(Color.black, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 7 + 5 * e, y: 3)
        .foregroundStyle(.white)
        // Animate ONLY the discrete event-driven open/close. Proximity-driven changes
        // to `openness` are not keyed here, so they render instantly and track the
        // cursor; the autoExpand transition rides the spring.
        .animation(expandSpring, value: autoExpand)
        // Report the drawn box (in the hosting view's coordinate space, which is what
        // .global resolves to here) so the panel hit-tests only the island; clicks on
        // the transparent canvas elsewhere pass through. Written directly to avoid
        // SwiftUI preference-propagation timing issues.
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { hitRegion.rect = geo.frame(in: .global) }
                .onChange(of: geo.frame(in: .global)) { _, f in hitRegion.rect = f }
        })
        // Press-and-drag horizontally to reposition the island (e.g. to clear the
        // menu-bar status icons). Vertical movement is ignored — it stays flush at the
        // top. minimumDistance lets row taps (jump) still register as clicks. Global
        // coordinate space keeps the translation stable as the panel moves under it.
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { drag.onChanged?($0.translation.width) }
                .onEnded { _ in drag.onEnded?() }
        )
    }

    // MARK: - Collapsed capsule

    private var collapsedCapsule: some View {
        HStack(spacing: 7) {
            // Left: only the latest (most-recently-active) session's status glyph,
            // drawn as a pixel sprite (matches the expanded-row avatars).
            if let latest = model.display.rows.first {
                PixelGlyphView(sprite: spriteFor(latest.status), pixelSize: 2,
                               colorOverride: glyphColor(latest.status))
                    .frame(width: 28, alignment: .leading)
            }
            Spacer(minLength: 16)
            // Right: total session count.
            Text("\(model.display.pillCount)")
                .font(fs(13, .bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .frame(width: CGFloat(settings.collapsedWidth), height: 34)
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        // Capped at half-screen; taller content scrolls. The inner content reports its
        // natural height (measured below) so the box knows how tall to grow, up to the cap.
        ScrollView(.vertical, showsIndicators: false) {
            expandedPanelContent
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { expandedHeight = g.size.height }
                        .onChange(of: g.size.height) { _, nh in expandedHeight = nh }
                })
        }
        .frame(width: CGFloat(settings.expandedWidth), height: min(expandedHeight, maxPanelHeight))
        // Only scroll when content actually overflows the cap; otherwise it's a plain panel.
        .scrollDisabled(expandedHeight <= maxPanelHeight)
    }

    private var expandedPanelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
                .padding(.horizontal, 12).padding(.vertical, 8)
            // A pending plan sits inline, ABOVE the session rows — part of the same panel,
            // not a separate window. The session list stays visible below it.
            if let plan = model.pendingPlan {
                PlanReviewCard(plan: plan) { reply in model.resolvePlan(plan, reply) }
                    .padding(.bottom, 6)
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.bottom, 4)
            }
            VStack(spacing: 0) {
                ForEach(Array(model.display.rows.enumerated()), id: \.element.id) { idx, row in
                    ZStack(alignment: .topTrailing) {
                        Button { if settings.clickToJump { model.jump(sessionId: row.id) } } label: { rowView(row: row, now: now) }
                            .buttonStyle(.plain)
                        // Clear control: appears over the elapsed-time slot on hover,
                        // removes the session from the panel without triggering jump
                        // (it's a sibling button on top of the row's tap target).
                        if hoveredRow == row.id {
                            Button { model.dismiss(sessionId: row.id) } label: {
                                Image(systemName: "trash")
                                    .font(fs(12))
                                    .foregroundStyle(.secondary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("从面板清除该会话")
                            .padding(.top, 6)
                            .padding(.trailing, 8)
                            .transition(.opacity)
                        }
                    }
                    // Hover highlight: subtle background while the cursor is over the row.
                    .background(hoveredRow == row.id ? Color.white.opacity(0.07) : Color.clear)
                    .animation(.easeOut(duration: 0.12), value: hoveredRow)
                    .onHover { inside in
                        if inside { hoveredRow = row.id }
                        else if hoveredRow == row.id { hoveredRow = nil }
                    }
                    // Staggered cascade: each row fades + slides in slightly after
                    // the previous one, once the box has begun expanding.
                    .opacity(rowsIn ? 1 : 0)
                    .offset(y: rowsIn ? 0 : -4)
                    .animation(.easeOut(duration: 0.24).delay(Double(idx) * 0.04), value: rowsIn)
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .frame(width: CGFloat(settings.expandedWidth))
        // Refresh elapsed labels without rebuilding the row/avatar subtree
        // (which would interrupt the equalizer's repeating animation).
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack(spacing: 6) {
            Spacer()
            // Toggle event sounds. Slashed icon ⇒ muted.
            Button { settings.soundEnabled.toggle() } label: {
                Image(systemName: settings.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(settings.soundEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white.opacity(0.35)))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(settings.soundEnabled ? "静音事件音效" : "开启事件音效")
            // Open the settings window.
            Button { model.openSettings() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("设置")
        }
    }

    // MARK: - Row view

    private func rowView(row: IslandRow, now: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            PixelAvatar(sprite: spriteFor(row.status), color: glyphColor(row.status))
            VStack(alignment: .leading, spacing: 5) {
                // Line 1: title · cwd + badges + elapsed
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(fs(13, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let cwd = row.cwd {
                        Text("· " + shortCwd(cwd))
                            .font(fs(11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    if let mode = PermissionMode.from(row.permissionMode) {
                        badge(mode.label, tint: permissionTint(mode.tint))
                    }
                    badge(row.model ?? "Claude")
                    if !row.terminal.isEmpty { badge(row.terminal) }
                    Text(elapsedString(from: row.lastActivity, to: now))
                        .font(fs(11))
                        .foregroundStyle(.secondary)
                        // Hidden while hovered so the clear icon shows in its place.
                        .opacity(hoveredRow == row.id ? 0 : 1)
                }
                // Line 2: prompt
                Text("你：" + (row.prompt ?? "—"))
                    .font(fs(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                // Line 3: assistant's latest message (if present)
                if let assistant = row.assistant {
                    Text(assistant)
                        .font(fs(12))
                        .foregroundStyle(.secondary.opacity(0.9))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                // Line 4: current action (only if present)
                if let action = row.action {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.blue)
                        Text(action)
                            .font(fs(11))
                            .foregroundStyle(.blue.opacity(0.9))
                            .lineLimit(1)
                    }
                }
                // Line 5: task block (if present)
                if !row.tasks.isEmpty {
                    let s = TaskSummary.from(row.tasks)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("任务 (\(s.completed) 已完成, \(s.inProgress) 进行中, \(s.pending) 待处理)")
                            .font(fs(11))
                            .foregroundStyle(.secondary)
                        ForEach(Array(row.tasks.prefix(3))) { item in
                            HStack(spacing: 6) {
                                taskIcon(item.status)
                                Text(item.subject)
                                    .font(fs(11))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .foregroundStyle(item.status == "completed" ? AnyShapeStyle(.secondary) : item.status == "in_progress" ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
                                    .strikethrough(item.status == "completed")
                            }
                        }
                        if row.tasks.count > 3 {
                            Text("… +\(row.tasks.count - 3) 更多")
                                .font(fs(11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func taskIcon(_ status: String) -> some View {
        switch status {
        case "completed":
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.green)
        case "in_progress":
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.blue)
        default:
            Image(systemName: "circle")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Badge helper

    /// Maps a permission-mode tint category to a badge colour, ordered by how much
    /// authority the mode grants: neutral grey → blue → orange → orange-red → red.
    private func permissionTint(_ tint: PermissionTint) -> Color {
        switch tint {
        case .neutral: return .white.opacity(0.12)
        case .plan:    return .blue.opacity(0.35)
        case .edits:   return .orange.opacity(0.35)
        case .auto:    return .red.opacity(0.30)
        case .full:    return .red.opacity(0.45)
        }
    }

    private func badge(_ text: String, tint: Color = .white.opacity(0.12)) -> some View {
        Text(text)
            .font(fs(10, .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint, in: Capsule())
            .foregroundStyle(.white.opacity(0.85))
    }

    // MARK: - Elapsed time

    private func elapsedString(from date: Date, to now: Date) -> String {
        let secs = max(0, now.timeIntervalSince(date))
        if secs < 60 { return "now" }
        let min = Int(secs / 60)
        if min < 60 { return "\(min)m" }
        let hr = Int(secs / 3600)
        if hr < 24 { return "\(hr)h" }
        let days = Int(secs / 86400)
        return "\(days)d"
    }

    // MARK: - Short CWD helper

    private func shortCwd(_ p: String) -> String {
        let home = NSHomeDirectory()
        var path = p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
        if path.count > 28 {
            let components = (path as NSString).pathComponents
            if components.count >= 2 {
                let last2 = components.suffix(2).joined(separator: "/")
                path = "…/" + last2
            }
        }
        return path
    }
}

// MARK: - Identicon avatar

private struct IdenticonView: View {
    let seed: String
    var pixel: CGFloat = 5

    var body: some View {
        let grid = Identicon.make(seed: seed)
        let color = Color(hue: grid.hue, saturation: 0.6, brightness: 0.9)
        VStack(spacing: 1) {
            ForEach(0..<grid.cells.count, id: \.self) { r in
                HStack(spacing: 1) {
                    ForEach(0..<grid.cells[r].count, id: \.self) { c in
                        Rectangle()
                            .fill(grid.cells[r][c] ? color : Color.clear)
                            .frame(width: pixel, height: pixel)
                    }
                }
            }
        }
        .padding(4)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Pixel avatar (status-coded sprite)

/// Expanded-row avatar: the per-status pixel sprite centered in a dark rounded
/// square. Status colour + motion live in `PixelSprite.forStatus`.
private struct PixelAvatar: View {
    let sprite: PixelSprite
    var color: Color? = nil
    var body: some View {
        PixelGlyphView(sprite: sprite, pixelSize: 2, colorOverride: color)
            .frame(width: 28, height: 22)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
    }
}
