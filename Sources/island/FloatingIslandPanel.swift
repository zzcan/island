import AppKit
import SwiftUI
import Combine

/// NSPanel that refuses AppKit's automatic "keep the window below the menu bar"
/// constraint, so we can place the capsule flush at the very top of the display
/// (over the notch / menu-bar strip). Without this override, setFrameOrigin to a
/// point inside the menu-bar region is silently clamped back down.
private final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Shared, mutable holder for the island's current visible rect (top-left origin, in
/// the hosting view's coordinate space, i.e. within the 500×360 canvas). IslandView
/// writes it as the island grows/shrinks; the panel uses it to decide click passthrough.
@MainActor final class IslandHitRegion {
    var rect: CGRect = .zero
}

/// Continuous 0…1 "how open should the island be" signal, driven by how close the
/// cursor is to the island. The panel updates it on every mouse-move; IslandView
/// observes it and morphs its geometry to match — so the island opens as the pointer
/// approaches instead of only on direct hover.
@MainActor final class IslandProximity: ObservableObject {
    @Published var value: CGFloat = 0
}

/// Lets the SwiftUI IslandView drive horizontal repositioning of the hosting panel.
/// The panel installs these callbacks after init; the view calls them from its drag
/// gesture (translation is the cumulative horizontal delta since the drag began).
@MainActor final class IslandDragProxy {
    var onChanged: ((CGFloat) -> Void)?
    var onEnded: (() -> Void)?
}

/// Borderless, non-activating floating panel that hosts the IslandView at the
/// top-center of the main screen. Non-activating so hovering/clicking it never
/// steals focus from the user's terminal.
@MainActor
final class FloatingIslandPanel {
    private let panel: NSPanel
    private let hitRegion = IslandHitRegion()
    private let dragProxy = IslandDragProxy()
    private let proximity = IslandProximity()
    private var monitors: [Any] = []
    private var settingsCancellable: AnyCancellable?
    private var resetObserver: NSObjectProtocol?

    /// Persisted horizontal offset (points) from the screen-centered default position.
    /// Lets the user drag the island sideways to clear the menu-bar status icons.
    private static let offsetKey = "island.horizontalOffset"
    /// Default horizontal offset for a fresh install / after "复位水平位置" — slightly
    /// left of dead-center, the position settled on in use.
    private static let defaultOffset: CGFloat = -7
    private var horizontalOffset: CGFloat = 0
    private var dragStartOffset: CGFloat?
    private var isDragging = false

    init(appModel: AppModel) {
        let region = hitRegion
        let proxy = dragProxy
        let hosting = NSHostingView(rootView: IslandView(hitRegion: region, drag: proxy, proximity: proximity).environmentObject(appModel))
        // Fixed generous canvas; the island draws top-center, the rest is transparent.
        // Wide enough to fit the 560pt expanded panel plus room to drag it sideways, and
        // tall enough for a full plan-review card (which can be ~640pt) — the panel's top
        // stays flush to the screen, so the extra height just extends transparently down.
        panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        // Start fully click-through; the mouse monitors enable interaction only while
        // the cursor is actually over the island (see updatePassthrough). A returned-nil
        // hitTest does NOT pass clicks through to other apps — only ignoresMouseEvents
        // does — so we toggle that per cursor position instead.
        panel.ignoresMouseEvents = true
        // z-order: notch > island > menu bar.
        // The notch is a hardware cutout (no pixels), so it is ALWAYS on top and the
        // capsule's middle is simply clipped by it — its wider ears peek out around
        // it. We only need the island ABOVE the menu bar (vs .floating, which sits
        // below it and let the menu bar swallow hover events, hiding the island).
        // CGShieldingWindowLevel composites over the menu bar so the ears are visible
        // and hoverable. (NotchPanel.constrainFrameRect keeps it pinned to the top.)
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        hosting.frame = panel.contentLayoutRect
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        horizontalOffset = (UserDefaults.standard.object(forKey: Self.offsetKey) as? Double).map { CGFloat($0) } ?? Self.defaultOffset
        reposition()
        installMouseMonitors()
        dragProxy.onChanged = { [weak self] translationX in self?.handleDrag(translationX: translationX) }
        dragProxy.onEnded = { [weak self] in self?.endDrag() }
        // Re-place the island whenever a settings change might affect its position
        // (display choice / top offset). Deferred so the @Published value is updated.
        settingsCancellable = Settings.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
        // The "复位水平位置" button asks us to clear the drag offset and re-center.
        resetObserver = NotificationCenter.default.addObserver(
            forName: .resetIslandPosition, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.horizontalOffset = Self.defaultOffset
                UserDefaults.standard.set(Double(Self.defaultOffset), forKey: Self.offsetKey)
                self.reposition()
            }
        }
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    /// Toggle window-level click-through based on whether the cursor is over the island.
    /// The global monitor fires while we're passthrough (events go elsewhere) → detects
    /// the cursor ENTERING the island; the local monitor fires while we own events →
    /// detects it LEAVING. Both recompute the same way.
    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.updatePassthrough()
            self?.updateProximity()
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.updatePassthrough()
            self?.updateProximity()
            return event
        }
        monitors = [global, local].compactMap { $0 }
        updatePassthrough()
        updateProximity()
    }

    /// Continuous open signal: how close is the cursor to the island?
    /// The ramp is measured against a FIXED anchor (the collapsed pill at top-center),
    /// not the live expanding rect — otherwise expansion would feed back into the
    /// distance and snap fully open. Once the cursor is actually inside the (possibly
    /// expanded) island we pin it to 1, so moving down through the rows holds it open.
    private func updateProximity() {
        let p = NSEvent.mouseLocation
        let f = panel.frame
        // Collapsed pill region in screen coords (flush at the top, centered).
        let cw = CGFloat(Settings.shared.collapsedWidth)
        let anchor = CGRect(x: f.midX - cw / 2, y: f.maxY - 40, width: cw, height: 34)
        let dx = max(max(anchor.minX - p.x, 0), p.x - anchor.maxX)
        let dy = max(max(anchor.minY - p.y, 0), p.y - anchor.maxY)
        let dist = (dx * dx + dy * dy).squareRoot()
        let pad = max(1, CGFloat(Settings.shared.activationPad))
        var v = max(0, 1 - dist / pad)
        // Hold fully open while the cursor is within the drawn island (+ a small pad).
        let r = hitRegion.rect
        if !r.isEmpty {
            let live = CGRect(x: f.minX + r.minX, y: f.maxY - r.maxY, width: r.width, height: r.height)
            if live.insetBy(dx: -6, dy: -6).contains(p) { v = 1 }
        }
        // Quantize lightly to avoid a render on every sub-pixel mouse move.
        let q = (v * 100).rounded() / 100
        if proximity.value != q { proximity.value = q }
    }

    private func updatePassthrough() {
        // While dragging, keep owning mouse events even if the cursor briefly leads the
        // moving island, so the drag gesture isn't cut off mid-move.
        if isDragging { panel.ignoresMouseEvents = false; return }
        let r = hitRegion.rect
        guard !r.isEmpty else { panel.ignoresMouseEvents = true; return }
        // Convert the island rect (top-left, within the 500×360 canvas) to screen
        // coordinates (bottom-left, matching NSEvent.mouseLocation). The canvas top is
        // panel.frame.maxY, and the rect's y grows downward, so subtract r.maxY.
        let screenRect = CGRect(x: panel.frame.minX + r.minX,
                                y: panel.frame.maxY - r.maxY,
                                width: r.width, height: r.height)
        panel.ignoresMouseEvents = !screenRect.contains(NSEvent.mouseLocation)
    }

    private func reposition() {
        // Which display hosts the island is a user choice (primary / follow-focus /
        // a specific monitor); Settings resolves it with sensible fallbacks.
        guard let screen = Settings.shared.targetScreen() ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let f = screen.frame
        let size = panel.frame.size
        // IslandView pads its content 6pt from the panel's top edge; compensate so
        // the capsule's top is flush with the physical screen top. `topOffset` then
        // nudges it further down for imperfect notch fit.
        let contentTopInset: CGFloat = 6
        let centerX = f.midX - size.width / 2
        horizontalOffset = clampedOffset(horizontalOffset, screen: f, size: size)
        panel.setFrameOrigin(NSPoint(x: centerX + horizontalOffset,
                                     y: f.maxY - size.height + contentTopInset - CGFloat(Settings.shared.topOffset)))
    }

    /// Clamp the offset so the visible island (centered within the wider transparent
    /// canvas) stays on-screen with a margin, while the canvas itself may extend past
    /// the screen edge (NotchPanel.constrainFrameRect allows that).
    private func clampedOffset(_ off: CGFloat, screen f: CGRect, size: CGSize) -> CGFloat {
        let margin: CGFloat = 130   // ~half the collapsed capsule, keeps it fully visible
        let limit = max(0, f.width / 2 - margin)
        return min(max(off, -limit), limit)
    }

    private func handleDrag(translationX: CGFloat) {
        if dragStartOffset == nil { dragStartOffset = horizontalOffset }
        isDragging = true
        horizontalOffset = (dragStartOffset ?? 0) + translationX
        reposition()   // applies the clamp and moves the panel
    }

    private func endDrag() {
        isDragging = false
        dragStartOffset = nil
        UserDefaults.standard.set(horizontalOffset, forKey: Self.offsetKey)
    }
}
