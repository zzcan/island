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

    private var island: some View {
        Group {
            if expanded {
                expandedPanel
            } else {
                collapsedCapsule
            }
        }
        .onHover { h in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { hovering = h }
            if !h {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if !hovering { autoExpand = false }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: expanded)
    }

    // MARK: - Collapsed capsule

    private var collapsedCapsule: some View {
        HStack(spacing: 5) {
            ForEach(model.display.rows.prefix(4)) { row in
                StatusDot(status: row.status)
            }
            if model.display.pillCount > 4 {
                Text("+\(model.display.pillCount - 4)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text("\(model.display.pillCount)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.leading, 1)
        }
        .padding(.horizontal, 11)
        .frame(height: 26)
        .background(Color.black, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            VStack(spacing: 10) {
                ForEach(model.display.rows) { row in
                    Button { model.jump(sessionId: row.id) } label: {
                        rowView(row: row, now: context.date)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(width: 440)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .foregroundStyle(.white)
        }
    }

    // MARK: - Row view

    private func rowView(row: IslandRow, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Line 1: title + badges + elapsed
            HStack(spacing: 6) {
                Text(row.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                badge("Claude")
                badge(row.terminal)
                Text(elapsedString(from: row.lastActivity, to: now))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // Line 2: status glyph + prompt preview
            HStack(spacing: 6) {
                statusGlyph(row.status)
                Text("你：" + (row.prompt ?? "—"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Badge helper

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.white.opacity(0.12), in: Capsule())
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
}

// MARK: - Collapsed status dot

/// One dot per active session in the collapsed capsule. `working` gently pulses;
/// `needsInput` gets a colored glow so urgent sessions catch the eye.
private struct StatusDot: View {
    let status: SessionStatus
    @State private var pulsing = false

    private var color: Color {
        switch status {
        case .done: return .green
        case .needsInput: return .yellow
        case .working: return .blue
        case .idle: return .gray
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: status == .needsInput ? 8 : 7, height: status == .needsInput ? 8 : 7)
            .scaleEffect(status == .working && pulsing ? 1.0 : (status == .working ? 0.65 : 1.0))
            .shadow(color: status == .needsInput ? color.opacity(0.9) : .clear, radius: 3)
            .onAppear {
                guard status == .working else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}
