import Foundation
import AppKit
import ServiceManagement

/// Central, persisted, observable settings store. Single source of truth for every
/// user-tunable preference; views bind to it and the panel/synth read from it.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    // MARK: General
    @Published var launchAtLogin: Bool { didSet { applyLaunchAtLogin() } }

    // MARK: Sound
    @Published var soundEnabled: Bool { didSet { persist(soundEnabled, K.soundEnabled) } }
    /// Master 0…1 multiplier applied on top of each preset's own amplitude.
    @Published var soundVolume: Double { didSet { persist(soundVolume, K.soundVolume) } }
    @Published var soundSessionStart: Bool { didSet { persist(soundSessionStart, K.soundSessionStart) } }
    @Published var soundInputRequired: Bool { didSet { persist(soundInputRequired, K.soundInputRequired) } }
    @Published var soundTaskComplete: Bool { didSet { persist(soundTaskComplete, K.soundTaskComplete) } }

    // MARK: Island geometry / proximity
    @Published var activationPad: Double { didSet { persist(activationPad, K.activationPad) } }
    @Published var collapsedWidth: Double { didSet { persist(collapsedWidth, K.collapsedWidth) } }
    @Published var expandedWidth: Double { didSet { persist(expandedWidth, K.expandedWidth) } }
    /// Extra pixels to push the island down from the very top (notch-fit nudge).
    @Published var topOffset: Double { didSet { persist(topOffset, K.topOffset) } }

    // MARK: Display
    /// 0 = primary (menu-bar) display, 1 = follow focus, otherwise a CGDirectDisplayID.
    @Published var displayChoice: Int { didSet { persist(displayChoice, K.displayChoice) } }

    // MARK: Quiet hours (mute all sounds within a daily window)
    @Published var quietHoursEnabled: Bool { didSet { persist(quietHoursEnabled, K.quietEnabled) } }
    /// Minutes since midnight.
    @Published var quietStart: Int { didSet { persist(quietStart, K.quietStart) } }
    @Published var quietEnd: Int { didSet { persist(quietEnd, K.quietEnd) } }

    // MARK: Behaviour
    /// AutoExpandMode rawValue: 0 all events, 1 actionable only, 2 never.
    @Published var autoExpandMode: Int { didSet { persist(autoExpandMode, K.autoExpandMode) } }
    /// Seconds an event-driven auto-expansion stays open before retracting.
    @Published var autoCollapseDwell: Double { didSet { persist(autoCollapseDwell, K.dwell) } }

    // MARK: Filters — hide sessions whose cwd contains / whose first prompt starts with.
    @Published var cwdFilters: [String] { didSet { persist(cwdFilters, K.cwdFilters) } }
    @Published var promptFilters: [String] { didSet { persist(promptFilters, K.promptFilters) } }

    // MARK: Notifications / interaction
    /// Post macOS banner notifications on needs-input / done.
    @Published var notificationsEnabled: Bool { didSet { persist(notificationsEnabled, K.notificationsEnabled) } }

    // MARK: Remote push (Bark)
    /// 启用向 iPhone Bark 的远程推送（needs-input / done / plan review）。
    @Published var barkEnabled: Bool { didSet { persist(barkEnabled, K.barkEnabled) } }
    /// Bark 服务器，默认官方 https://api.day.app，支持自建。
    @Published var barkServer: String { didSet { persist(barkServer, K.barkServer) } }
    /// Bark device key（iPhone app 首页那串）。
    @Published var barkDeviceKey: String { didSet { persist(barkDeviceKey, K.barkDeviceKey) } }
    /// Clicking a session row jumps to its terminal/IDE.
    @Published var clickToJump: Bool { didSet { persist(clickToJump, K.clickToJump) } }
    /// Intercept ExitPlanMode and review plans in the island. When off, plan approval
    /// falls back to Claude's own terminal prompt.
    @Published var planReviewEnabled: Bool {
        didSet {
            persist(planReviewEnabled, K.planReviewEnabled)
            HookSync.sync(planReview: planReviewEnabled)
        }
    }
    /// Minutes a done/idle session lingers before it's pruned as residual.
    @Published var sessionRetentionMinutes: Double { didSet { persist(sessionRetentionMinutes, K.retention) } }

    // MARK: Appearance
    /// Multiplier on the expanded panel's text sizes.
    @Published var fontScale: Double { didSet { persist(fontScale, K.fontScale) } }
    /// Which sprite family (SpriteTheme rawValue): 0 invaders, 1 ghosts, 2 mario, 3 slime.
    @Published var spriteTheme: Int { didSet { persist(spriteTheme, K.spriteTheme) } }
    /// Colour tint: 0 = 原色 (per-status), 1 = phosphor green, 2 = amber, 3 = Game Boy.
    @Published var colorMode: Int { didSet { persist(colorMode, K.colorMode) } }

    private let d = UserDefaults.standard
    private func persist(_ v: Any, _ key: String) { d.set(v, forKey: key) }

    private enum K {
        static let soundEnabled = "island.soundEnabled"   // kept from the original speaker toggle
        static let soundVolume = "s.soundVolume"
        static let soundSessionStart = "s.snd.sessionStart"
        static let soundInputRequired = "s.snd.inputRequired"
        static let soundTaskComplete = "s.snd.taskComplete"
        static let activationPad = "s.activationPad"
        static let collapsedWidth = "s.collapsedWidth"
        static let expandedWidth = "s.expandedWidth"
        static let topOffset = "s.topOffset"
        static let displayChoice = "s.displayChoice"
        static let quietEnabled = "s.quietEnabled"
        static let quietStart = "s.quietStart"
        static let quietEnd = "s.quietEnd"
        static let autoExpandMode = "s.autoExpandMode"
        static let dwell = "s.autoCollapseDwell"
        static let cwdFilters = "s.cwdFilters"
        static let promptFilters = "s.promptFilters"
        static let notificationsEnabled = "s.notificationsEnabled"
        static let barkEnabled = "s.bark.enabled"
        static let barkServer = "s.bark.server"
        static let barkDeviceKey = "s.bark.deviceKey"
        static let clickToJump = "s.clickToJump"
        static let planReviewEnabled = "s.planReviewEnabled"
        static let retention = "s.sessionRetentionMinutes"
        static let fontScale = "s.fontScale"
        static let spriteTheme = "s.spriteTheme"
        static let colorMode = "s.pixelTheme"   // key kept for migration
    }

    private init() {
        let d = UserDefaults.standard
        soundEnabled = d.object(forKey: K.soundEnabled) as? Bool ?? true
        soundVolume = d.object(forKey: K.soundVolume) as? Double ?? 1.0
        soundSessionStart = d.object(forKey: K.soundSessionStart) as? Bool ?? false
        soundInputRequired = d.object(forKey: K.soundInputRequired) as? Bool ?? true
        soundTaskComplete = d.object(forKey: K.soundTaskComplete) as? Bool ?? true
        activationPad = d.object(forKey: K.activationPad) as? Double ?? 0
        collapsedWidth = d.object(forKey: K.collapsedWidth) as? Double ?? 246
        expandedWidth = d.object(forKey: K.expandedWidth) as? Double ?? 560
        topOffset = d.object(forKey: K.topOffset) as? Double ?? 0
        displayChoice = d.object(forKey: K.displayChoice) as? Int ?? 0
        quietHoursEnabled = d.object(forKey: K.quietEnabled) as? Bool ?? false
        quietStart = d.object(forKey: K.quietStart) as? Int ?? 22 * 60   // 22:00
        quietEnd = d.object(forKey: K.quietEnd) as? Int ?? 8 * 60        // 08:00
        autoExpandMode = d.object(forKey: K.autoExpandMode) as? Int ?? 0
        autoCollapseDwell = d.object(forKey: K.dwell) as? Double ?? 3
        cwdFilters = d.stringArray(forKey: K.cwdFilters) ?? []
        promptFilters = d.stringArray(forKey: K.promptFilters) ?? []
        notificationsEnabled = d.object(forKey: K.notificationsEnabled) as? Bool ?? true
        barkEnabled = d.object(forKey: K.barkEnabled) as? Bool ?? false
        barkServer = d.object(forKey: K.barkServer) as? String ?? "https://api.day.app"
        barkDeviceKey = d.object(forKey: K.barkDeviceKey) as? String ?? ""
        clickToJump = d.object(forKey: K.clickToJump) as? Bool ?? true
        planReviewEnabled = d.object(forKey: K.planReviewEnabled) as? Bool ?? false
        sessionRetentionMinutes = d.object(forKey: K.retention) as? Double ?? 30
        fontScale = d.object(forKey: K.fontScale) as? Double ?? 1.0
        spriteTheme = d.object(forKey: K.spriteTheme) as? Int ?? 0
        colorMode = d.object(forKey: K.colorMode) as? Int ?? 0
        // Source of truth for the toggle is the actual login-item registration.
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    /// Restore every preference to its built-in default (login item left untouched).
    func resetToDefaults() {
        soundEnabled = true; soundVolume = 1.0
        soundSessionStart = false; soundInputRequired = true; soundTaskComplete = true
        quietHoursEnabled = false; quietStart = 22 * 60; quietEnd = 8 * 60
        activationPad = 0; collapsedWidth = 246; expandedWidth = 560; topOffset = 0
        displayChoice = 0
        autoCollapseDwell = 3; autoExpandMode = 0
        cwdFilters = []; promptFilters = []
        notificationsEnabled = true; clickToJump = true; planReviewEnabled = false
        barkEnabled = false; barkServer = "https://api.day.app"; barkDeviceKey = ""
        sessionRetentionMinutes = 30
        fontScale = 1.0; spriteTheme = 0; colorMode = 0
    }

    /// True if `now` falls within the configured quiet-hours window (handles windows
    /// that cross midnight, e.g. 22:00 → 08:00).
    func isQuietNow(_ now: Date = Date()) -> Bool {
        guard quietHoursEnabled, quietStart != quietEnd else { return false }
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let mins = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return quietStart < quietEnd
            ? (mins >= quietStart && mins < quietEnd)
            : (mins >= quietStart || mins < quietEnd)
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("island: launch-at-login toggle failed: \(error)")
        }
    }

    /// Screen the island should live on, per `displayChoice`. Falls back gracefully
    /// (e.g. a chosen display that's been unplugged → main).
    func targetScreen() -> NSScreen? {
        switch displayChoice {
        case 0: return NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
        case 1: return NSScreen.main
        default:
            let id = CGDirectDisplayID(UInt32(truncatingIfNeeded: displayChoice))
            return NSScreen.screens.first { $0.displayID == id } ?? NSScreen.main
        }
    }
}

extension NSScreen {
    /// The CoreGraphics display id, used to pin the island to a specific monitor.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

extension Notification.Name {
    /// Posted by the settings UI to ask the panel to re-center (clear drag offset).
    static let resetIslandPosition = Notification.Name("island.resetPosition")
}
