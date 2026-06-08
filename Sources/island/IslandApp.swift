import SwiftUI
import IslandCore

@main
struct IslandApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(model)
                .onAppear { model.start() }
        } label: {
            Image(systemName: model.icon.symbolName)
        }
        .menuBarExtraStyle(.menu)
    }
}
