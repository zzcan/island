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
    /// When set, the pixel size is additionally capped so the sprite never grows
    /// wider than this. Lets status sprites with different grid sizes share roughly
    /// one cell size and sit inside a fixed-size box.
    var maxWidth: CGFloat? = nil
    /// When set, forces an exact pixel (cell) size in points and ignores
    /// height/maxWidth. Use for the status avatars so every alien — the 11-wide
    /// crab, the 8-wide squid, the 12-wide octopus — renders at the SAME cell size
    /// and just centers in its box. This is what keeps the family visually uniform.
    var pixelSize: CGFloat? = nil
    /// Overrides the sprite's own colour (used by the monochrome pixel themes).
    var colorOverride: Color? = nil

    var body: some View {
        let rows = max(sprite.rows, 1)
        let cols = max(sprite.cols, 1)
        let byHeight = height / CGFloat(rows)
        let byWidth = (maxWidth ?? .infinity) / CGFloat(cols)
        let px = pixelSize ?? max(1, min(byHeight, byWidth).rounded(.down))
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
                    gc.fill(Path(rect), with: .color(colorOverride ?? sprite.color))
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

// MARK: - Sprite themes

/// A selectable family of status glyphs. Each maps the four statuses to a sprite;
/// colour is the sprite's own "原色" unless a monochrome colour mode overrides it.
enum SpriteTheme: Int, CaseIterable, Identifiable {
    case invaders, ghosts, mario, slime, zelda, tetris, dino, tamagotchi, robot, terminal
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .invaders:   return "太空侵略者"
        case .ghosts:     return "吃豆人幽灵"
        case .mario:      return "马里奥"
        case .slime:      return "史莱姆"
        case .zelda:      return "塞尔达"
        case .tetris:     return "俄罗斯方块"
        case .dino:       return "恐龙快跑"
        case .tamagotchi: return "拓麻歌子"
        case .robot:      return "机器人"
        case .terminal:   return "极客终端"
        }
    }
    func sprite(for status: SessionStatus) -> PixelSprite {
        PixelSprite.sprite(theme: self, status: status)
    }
}

// MARK: - Sprite library

extension PixelSprite {
    // Status palette ("原色" mode).
    static let phosphor = Color(red: 0.30, green: 1.0, blue: 0.55)
    private static let blue = Color(red: 0.35, green: 0.70, blue: 1.0)
    private static let yellow = Color(red: 1.0, green: 0.82, blue: 0.20)
    private static let red = Color(red: 1.0, green: 0.40, blue: 0.38)
    private static let gold = Color(red: 1.0, green: 0.80, blue: 0.28)
    private static let brickColor = Color(red: 0.80, green: 0.52, blue: 0.34)
    private static let dim = Color.gray.opacity(0.5)
    private static let cyan = Color(red: 0.30, green: 0.85, blue: 0.95)
    private static let purple = Color(red: 0.66, green: 0.42, blue: 0.92)

    static func sprite(theme: SpriteTheme, status: SessionStatus) -> PixelSprite {
        switch theme {
        case .invaders:   return invaders(status)
        case .ghosts:     return ghosts(status)
        case .mario:      return mario(status)
        case .slime:      return slime(status)
        case .zelda:      return zelda(status)
        case .tetris:     return tetris(status)
        case .dino:       return dino(status)
        case .tamagotchi: return tama(status)
        case .robot:      return robot(status)
        case .terminal:   return terminal(status)
        }
    }

    /// Convenience: the default (Space Invaders) set.
    static func forStatus(_ status: SessionStatus) -> PixelSprite { invaders(status) }

    // MARK: Space Invaders (crab / squid / octopus)
    private static func invaders(_ s: SessionStatus) -> PixelSprite {
        switch s {
        case .done:       return PixelSprite(frames: [crabA, crabB], color: phosphor, frameInterval: 0.45)
        case .idle:       return PixelSprite(frames: [crabA], color: dim)
        case .working:    return PixelSprite(frames: [squidA, squidB], color: blue, frameInterval: 0.22)
        case .needsInput: return PixelSprite(frames: [octopusA, octopusB], color: yellow, frameInterval: 0.4, pulse: true)
        }
    }
    private static let crabA = [
        "..X.....X..", "...X...X...", "..XXXXXXX..", ".XX.XXX.XX.",
        "XXXXXXXXXXX", "X.XXXXXXX.X", "X.X.....X.X", "...XX.XX...",
    ]
    private static let crabB = [
        "..X.....X..", "X..X...X..X", "X.XXXXXXX.X", "XXX.XXX.XXX",
        "XXXXXXXXXXX", ".XXXXXXXXX.", "..X.....X..", ".X.......X.",
    ]
    private static let squidA = [
        "...XX...", "..XXXX..", ".XXXXXX.", "XX.XX.XX",
        "XXXXXXXX", "..X..X..", ".X.XX.X.", "X.X..X.X",
    ]
    private static let squidB = [
        "...XX...", "..XXXX..", ".XXXXXX.", "XX.XX.XX",
        "XXXXXXXX", ".X.XX.X.", "X......X", ".X....X.",
    ]
    private static let octopusA = [
        "....XXXX....", ".XXXXXXXXXX.", "XXXXXXXXXXXX", "XXX..XX..XXX",
        "XXXXXXXXXXXX", "...XX..XX...", "..XX.XX.XX..", "XX........XX",
    ]
    private static let octopusB = [
        "....XXXX....", ".XXXXXXXXXX.", "XXXXXXXXXXXX", "XXX..XX..XXX",
        "XXXXXXXXXXXX", "..XXX..XXX..", ".XX..XX..XX.", "..XX....XX..",
    ]

    // MARK: Pac-Man ghosts (ghost / scared ghost / pac-man)
    private static func ghosts(_ s: SessionStatus) -> PixelSprite {
        switch s {
        case .done:       return PixelSprite(frames: [pac], color: gold)
        case .idle:       return PixelSprite(frames: [ghostA], color: dim)
        case .working:    return PixelSprite(frames: [ghostA, ghostB], color: red, frameInterval: 0.3)
        case .needsInput: return PixelSprite(frames: [ghostA, ghostB], color: blue, frameInterval: 0.3, pulse: true)
        }
    }
    private static let ghostA = [
        ".XXXXXX.", "XXXXXXXX", "XX.XX.XX", "XX.XX.XX",
        "XXXXXXXX", "XXXXXXXX", "XXXXXXXX", "X.X..X.X",
    ]
    private static let ghostB = [
        ".XXXXXX.", "XXXXXXXX", "XX.XX.XX", "XX.XX.XX",
        "XXXXXXXX", "XXXXXXXX", "XXXXXXXX", ".X.XX.X.",
    ]
    private static let pac = [
        "..XXXX..", ".XXXXX..", "XXXXX...", "XXXX....",
        "XXXX....", "XXXXX...", ".XXXXXX.", "..XXXX..",
    ]

    // MARK: Mario (mushroom / ? block / coin / brick)
    private static func mario(_ s: SessionStatus) -> PixelSprite {
        switch s {
        case .done:       return PixelSprite(frames: [coin], color: gold)
        case .idle:       return PixelSprite(frames: [brick], color: brickColor.opacity(0.6))
        case .working:    return PixelSprite(frames: [mushroom], color: red)
        case .needsInput: return PixelSprite(frames: [qblock], color: yellow, pulse: true)
        }
    }
    private static let mushroom = [
        "..XXXX..", ".XXXXXX.", "XXXXXXXX", "XX.XX.XX",
        ".XXXXXX.", "..XXXX..", "..X..X..", "..XXXX..",
    ]
    private static let qblock = [
        "XXXXXXXX", "X......X", "X.XXX..X", "X...X..X",
        "X..X...X", "X......X", "X..X...X", "XXXXXXXX",
    ]
    private static let coin = [
        "..XXXX..", ".XXXXXX.", "XX.XX.XX", "XX.XX.XX",
        "XX.XX.XX", "XX.XX.XX", ".XXXXXX.", "..XXXX..",
    ]
    private static let brick = [
        "XXXXXXXX", "X..X..X.", "XXXXXXXX", ".X..X..X",
        "XXXXXXXX", "X..X..X.", "XXXXXXXX", ".X..X..X",
    ]

    // MARK: Slime (one creature, four moods)
    private static func slime(_ s: SessionStatus) -> PixelSprite {
        switch s {
        case .done:       return PixelSprite(frames: [slimeSmile], color: phosphor)
        case .idle:       return PixelSprite(frames: [slimeFlat], color: dim)
        case .working:    return PixelSprite(frames: [slimeTall, slimeSquish], color: blue, frameInterval: 0.25)
        case .needsInput: return PixelSprite(frames: [slimeWide], color: yellow, pulse: true)
        }
    }
    private static let slimeTall = [
        "...XX...", "..XXXX..", ".XXXXXX.", "XXXXXXXX",
        "XX.XX.XX", "XXXXXXXX", "XXXXXXXX", ".XXXXXX.",
    ]
    private static let slimeSquish = [
        "........", "...XX...", "..XXXX..", ".XXXXXX.",
        "XX.XX.XX", "XXXXXXXX", "XXXXXXXX", "XXXXXXXX",
    ]
    private static let slimeFlat = [
        "........", "........", "...XX...", "..XXXX..",
        ".XX..XX.", ".XXXXXX.", "XXXXXXXX", "XXXXXXXX",
    ]
    private static let slimeWide = [
        "...XX...", "..XXXX..", ".XXXXXX.", "XXXXXXXX",
        "X.X..X.X", "XXXXXXXX", "XXXXXXXX", ".XXXXXX.",
    ]
    private static let slimeSmile = [
        "...XX...", "..XXXX..", ".XXXXXX.", "XXXXXXXX",
        "XX.XX.XX", "XXXXXXXX", "X.XXXX.X", ".XXXXXX.",
    ]

    // MARK: Zelda (triforce / rupee / heart)
    private static func zelda(_ s: SessionStatus) -> PixelSprite {
        switch s {
        case .done:       return PixelSprite(frames: [triforce], color: gold)
        case .idle:       return PixelSprite(frames: [rupee], color: dim)
        case .working:    return PixelSprite(frames: [rupee], color: phosphor)
        case .needsInput: return PixelSprite(frames: [heart], color: red, pulse: true)
        }
    }
    private static let triforce = [
        "...XX...", "...XX...", "..XXXX..", "..XXXX..",
        ".XX..XX.", ".XX..XX.", "XXXXXXXX", "XXXXXXXX",
    ]
    private static let rupee = [
        "...XX...", "..XXXX..", ".XXXXXX.", "XXXXXXXX",
        "XXXXXXXX", ".XXXXXX.", "..XXXX..", "...XX...",
    ]
    private static let heart = [
        ".XX.XX..", "XXXXXXX.", "XXXXXXX.", "XXXXXXX.",
        ".XXXXX..", "..XXX...", "...X....", "........",
    ]

    // MARK: Tetris (tetrominoes)
    private static func tetris(_ s: SessionStatus) -> PixelSprite {
        switch s {
        case .done:       return PixelSprite(frames: [pieceI], color: cyan)
        case .idle:       return PixelSprite(frames: [pieceO], color: dim)
        case .working:    return PixelSprite(frames: [pieceT], color: purple)
        case .needsInput: return PixelSprite(frames: [pieceS], color: red, pulse: true)
        }
    }
    private static let pieceI = [
        "........", "........", "........", "XXXXXXXX",
        "XXXXXXXX", "........", "........", "........",
    ]
    private static let pieceO = [
        "........", "........", "..XXXX..", "..XXXX..",
        "..XXXX..", "..XXXX..", "........", "........",
    ]
    private static let pieceT = [
        "........", ".XXXXXX.", ".XXXXXX.", "...XX...",
        "...XX...", "........", "........", "........",
    ]
    private static let pieceS = [
        "........", "........", "..XXXX..", "..XXXX..",
        "XXXX....", "XXXX....", "........", "........",
    ]

    // MARK: Dino (running dino / cactus)
    private static func dino(_ s: SessionStatus) -> PixelSprite {
        switch s {
        case .done:       return PixelSprite(frames: [dinoStand], color: phosphor)
        case .idle:       return PixelSprite(frames: [dinoStand], color: dim)
        case .working:    return PixelSprite(frames: [dinoRunA, dinoRunB], color: phosphor, frameInterval: 0.18)
        case .needsInput: return PixelSprite(frames: [cactus], color: phosphor, pulse: true)
        }
    }
    private static let dinoStand = [
        ".....XXX", ".....X.X", ".....XXX", "XX...XXX",
        "XXX.XXXX", "XXXXXXX.", ".XXXXX..", "..X..X..",
    ]
    private static let dinoRunA = [
        ".....XXX", ".....X.X", ".....XXX", "XX...XXX",
        "XXX.XXXX", "XXXXXXX.", ".XXXXX..", "..X...X.",
    ]
    private static let dinoRunB = [
        ".....XXX", ".....X.X", ".....XXX", "XX...XXX",
        "XXX.XXXX", "XXXXXXX.", ".XXXXX..", ".X...X..",
    ]
    private static let cactus = [
        "...X....", ".X.X....", ".X.X.X..", ".XXX.X..",
        "...XXX..", "...X....", "...X....", "...X....",
    ]

    // MARK: Tamagotchi (egg / blobby pet)
    private static func tama(_ s: SessionStatus) -> PixelSprite {
        switch s {
        case .done:       return PixelSprite(frames: [petHappy], color: phosphor)
        case .idle:       return PixelSprite(frames: [egg], color: dim)
        case .working:    return PixelSprite(frames: [petA, petB], color: blue, frameInterval: 0.25)
        case .needsInput: return PixelSprite(frames: [petA], color: yellow, pulse: true)
        }
    }
    private static let egg = [
        "...XX...", "..XXXX..", ".XXXXXX.", ".XXXXXX.",
        "XXXXXXXX", "XXXXXXXX", "XXXXXXXX", ".XXXXXX.",
    ]
    private static let petA = [
        ".X....X.", ".XXXXXX.", "XXXXXXXX", "XX.XX.XX",
        "XXXXXXXX", "XXXXXXXX", ".XXXXXX.", "..X..X..",
    ]
    private static let petB = [
        ".X....X.", ".XXXXXX.", "XXXXXXXX", "XX.XX.XX",
        "XXXXXXXX", "XXXXXXXX", ".XXXXXX.", ".X....X.",
    ]
    private static let petHappy = [
        ".X....X.", ".XXXXXX.", "XXXXXXXX", "XX.XX.XX",
        "XXXXXXXX", "X.XXXX.X", ".XXXXXX.", "..X..X..",
    ]

    // MARK: Robot (one head, expressions)
    private static func robot(_ s: SessionStatus) -> PixelSprite {
        switch s {
        case .done:       return PixelSprite(frames: [robotHappy], color: phosphor)
        case .idle:       return PixelSprite(frames: [robotSleep], color: dim)
        case .working:    return PixelSprite(frames: [robotScanA, robotScanB], color: blue, frameInterval: 0.3)
        case .needsInput: return PixelSprite(frames: [robotAlert], color: yellow, pulse: true)
        }
    }
    private static let robotScanA = [
        "...X....", ".XXXXXX.", "XXXXXXXX", "XXX.X.XX",
        "XXXXXXXX", "X.XXXX.X", ".XXXXXX.", "..X..X..",
    ]
    private static let robotScanB = [
        "...X....", ".XXXXXX.", "XXXXXXXX", "XX.X.XXX",
        "XXXXXXXX", "X.XXXX.X", ".XXXXXX.", "..X..X..",
    ]
    private static let robotAlert = [
        "...X....", ".XXXXXX.", "XXXXXXXX", "X.X..X.X",
        "XXXXXXXX", "X.XXXX.X", ".XXXXXX.", "..X..X..",
    ]
    private static let robotHappy = [
        "...X....", ".XXXXXX.", "XXXXXXXX", "XX.XX.XX",
        "XXXXXXXX", "X.X..X.X", ".XXXXXX.", "..X..X..",
    ]
    private static let robotSleep = [
        "...X....", ".XXXXXX.", "XXXXXXXX", "XXXXXXXX",
        "XXXXXXXX", "X.XXXX.X", ".XXXXXX.", "..X..X..",
    ]

    // MARK: Terminal (cursor / hourglass / prompt / check)
    private static func terminal(_ s: SessionStatus) -> PixelSprite {
        switch s {
        case .done:       return PixelSprite(frames: [check], color: phosphor)
        case .idle:       return PixelSprite(frames: [cursor], color: dim)
        case .working:    return PixelSprite(frames: [hourA, hourB], color: blue, frameInterval: 0.4)
        case .needsInput: return PixelSprite(frames: [prompt], color: yellow, pulse: true)
        }
    }
    private static let cursor = [
        "........", "........", "..XXXX..", "..XXXX..",
        "..XXXX..", "..XXXX..", "........", "........",
    ]
    private static let hourA = [
        "XXXXXXX.", "XXXXXX..", ".XXXX...", "..XX....",
        "..XX....", "...X....", "..X.....", "XXXXXXX.",
    ]
    private static let hourB = [
        "XXXXXXX.", ".XX.X...", "..XX....", "...X....",
        "..XX....", ".XXXX...", "XXXXXX..", "XXXXXXX.",
    ]
    private static let prompt = [
        ".X......", ".XX.....", ".XXX....", ".XXXX...",
        ".XXX....", ".XX.....", ".X......", "........",
    ]
    private static let check = [
        "......X.", ".....XX.", "....XX..", "X..XX...",
        "XX.XX...", ".XXX....", "..X.....", "........",
    ]
}
