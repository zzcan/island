import SwiftUI
import IslandCore

@main
struct IslandApp: App {
    @StateObject private var model: AppModel

    init() {
        let m = AppModel()
        _model = StateObject(wrappedValue: m)
        MainActor.assumeIsolated { m.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(model)
        } label: {
            Image(systemName: model.icon.symbolName)
        }
        .menuBarExtraStyle(.menu)
    }
}
