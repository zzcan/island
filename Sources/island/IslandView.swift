import SwiftUI
import IslandCore

struct IslandView: View {
    @EnvironmentObject var model: AppModel
    @State private var hovering = false
    @State private var autoExpand = false

    private var expanded: Bool { hovering || autoExpand }

    var body: some View {
        VStack(spacing: 0) {
            if !model.display.hidden { island }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
        .environment(\.colorScheme, .dark)
        .onChange(of: model.eventTick) { _, _ in
            autoExpand = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if !hovering { autoExpand = false }
            }
        }
    }

    // Dynamic-Island-style spring: fluid with a little overshoot.
    private var morph: Animation { .spring(response: 0.42, dampingFraction: 0.72) }

    private var island: some View {
        let radius: CGFloat = expanded ? 24 : 15
        return Group {
            if expanded {
                expandedPanel
                    .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
            } else {
                collapsedCapsule
                    .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
            }
        }
        // Single morphing black container: size + corner radius animate together.
        .background(Color.black, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: expanded ? 12 : 7, y: 3)
        .foregroundStyle(.white)
        .onHover { h in
            withAnimation(morph) { hovering = h }
            if !h {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if !hovering { withAnimation(morph) { autoExpand = false } }
                }
            }
        }
        .animation(morph, value: expanded)
    }

    // MARK: - Collapsed capsule

    private var collapsedCapsule: some View {
        HStack(spacing: 7) {
            // Left: per-session equalizer glyphs (capped), like Vibe Island's notch bar.
            ForEach(model.display.rows.prefix(5)) { row in
                EqualizerGlyph(status: row.status)
            }
            if model.display.pillCount > 5 {
                Text("+\(model.display.pillCount - 5)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 16)
            // Right: session count.
            Text("\(model.display.pillCount)")
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .frame(width: 360, height: 30)
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            VStack(alignment: .leading, spacing: 0) {
                usageBar
                    .padding(.horizontal, 12).padding(.vertical, 8)
                Divider().overlay(.white.opacity(0.08))
                VStack(spacing: 0) {
                    ForEach(Array(model.display.rows.enumerated()), id: \.element.id) { idx, row in
                        Button { model.jump(sessionId: row.id) } label: { rowView(row: row, now: context.date) }
                            .buttonStyle(.plain)
                        if idx < model.display.rows.count - 1 {
                            Divider().overlay(.white.opacity(0.06)).padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(width: 460)
        }
    }

    // MARK: - Usage bar (static placeholder)

    private var usageBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            // Segment 1: 5h --% --
            HStack(spacing: 3) {
                Text("5h")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                Text("--%")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                Text("--")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            // Segment 2: 7d --% --
            HStack(spacing: 3) {
                Text("7d")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                Text("--%")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                Text("--")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Row view

    private func rowView(row: IslandRow, now: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            IdenticonView(seed: row.cwd ?? row.id)
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
                    badge("自动批准", tint: .red.opacity(0.35))
                    badge("Claude")
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
                // Line 3: current action (only if present)
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
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Badge helper

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

// MARK: - Collapsed status dot

/// One small equalizer glyph per active session in the collapsed bar — mirrors
/// Vibe Island's notch bar. `working` animates the bars; color encodes status.
private struct EqualizerGlyph: View {
    let status: SessionStatus
    @State private var animating = false

    private var color: Color {
        switch status {
        case .done, .working: return .green
        case .needsInput: return .yellow
        case .idle: return .gray
        }
    }

    private let base: [CGFloat] = [6, 12, 8, 13]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: height(i))
            }
        }
        .frame(height: 14, alignment: .center)
        .onAppear {
            guard status == .working else { return }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                animating = true
            }
        }
    }

    private func height(_ i: Int) -> CGFloat {
        guard status == .working else { return base[i] }
        return animating ? base[(i + 2) % 4] : base[i]
    }
}
