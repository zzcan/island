import SwiftUI
import IslandCore

@main
struct IslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(delegate.model)
        } label: {
            Image(systemName: delegate.model.icon.symbolName)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var islandPanel: FloatingIslandPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        let panel = FloatingIslandPanel(appModel: model)
        panel.show()
        islandPanel = panel
    }
}
