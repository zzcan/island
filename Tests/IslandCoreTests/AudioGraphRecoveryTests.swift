import Testing
import AVFoundation
@testable import IslandCore

/// The live bug: an `AVAudioEngineConfigurationChange` (sleep/wake, output-device
/// or route switch) tears down the player→mixer connection. The old recovery path
/// only restarted the engine, so `scheduleBuffer` fed a disconnected node → silence
/// until the process was restarted. These tests pin the reconnection logic that fixes
/// it, exercised against a real `AVAudioEngine` (topology management needs no audio
/// hardware, so it runs headless).
@Suite struct AudioGraphRecoveryTests {
    private func makeGraph() -> (AVAudioEngine, AVAudioPlayerNode, AVAudioFormat) {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        return (engine, player, format)
    }

    @Test @MainActor func reconnectsPlayerAfterConfigChangeTearsDownConnection() {
        let (engine, player, format) = makeGraph()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        // Simulate what AVAudioEngineConfigurationChange does to the graph: the
        // player's output connection is torn down.
        engine.disconnectNodeOutput(player)
        #expect(engine.outputConnectionPoints(for: player, outputBus: 0).isEmpty)

        ensurePlayerConnected(engine, player, format: format)
        #expect(!engine.outputConnectionPoints(for: player, outputBus: 0).isEmpty)
    }

    @Test @MainActor func attachesAndConnectsAFreshPlayer() {
        // A never-attached node (fresh process, or after a full teardown) must be
        // brought all the way into the graph.
        let (engine, player, format) = makeGraph()

        ensurePlayerConnected(engine, player, format: format)

        #expect(engine.attachedNodes.contains(player))
        #expect(!engine.outputConnectionPoints(for: player, outputBus: 0).isEmpty)
    }

    @Test @MainActor func isIdempotentWhenAlreadyConnected() {
        // Calling it on every play() must be a cheap no-op when the graph is intact
        // (i.e. it must not stack duplicate connections or throw).
        let (engine, player, format) = makeGraph()
        ensurePlayerConnected(engine, player, format: format)
        ensurePlayerConnected(engine, player, format: format)

        #expect(engine.outputConnectionPoints(for: player, outputBus: 0).count == 1)
    }
}
