import Foundation
import Sparkle

/// Sparkle glue. Owns the standard updater (automatic daily checks + its own UI).
/// Feed URL and EdDSA public key live in Info.plist (SUFeedURL / SUPublicEDKey),
/// written by Scripts/bundle.sh.
@MainActor
final class UpdaterManager {
    static let shared = UpdaterManager()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    /// Kick off the shared instance (called once at launch so scheduled checks start).
    /// ISLAND_CHECK_UPDATES=1 forces an immediate interactive check (debugging/e2e).
    func start() {
        if ProcessInfo.processInfo.environment["ISLAND_CHECK_UPDATES"] == "1" {
            checkForUpdates()
        }
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
