import SwiftUI
import IslandCore

// MARK: - Pixel sprite model

/// A tiny pixel-art sprite. Each frame is an array of equal-meaning rows where
/// any character other than "." or " " is a lit pixel. Frames cycle on a timer
/// to animate; `pulse` adds a continuous breathing (opacity + scale) on top.
///
/// Drawn the same "one rectangle per cell" way as `IdenticonView`, just via
/// `Canvas` so a 16×8 grid stays cheap.
struct PixelSprite {
    let frames: [[String]]
    let color: Color
    /// Seconds per frame. 0 → static (only the first frame is shown).
    let frameInterval: Double
    /// When true the whole glyph breathes (opacity + slight scale).
    let pulse: Bool

    init(frames: [[String]], color: Color, frameInterval: Double = 0, pulse: Bool = false) {
        self.frames = frames
        self.color = color
        self.frameInterval = frameInterval
        self.pulse = pulse
    }

    var cols: Int { frames.flatMap { $0 }.map(\.count).max() ?? 0 }
    var rows: Int { frames.map(\.count).max() ?? 0 }
}

// MARK: - Renderer

struct PixelGlyphView: View {
    let sprite: PixelSprite
    /// Target height in points; pixels are snapped to whole points so the art
    /// stays crisp, and width follows to keep cells square.
    var height: CGFloat = 14

    var body: some View {
        let rows = max(sprite.rows, 1)
        let px = max(1, (height / CGFloat(rows)).rounded(.down))
        let w = px * CGFloat(sprite.cols)
        let h = px * CGFloat(rows)

        Group {
            if sprite.frames.count > 1, sprite.frameInterval > 0 {
                TimelineView(.periodic(from: .now, by: sprite.frameInterval)) { ctx in
                    canvas(frameIndex(at: ctx.date), px: px)
                }
            } else {
                canvas(0, px: px)
            }
        }
        .frame(width: w, height: h)
        .modifier(PulseModifier(active: sprite.pulse))
    }

    private func frameIndex(at date: Date) -> Int {
        let n = sprite.frames.count
        guard n > 1, sprite.frameInterval > 0 else { return 0 }
        let step = Int(date.timeIntervalSinceReferenceDate / sprite.frameInterval)
        return ((step % n) + n) % n
    }

    private func canvas(_ index: Int, px: CGFloat) -> some View {
        let frame = sprite.frames[min(index, sprite.frames.count - 1)]
        return Canvas { gc, _ in
            for (r, line) in frame.enumerated() {
                for (c, ch) in line.enumerated() where ch != "." && ch != " " {
                    let rect = CGRect(x: CGFloat(c) * px, y: CGFloat(r) * px, width: px, height: px)
                    gc.fill(Path(rect), with: .color(sprite.color))
                }
            }
        }
    }
}

/// Continuous breathing used by attention states.
private struct PulseModifier: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let phase = (sin(t * 3.2) + 1) / 2 // 0…1
                content
                    .opacity(0.4 + 0.6 * phase)
                    .scaleEffect(0.9 + 0.1 * phase)
            }
        } else {
            content
        }
    }
}

// MARK: - Sprite library

extension PixelSprite {
    /// Classic phosphor green, like the reference icon.
    static let phosphor = Color(red: 0.30, green: 1.0, blue: 0.55)

    /// The iconic "crab" Space Invader — two march frames.
    private static let invaderA: [String] = [
        "..X.....X..",
        "...X...X...",
        "..XXXXXXX..",
        ".XX.XXX.XX.",
        "XXXXXXXXXXX",
        "X.XXXXXXX.X",
        "X.X.....X.X",
        "...XX.XX...",
    ]
    private static let invaderB: [String] = [
        "..X.....X..",
        "X..X...X..X",
        "X.XXXXXXX.X",
        "XXX.XXX.XXX",
        "XXXXXXXXXXX",
        ".XXXXXXXXX.",
        "..X.....X..",
        ".X.......X.",
    ]

    /// A blinking text I-beam cursor, drawn beside the invader.
    private static let iBeamOn: [String] = ["XXX", ".X.", ".X.", ".X.", ".X.", ".X.", ".X.", "XXX"]
    private static let iBeamOff: [String] = Array(repeating: "...", count: 8)

    /// Glue two sprites side by side with a blank gap between them.
    private static func glue(_ a: [String], _ b: [String], gap: Int = 2) -> [String] {
        let pad = String(repeating: ".", count: gap)
        return zip(a, b).map { $0 + pad + $1 }
    }

    /// done — green invader marching + cursor blinking (matches the reference).
    static let done = PixelSprite(
        frames: [glue(invaderA, iBeamOn), glue(invaderB, iBeamOff)],
        color: phosphor,
        frameInterval: 0.45
    )

    /// idle — the same invader, asleep: dim, grey, motionless.
    static let idle = PixelSprite(
        frames: [invaderA],
        color: .gray.opacity(0.5)
    )

    /// working — three blue dots bouncing in sequence (a loader).
    static let working = PixelSprite(
        frames: [
            ["XX......", "XX.XX.XX"], // left dot up
            ["...XX...", "XX.XX.XX"], // middle dot up
            ["......XX", "XX.XX.XX"], // right dot up
        ],
        color: Color(red: 0.35, green: 0.7, blue: 1.0),
        frameInterval: 0.16
    )

    /// needsInput — a yellow pixel "!" that breathes for attention.
    static let needsInput = PixelSprite(
        frames: [[
            "XX",
            "XX",
            "XX",
            "XX",
            "XX",
            "..",
            "XX",
            "XX",
        ]],
        color: Color(red: 1.0, green: 0.82, blue: 0.2),
        pulse: true
    )

    static func forStatus(_ status: SessionStatus) -> PixelSprite {
        switch status {
        case .done:       return .done
        case .needsInput: return .needsInput
        case .working:    return .working
        case .idle:       return .idle
        }
    }
}
