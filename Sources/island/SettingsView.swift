import SwiftUI
import AppKit

/// Settings, System-Settings style: a sidebar of categories (each a coloured icon +
/// title) on the left via `NavigationSplitView`, the selected category's controls on
/// the right. Binds directly to `Settings.shared`.
struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var selection: SettingsCategory = .general
    @State private var showReset = false

    var body: some View {
        NavigationSplitView {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(SettingsCategory.allCases) { cat in
                        SidebarRow(cat: cat, selected: selection == cat) { selection = cat }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .navigationSplitViewColumnWidth(min: 196, ideal: 208, max: 240)
        } detail: {
            Form {
                detail(selection)
            }
            .formStyle(.grouped)
            .navigationTitle(selection.title)
        }
        .frame(width: 720, height: 600)
    }

    // MARK: - Per-category content

    @ViewBuilder
    private func detail(_ cat: SettingsCategory) -> some View {
        switch cat {
        case .general:
            Section {
                Toggle("登录时打开", isOn: $settings.launchAtLogin)
                Toggle("系统通知横幅", isOn: $settings.notificationsEnabled)
            }

        case .sound:
            Section("音效") {
                Toggle("启用音效", isOn: $settings.soundEnabled)
                LabeledContent("音量") {
                    Slider(value: $settings.soundVolume, in: 0...1).frame(width: 200)
                }
                soundRow("会话开始", isOn: $settings.soundSessionStart, sound: .sessionStart)
                soundRow("需要审批", isOn: $settings.soundInputRequired, sound: .needsInput)
                soundRow("任务完成", isOn: $settings.soundTaskComplete, sound: .done)
            }
            Section("静音时段") {
                Toggle("在指定时段内静音", isOn: $settings.quietHoursEnabled)
                Group {
                    DatePicker("开始", selection: timeBinding($settings.quietStart), displayedComponents: .hourAndMinute)
                    DatePicker("结束", selection: timeBinding($settings.quietEnd), displayedComponents: .hourAndMinute)
                }
                .disabled(!settings.quietHoursEnabled)
            }

        case .appearance:
            Section {
                LabeledContent("内容字体大小") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.fontScale, in: 0.8...1.4).frame(width: 170)
                        Text("\(Int(settings.fontScale * 100))%")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                Picker("角色主题", selection: $settings.spriteTheme) {
                    ForEach(SpriteTheme.allCases) { theme in Text(theme.label).tag(theme.rawValue) }
                }
                Picker("色调", selection: $settings.colorMode) {
                    Text("原色").tag(0); Text("磷光绿").tag(1); Text("琥珀").tag(2); Text("Game Boy").tag(3)
                }
            }

        case .island:
            Section {
                sliderRow("感应半径", value: $settings.activationPad, range: 0...160, unit: "pt")
                sliderRow("收起宽度", value: $settings.collapsedWidth, range: 180...360, unit: "pt")
                sliderRow("展开宽度", value: $settings.expandedWidth, range: 360...600, unit: "pt")
                sliderRow("顶部偏移", value: $settings.topOffset, range: 0...30, unit: "pt")
                Button("复位水平位置") {
                    NotificationCenter.default.post(name: .resetIslandPosition, object: nil)
                }
            }

        case .display:
            Section {
                Picker("显示在", selection: $settings.displayChoice) {
                    Text("主显示器").tag(0)
                    Text("跟随焦点").tag(1)
                    ForEach(screenOptions, id: \.id) { opt in Text(opt.name).tag(opt.id) }
                }
            }

        case .behavior:
            Section {
                Picker("事件自动展开", selection: $settings.autoExpandMode) {
                    Text("所有事件").tag(0)
                    Text("仅需操作的事件").tag(1)
                    Text("从不").tag(2)
                }
                Text(settings.autoExpandMode == 2
                     ? "事件不再自动弹开面板；仍可悬停展开，计划审阅仍会弹出。"
                     : "「仅需操作」= 需要审批与计划审阅时弹开；任务完成不弹。")
                    .font(.caption).foregroundStyle(.secondary)
                sliderRow("自动收起停留", value: $settings.autoCollapseDwell, range: 1...10, unit: "s")
                    .disabled(settings.autoExpandMode == 2)
                Toggle("点击会话跳转到终端", isOn: $settings.clickToJump)
                Toggle("在灵动岛内审阅计划（Plan）", isOn: $settings.planReviewEnabled)
                Text("关闭后，计划批准回到 Claude 终端原生提示。")
                    .font(.caption).foregroundStyle(.secondary)
                sliderRow("会话保留时长", value: $settings.sessionRetentionMinutes, range: 5...180, unit: "min")
            }

        case .filters:
            Section("会话过滤") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("按工作目录隐藏（包含匹配）").font(.caption).foregroundStyle(.secondary)
                    FilterEditor(placeholder: "例如 /experiments", items: $settings.cwdFilters)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("按首条提示词隐藏（前缀匹配）").font(.caption).foregroundStyle(.secondary)
                    FilterEditor(placeholder: "如 ## Memory", items: $settings.promptFilters)
                }
            }

        case .about:
            Section {
                LabeledContent("名称", value: "island")
                LabeledContent("版本", value: "0.1.0")
            }
            Section {
                Button(role: .destructive) { showReset = true } label: {
                    Text("恢复默认设置")
                }
                .confirmationDialog("恢复所有设置为默认值？", isPresented: $showReset, titleVisibility: .visible) {
                    Button("恢复默认", role: .destructive) {
                        settings.resetToDefaults()
                        NotificationCenter.default.post(name: .resetIslandPosition, object: nil)
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("声音、灵动岛尺寸、过滤规则等都会重置（登录项不变）。")
                }
            }
        }
    }

    // MARK: - Helpers

    /// Bridges an "minutes since midnight" Int to a DatePicker's Date (today at h:m).
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minutes.wrappedValue / 60,
                                         minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    /// A per-event sound row: enable toggle (greyed when sound off) + a 试听 preview.
    @ViewBuilder
    private func soundRow(_ title: String, isOn: Binding<Bool>, sound: SoundSynthesizer.Sound) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                Button { SoundSynthesizer.shared.preview(sound) } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .help("试听")
                Toggle("", isOn: isOn).labelsHidden().disabled(!settings.soundEnabled)
            }
        } label: {
            Text(title).foregroundStyle(settings.soundEnabled ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: value, in: range).frame(width: 170)
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }

    private struct ScreenOption: Identifiable { let id: Int; let name: String }
    private var screenOptions: [ScreenOption] {
        NSScreen.screens.map { ScreenOption(id: Int($0.displayID), name: $0.localizedName) }
    }
}

// MARK: - Category model

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, sound, appearance, island, display, behavior, filters, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "通用"
        case .sound: return "声音"
        case .appearance: return "外观"
        case .island: return "灵动岛"
        case .display: return "显示器"
        case .behavior: return "行为"
        case .filters: return "会话过滤"
        case .about: return "关于"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .sound: return "speaker.wave.2.fill"
        case .appearance: return "paintbrush.fill"
        case .island: return "capsule.fill"
        case .display: return "display"
        case .behavior: return "slider.horizontal.3"
        case .filters: return "eye.slash.fill"
        case .about: return "info.circle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .general: return .gray
        case .sound: return .green
        case .appearance: return .pink
        case .island: return .indigo
        case .display: return .blue
        case .behavior: return .orange
        case .filters: return .teal
        case .about: return .cyan
        }
    }
}

/// A sidebar row with comfortable padding, a hover highlight, and an accent-filled
/// selected state (white text). Custom-drawn so spacing + hover are fully controlled.
private struct SidebarRow: View {
    let cat: SettingsCategory
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label {
                Text(cat.title)
                    .foregroundStyle(selected ? Color.white : Color.primary)
            } icon: {
                CategoryIcon(symbol: cat.symbol, tint: cat.tint)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? AnyShapeStyle(Color.accentColor)
                               : hovering ? AnyShapeStyle(Color.primary.opacity(0.08))
                                          : AnyShapeStyle(Color.clear))
        )
        .onHover { hovering = $0 }
    }
}

/// A System-Settings-style coloured rounded-square glyph for a sidebar row.
private struct CategoryIcon: View {
    let symbol: String
    let tint: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.gradient)
            .frame(width: 22, height: 22)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// A small add/remove list editor for one filter category. Mutating `items` flows
/// straight back into Settings (persist + live refresh of the island).
private struct FilterEditor: View {
    let placeholder: String
    @Binding var items: [String]
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                HStack {
                    Text(item).font(.callout).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { items.removeAll { $0 == item } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("添加", action: add)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func add() {
        let v = draft.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty, !items.contains(v) else { return }
        items.append(v); draft = ""
    }
}
