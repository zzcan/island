import Testing
import Foundation
@testable import IslandCore

@Suite struct TerminalDetectTests {
    @Test func detectsITerm2BySessionIdGUID() {
        let env = ["TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "w0t2p0:ABC-123-GUID"]
        let t = TerminalDetect.detect(env: env, cwd: "/x/proj", sessionId: "s1", tty: "/dev/ttys003")
        #expect(t?.kind == .iterm)
        #expect(t?.itermSessionId == "ABC-123-GUID")   // part after the colon
        #expect(t?.tty == nil)
    }

    @Test func detectsAppleTerminalByTTY() {
        let env = ["TERM_PROGRAM": "Apple_Terminal", "TERM_SESSION_ID": "w0t0p0:UUID"]
        let t = TerminalDetect.detect(env: env, cwd: "/x/proj", sessionId: "s1", tty: "/dev/ttys004")
        #expect(t?.kind == .appleTerminal)
        #expect(t?.tty == "/dev/ttys004")
    }

    @Test func detectsGhosttyAndBuildsTitle() {
        let env = ["TERM_PROGRAM": "ghostty"]
        let t = TerminalDetect.detect(env: env, cwd: "/Users/me/island", sessionId: "abcdef123456", tty: nil)
        #expect(t?.kind == .ghostty)
        #expect(t?.ghosttyTitle == "island · vi:abcdef")   // basename + 6-char session prefix
    }

    @Test func detectsGhosttyByTermVar() {
        let env = ["TERM": "xterm-ghostty"]
        let t = TerminalDetect.detect(env: env, cwd: nil, sessionId: "s1", tty: nil)
        #expect(t?.kind == .ghostty)
    }

    @Test func returnsNilInsideTmux() {
        let env = ["TMUX": "/tmp/tmux-501/default,123,0", "ITERM_SESSION_ID": "w0t0p0:GUID"]
        #expect(TerminalDetect.detect(env: env, cwd: "/x", sessionId: "s1", tty: "/dev/ttys003") == nil)
    }

    @Test func returnsNilForUnknownTerminal() {
        #expect(TerminalDetect.detect(env: ["TERM_PROGRAM": "WezTerm"], cwd: "/x", sessionId: "s1", tty: nil) == nil)
        #expect(TerminalDetect.detect(env: [:], cwd: "/x", sessionId: "s1", tty: nil) == nil)
    }
}
