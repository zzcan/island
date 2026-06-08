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
        .onChange(of: model.eventTick) { _, _ in
            autoExpand = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if !hovering { autoExpand = false }
            }
        }
    }

    private var island: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: model.display.pillSymbol)
                if model.display.pillCount > 1 {
                    Text("\(model.display.pillCount)").font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            if expanded {
                VStack(spacing: 2) {
                    ForEach(model.display.rows) { row in
                        Button { model.jump(sessionId: row.id) } label: {
                            HStack(spacing: 8) {
                                Circle().fill(color(row.status)).frame(width: 8, height: 8)
                                Text(row.title).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .frame(width: 280, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.white)
        .fixedSize()
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

    private func color(_ s: SessionStatus) -> Color {
        switch s {
        case .idle: return .gray
        case .working: return .yellow
        case .needsInput: return .blue
        case .done: return .green
        }
    }
}
