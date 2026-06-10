import SwiftUI
import IslandCore

/// The plan-review surface, embedded inside the island's expanded panel: full Markdown
/// of the plan with approve / mode / reject controls and a feedback field — so you
/// decide without leaving the island. Fills the panel's width; caps its body height so
/// the whole card fits the floating panel's canvas.
struct PlanReviewCard: View {
    let plan: PlanRequest
    let onDecide: (PermissionReply) -> Void

    @State private var feedback: String = ""
    @FocusState private var feedbackFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Plan tag + project name.
            HStack(spacing: 8) {
                Text("PLAN")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.30)))
                    .foregroundStyle(.white)
                Text(plan.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Text("审阅计划").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)

            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)

            // Scrollable plan body — fills the card between header and footer. The card
            // has a fixed height (below) so this ScrollView gets a definite size to
            // scroll within, even though the panel measures itself with fixedSize.
            ScrollView {
                MarkdownView(text: plan.plan)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)

            // Feedback + actions.
            VStack(alignment: .leading, spacing: 10) {
                TextField("告诉 Claude 要改什么…（驳回时发送）", text: $feedback, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .lineLimit(1...3)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                    .focused($feedbackFocused)

                HStack(spacing: 8) {
                    actionButton("驳回", tint: .red.opacity(0.8)) {
                        decide(.deny(reason: feedback.isEmpty ? "用户驳回了该计划" : feedback))
                    }
                    Spacer()
                    actionButton("在终端处理", tint: .white.opacity(0.12), fg: .secondary) {
                        decide(.defer_)
                    }
                    actionButton("手动批准", tint: .white.opacity(0.16)) {
                        decide(.allow(mode: "default"))
                    }
                    actionButton("自动接受编辑", tint: .green.opacity(0.30)) {
                        decide(.allow(mode: "acceptEdits"))
                    }
                    actionButton("绕过权限", tint: .orange.opacity(0.30)) {
                        decide(.allow(mode: "bypassPermissions"))
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        // Fixed height gives the ScrollView a definite size to scroll within (the panel
        // measures the card with fixedSize, which would otherwise collapse the scroll).
        // Kept moderate so the session rows stay visible below it in the same panel.
        .frame(height: 380)
        .environment(\.colorScheme, .dark)
    }

    private func actionButton(_ title: String, tint: Color, fg: Color = .white,
                              _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(tint))
                .foregroundStyle(fg)
        }
        .buttonStyle(.plain)
    }

    private func decide(_ reply: PermissionReply) {
        feedback = ""
        onDecide(reply)
    }
}
