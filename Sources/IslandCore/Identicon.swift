import Foundation

public struct IdenticonGrid: Equatable, Sendable {
    public let cells: [[Bool]]   // size x size, horizontally symmetric
    public let hue: Double       // 0..<1
    public init(cells: [[Bool]], hue: Double) { self.cells = cells; self.hue = hue }
}

public enum Identicon {
    /// Deterministic identicon from a seed string: a horizontally-symmetric grid
    /// of on/off cells plus a hue, so each session/project gets a stable pixel avatar.
    public static func make(seed: String, size: Int = 5) -> IdenticonGrid {
        var hash: UInt64 = 1469598103934665603 // FNV-1a offset basis
        for b in seed.utf8 { hash ^= UInt64(b); hash = hash &* 1099511628211 }
        let hue = Double(hash % 360) / 360.0
        let half = (size + 1) / 2
        var cells = Array(repeating: Array(repeating: false, count: size), count: size)
        var h = hash
        for r in 0..<size {
            for c in 0..<half {
                h ^= (h << 13); h ^= (h >> 7); h ^= (h << 17) // xorshift
                let on = (h & 1) == 1
                cells[r][c] = on
                cells[r][size - 1 - c] = on // mirror for symmetry
            }
        }
        return IdenticonGrid(cells: cells, hue: hue)
    }
}
