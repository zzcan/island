import SwiftUI
import Combine
import IslandCore

struct IslandView: View {
    @EnvironmentObject var model: AppModel
    @State private var hovering = false
    @State private var autoExpand = false
    @State private var rowsIn = false   // drives the staggered row cascade
    @State private var now = Date()     // refreshed by a timer for elapsed labels

    private var expanded: Bool { hovering || autoExpand }

    // Asymmetric geometry springs, slow enough that the width/height morph reads
    // clearly. Expand slightly slower with a hair of overshoot; collapse smooth.
    private var expandSpring: Animation { .spring(response: 0.5, dampingFraction: 0.8) }
    private var collapseSpring: Animation { .spring(response: 0.45, dampingFraction: 0.82) }

    var body: some View {
        VStack(spacing: 0) {
            if !model.display.hidden { island }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if !hovering { autoExpand = false }
            }
        }
    }

    private var island: some View {
        // Uniform corners both states; radius animates with the geometry spring.
        let shape = RoundedRectangle(cornerRadius: expanded ? 16 : 8, style: .continuous)
        return Group {
            if expanded {
                expandedPanel
                    // Opacity is decoupled from the geometry: the box leads, content
                    // fades in over a slightly longer ramp so the size morph is visible.
                    .transition(.opacity.animation(.easeOut(duration: 0.3).delay(0.08)))
            } else {
                collapsedCapsule
                    .transition(.opacity.animation(.easeOut(duration: 0.2)))
            }
        }
        // Single morphing black container: size + corner radius animate together.
        .background(Color.black, in: shape)
        // Curtain reveal: content is clipped to the morphing box, so the panel
        // appears to unfurl downward from the top as the box grows.
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: expanded ? 12 : 7, y: 3)
        .foregroundStyle(.white)
        .onHover { h in
            withAnimation(h ? expandSpring : collapseSpring) { hovering = h }
            if !h {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if !hovering { withAnimation(collapseSpring) { autoExpand = false } }
                }
            }
        }
        // Geometry (size + radius) follows the directional spring.
        .animation(expanded ? expandSpring : collapseSpring, value: expanded)
    }

    // MARK: - Collapsed capsule

    private var collapsedCapsule: some View {
        HStack(spacing: 7) {
            // Left: only the latest (most-recently-active) session's status glyph.
            if let latest = model.display.rows.first {
                EqualizerBars(status: latest.status, barCount: 4, barWidth: 2, maxHeight: 11, spacing: 1.5)
            }
            Spacer(minLength: 16)
            // Right: total session count.
            Text("\(model.display.pillCount)")
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .frame(width: 240, height: 34)
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            usageBar
                .padding(.horizontal, 12).padding(.vertical, 8)
            Divider().overlay(.white.opacity(0.08))
            VStack(spacing: 0) {
                ForEach(Array(model.display.rows.enumerated()), id: \.element.id) { idx, row in
                    Button { model.jump(sessionId: row.id) } label: { rowView(row: row, now: now) }
                        .buttonStyle(.plain)
                        // Staggered cascade: each row fades + slides in slightly after
                        // the previous one, once the box has begun expanding.
                        .opacity(rowsIn ? 1 : 0)
                        .offset(y: rowsIn ? 0 : -4)
                        .animation(.easeOut(duration: 0.24).delay(Double(idx) * 0.04), value: rowsIn)
                    if idx < model.display.rows.count - 1 {
                        Divider().overlay(.white.opacity(0.06)).padding(.horizontal, 12)
                            .opacity(rowsIn ? 1 : 0)
                            .animation(.easeOut(duration: 0.24).delay(Double(idx) * 0.04), value: rowsIn)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 460)
        // Refresh elapsed labels without rebuilding the row/avatar subtree
        // (which would interrupt the equalizer's repeating animation).
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    // MARK: - Usage bar (real subscription usage from /api/oauth/usage)

    private var usageBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            usageSegment(label: "5h", window: model.usage?.fiveHour)
            usageSegment(label: "7d", window: model.usage?.sevenDay)
            Spacer()
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func usageSegment(label: String, window: UsageWindow?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white)
            if let w = window {
                Text(UsageFormat.percent(w.utilization))
                    .font(.system(size: 12))
                    .foregroundStyle(usageColor(UsageTint.from(w.utilization)))
                Text(UsageFormat.remaining(until: w.resetsAt, now: now))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                // No data yet (first fetch pending, keychain denied, or offline).
                Text("--%").font(.system(size: 12)).foregroundStyle(.secondary)
                Text("--").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private func usageColor(_ tint: UsageTint) -> Color {
        switch tint {
        case .ok:   return .green
        case .warn: return .orange
        case .crit: return .red
        }
    }

    // MARK: - Row view

    private func rowView(row: IslandRow, now: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            EqualizerAvatar(status: row.status)
            VStack(alignment: .leading, spacing: 3) {
                // Line 1: title · cwd + badges + elapsed
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let cwd = row.cwd {
                        Text("· " + shortCwd(cwd))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    if let mode = PermissionMode.from(row.permissionMode) {
                        badge(mode.label, tint: permissionTint(mode.tint))
                    }
                    badge(row.model ?? "Claude")
                    badge(row.terminal)
                    Text(elapsedString(from: row.lastActivity, to: now))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                // Line 2: status glyph + prompt
                HStack(spacing: 6) {
                    statusGlyph(row.status)
                    Text("你：" + (row.prompt ?? "—"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // Line 3: assistant's latest message (if present)
                if let assistant = row.assistant {
                    Text(assistant)
                        .font(.caption)
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
                            .font(.caption2)
                            .foregroundStyle(.blue.opacity(0.9))
                            .lineLimit(1)
                    }
                }
                // Line 5: task block (if present)
                if !row.tasks.isEmpty {
                    let s = TaskSummary.from(row.tasks)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("任务 (\(s.completed) 已完成, \(s.inProgress) 进行中, \(s.pending) 待处理)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(Array(row.tasks.prefix(3))) { item in
                            HStack(spacing: 6) {
                                taskIcon(item.status)
                                Text(item.subject)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .foregroundStyle(item.status == "completed" ? AnyShapeStyle(.secondary) : item.status == "in_progress" ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
                                    .strikethrough(item.status == "completed")
                            }
                        }
                        if row.tasks.count > 3 {
                            Text("… +\(row.tasks.count - 3) 更多")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 7)
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
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint, in: Capsule())
            .foregroundStyle(.white.opacity(0.85))
    }

    // MARK: - Status glyph

    @ViewBuilder
    private func statusGlyph(_ status: SessionStatus) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        case .needsInput:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.yellow)
        case .working:
            ProgressView()
                .controlSize(.mini)
        case .idle:
            Image(systemName: "circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.gray)
        }
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

// MARK: - Equalizer bars (status-coded color + motion)

/// Per-session equalizer, used in the collapsed bar and (wrapped) as the
/// expanded-row avatar. Each status has its own COLOR and its own MOTION:
///   working   → blue, bars bounce (active)
///   needsInput→ yellow, bars blink in opacity (attention)
///   done      → green, bars settle to an even height (calm/complete)
///   idle      → gray, low and dim (quiet)
private struct EqualizerBars: View {
    let status: SessionStatus
    var barCount: Int = 4
    var barWidth: CGFloat = 2.5
    var maxHeight: CGFloat = 14
    var spacing: CGFloat = 2

    private var color: Color {
        switch status {
        case .working:    return .blue
        case .needsInput: return .yellow
        case .done:       return .green
        case .idle:       return .gray
        }
    }

    private var isAnimated: Bool { status == .working || status == .needsInput }

    var body: some View {
        // Time-driven: TimelineView(.animation) ticks per frame so the bars move
        // continuously and reliably (no fragile repeatForever state). Static states
        // skip the timeline entirely.
        Group {
            if isAnimated {
                TimelineView(.animation) { ctx in
                    bars(at: ctx.date.timeIntervalSinceReferenceDate)
                }
            } else {
                bars(at: 0)
            }
        }
    }

    private func bars(at t: Double) -> some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule().fill(color).frame(width: barWidth, height: height(i, t))
            }
        }
        .frame(height: maxHeight, alignment: .center)
        .opacity(opacity(at: t))
    }

    private func height(_ i: Int, _ t: Double) -> CGFloat {
        switch status {
        case .working:
            // Per-bar sine wave, phase-offset by index → equalizer ripple.
            let s = (sin(t * 6.0 + Double(i) * 0.9) + 1) / 2          // 0...1
            return maxHeight * (0.3 + 0.65 * s)
        case .done:       return maxHeight * 0.75    // settled, even
        case .needsInput: return maxHeight * 0.6     // medium (opacity blinks)
        case .idle:       return maxHeight * 0.4     // low
        }
    }

    private func opacity(at t: Double) -> Double {
        switch status {
        case .needsInput:
            let s = (sin(t * 4.0) + 1) / 2
            return 0.3 + 0.7 * s                     // attention blink
        case .idle: return 0.55
        default:    return 1.0
        }
    }
}

/// Expanded-row avatar: equalizer bars in a 26×26 dark rounded square.
private struct EqualizerAvatar: View {
    let status: SessionStatus
    var body: some View {
        EqualizerBars(status: status, barCount: 5, barWidth: 2.5, maxHeight: 12, spacing: 1.5)
            .frame(width: 20, height: 20)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
    }
}
