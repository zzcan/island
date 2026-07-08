import AVFoundation

/// Ensure `player` is attached to `engine` and its output is connected to the main
/// mixer with `format`, restoring the graph if a configuration change tore it down.
///
/// `AVAudioEngineConfigurationChange` (sleep/wake, output-device or route switch)
/// both stops the engine *and* removes the player→mixer connection. Recovery that
/// only restarts the engine leaves the player dangling, so scheduled buffers play
/// into nothing (silence, no error). Call this before every play so the topology is
/// rebuilt lazily; it is a no-op when the graph is already intact.
@MainActor
public func ensurePlayerConnected(
    _ engine: AVAudioEngine,
    _ player: AVAudioPlayerNode,
    format: AVAudioFormat
) {
    if !engine.attachedNodes.contains(player) {
        engine.attach(player)
    }
    if engine.outputConnectionPoints(for: player, outputBus: 0).isEmpty {
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }
}
