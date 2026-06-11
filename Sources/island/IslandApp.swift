import SwiftUI
import IslandCore

@main
struct IslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// The menu-bar label: the status-coloured pixel crab. A view (not a bare Image) so
/// it observes the model and re-renders the icon when the aggregate status changes.
private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Image(nsImage: MenuBarIcon.image(for: model.display.rows.map(\.status)))
            .renderingMode(.original)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var islandPanel: FloatingIslandPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        HookSync.sync(planReview: Settings.shared.planReviewEnabled)
        UpdaterManager.shared.start()
        model.start()
        let panel = FloatingIslandPanel(appModel: model)
        panel.show()
        islandPanel = panel
    }
}
