import Testing
import AVFoundation
@testable import IslandCore

/// The live bug (round 3): after a long display-only sleep the engine's output
/// unit stayed bound to a *dead* AudioDeviceID (the device object was unpublished
/// while the screen was off). `engine.stop()` + `engine.start()` — the previous
/// recovery — reuses that dead binding: every layer reports healthy
/// (`isRunning == true`, graph initialized, render clock advancing) while samples
/// go to a device that no longer exists. Only a *fresh* `AVAudioEngine` rebinds to
/// the current default output. These tests pin the rebuild-based recovery.
///
/// Tests avoid `engine.start()` assertions unless the host actually has an output
/// device (they bail out quietly when hardware start fails, so they stay
/// headless-tolerant like AudioGraphRecoveryTests).
@Suite struct RecoverableAudioEngineTests {
    @MainActor private static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    @Test @MainActor func initBuildsConnectedGraph() {
        let audio = RecoverableAudioEngine(format: Self.format)
        #expect(audio.engine.attachedNodes.contains(audio.player))
        #expect(!audio.engine.outputConnectionPoints(for: audio.player, outputBus: 0).isEmpty)
    }

    @Test @MainActor func rebuildSwapsEngineAndPlayerAndReconnects() {
        let audio = RecoverableAudioEngine(format: Self.format)
        let oldEngine = audio.engine
        let oldPlayer = audio.player

        audio.rebuild()

        #expect(audio.engine !== oldEngine)
        #expect(audio.player !== oldPlayer)
        #expect(audio.engine.attachedNodes.contains(audio.player))
        #expect(!audio.engine.outputConnectionPoints(for: audio.player, outputBus: 0).isEmpty)
    }

    /// The core regression: after a recovery trigger (wake notification), the next
    /// ensureRunning() must NOT reuse the old engine instance — stop()+start() is
    /// exactly the path that kept the dead device binding alive.
    @Test @MainActor func ensureRunningAfterRecoveryTriggerRebuildsTheEngine() {
        let audio = RecoverableAudioEngine(format: Self.format)
        let oldEngine = audio.engine

        audio.stopForRecovery()
        _ = audio.ensureRunning()

        #expect(audio.engine !== oldEngine)
    }

    /// A freshly built, never-started engine has no live output-device binding, so
    /// it must report unhealthy (→ ensureRunning takes the rebuild+start path).
    @Test @MainActor func unstartedEngineIsNotHealthy() {
        let audio = RecoverableAudioEngine(format: Self.format)
        #expect(!audio.isHealthy())
    }

    /// With real output hardware: after ensureRunning() the engine must be running,
    /// bound to the *current system default* output device, and that device must be
    /// alive — i.e. exactly the invariant the dead-device bug violated.
    @Test @MainActor func ensureRunningBindsCurrentDefaultOutputDevice() {
        let audio = RecoverableAudioEngine(format: Self.format)
        guard audio.ensureRunning() else { return } // headless host: nothing to pin
        defer { audio.engine.stop() }

        #expect(audio.engine.isRunning)
        #expect(audio.isHealthy())
        let bound = engineOutputDevice(audio.engine)
        #expect(bound != nil)
        #expect(bound == systemDefaultOutputDevice())
        if let bound { #expect(audioDeviceIsAlive(bound)) }
    }

    /// Rebuilding must move the AVAudioEngineConfigurationChange observer to the
    /// new engine instance — the notification is filtered by `object:`, so a stale
    /// registration would silently stop reacting to config changes after the first
    /// rebuild.
    @Test @MainActor func configChangeObserverFollowsTheRebuiltEngine() async {
        let audio = RecoverableAudioEngine(format: Self.format)
        let oldEngine = audio.engine
        audio.rebuild()

        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: oldEngine)
        for _ in 0..<10 { await Task.yield() }
        #expect(audio.configChangeCount == 0, "old engine's notifications must be ignored")

        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: audio.engine)
        for _ in 0..<10 { await Task.yield() }
        #expect(audio.configChangeCount == 1)
    }
}
