import Testing
import Foundation
@testable import IslandCore

@Suite struct IdenticonTests {
    @Test func deterministic() {
        let a = Identicon.make(seed: "island")
        let b = Identicon.make(seed: "island")
        #expect(a == b)
    }

    @Test func differentSeedsDiffer() {
        let a = Identicon.make(seed: "a")
        let b = Identicon.make(seed: "b")
        #expect(a.cells != b.cells || a.hue != b.hue)
    }

    @Test func symmetric() {
        let grid = Identicon.make(seed: "symmetric-test")
        let size = grid.cells.count
        for r in 0..<size {
            for c in 0..<size {
                #expect(grid.cells[r][c] == grid.cells[r][size - 1 - c])
            }
        }
    }

    @Test func hueInRange() {
        let grid = Identicon.make(seed: "hue-check")
        #expect(grid.hue >= 0.0 && grid.hue < 1.0)
    }

    @Test func sizeMatchesDefault() {
        let grid = Identicon.make(seed: "size-check")
        #expect(grid.cells.count == 5)
        for row in grid.cells {
            #expect(row.count == 5)
        }
    }

    @Test func sizeMatchesCustom() {
        let grid = Identicon.make(seed: "size-check", size: 7)
        #expect(grid.cells.count == 7)
        for row in grid.cells {
            #expect(row.count == 7)
        }
    }
}
