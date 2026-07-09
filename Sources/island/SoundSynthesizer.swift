import AVFoundation
import AppKit
import IslandCore

/// Tiny chiptune-style synth: every event gets a short 8-bit blip sequence,
/// generated at runtime — no audio files shipped. This mirrors Vibe Island's
/// approach (a built-in *synthesized* sound pack, `builtin8bit`) rather than
/// bundling a per-event WAV for each state.
///
/// Each sound is rendered into a single PCM buffer on the main actor and handed to
/// an `AVAudioPlayerNode`, so nothing mutable is touched on the realtime audio
/// render thread.
@MainActor
final class SoundSynthesizer {
    /// Shared instance — used both for live event sounds (AppModel) and for the
    /// settings "试听" preview buttons, so they share one audio engine.
    static let shared = SoundSynthesizer()

    /// A preset sound = an ordered list of notes (frequency in Hz, duration in s).
    struct Sound {
        let notes: [(freq: Double, dur: Double)]
        let volume: Float
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    /// Master on/off — gated by Settings in AppModel; kept as a belt-and-braces flag.
    var enabled = true
    /// 0…1 user volume scale applied on top of each preset's amplitude.
    var masterVolume: Float = 1

    init() {
        ensurePlayerConnected(engine, player, format: format)
        registerRecoveryObservers()
    }

    /// Wire up the two recovery triggers that force the engine back through the lazy
    /// restart path in `ensureRunning()`.
    ///
    /// 1. `AVAudioEngineConfigurationChange` — posted on a *full* audio teardown
    ///    (system sleep/wake, output-device or route switch). It stops the engine and
    ///    tears down the player→mixer connection; we stop here so the next play()
    ///    rebuilds and restarts.
    ///
    /// 2. Screen/system **wake** (`NSWorkspace`) — a *display-only* sleep (息屏, no
    ///    system sleep) can idle or reset the output device *without* ever posting an
    ///    `AVAudioEngineConfigurationChange`, leaving the engine reporting
    ///    `isRunning == true` over dead audio IO — silent, with no error and no
    ///    notification to react to. So we also stop the engine on wake, which forces
    ///    the same lazy restart even when no config-change arrives. Stopping an already
    ///    healthy engine is harmless: the next play() simply restarts it (one blip of
    ///    startup latency), and sounds here are infrequent events.
    private func registerRecoveryObservers() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            NSLog("island: audio config change — stopping engine for lazy restart")
            Task { @MainActor in self?.engine.stop() }
        }

        // NSWorkspace wake notifications are posted on its *own* center, not the default
        // one, and are delivered on the main thread.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            ws.addObserver(forName: name, object: nil, queue: nil) { [weak self] note in
                NSLog("island: \(note.name.rawValue) — stopping audio engine for lazy restart")
                Task { @MainActor in self?.engine.stop() }
            }
        }
    }

    /// Start the engine on demand. Keyed on `engine.isRunning` rather than a one-shot
    /// flag, so it lazily starts on first use *and* recovers after the engine was
    /// stopped by an audio-config change.
    ///
    /// An `AVAudioEngineConfigurationChange` also *tears down* the player→mixer
    /// connection, not just the running state — so we must re-establish the graph
    /// (`ensurePlayerConnected`) before restarting, otherwise `scheduleBuffer` feeds a
    /// disconnected node and every later play is silent (with no error to log).
    private func ensureRunning() {
        let wasDisconnected = engine.outputConnectionPoints(for: player, outputBus: 0).isEmpty
        ensurePlayerConnected(engine, player, format: format)
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            player.play()
            NSLog("island: audio engine (re)started (reconnected=\(wasDisconnected))")
        } catch {
            NSLog("island: audio engine start failed: \(error)")
        }
    }

    func play(_ sound: Sound) {
        guard enabled else { return }
        ensureRunning()
        guard engine.isRunning, let buffer = render(sound) else { return }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    /// Audition a sound from Settings regardless of the per-event toggles, at the
    /// current master volume.
    func preview(_ sound: Sound) {
        masterVolume = Float(Settings.shared.soundVolume)
        ensureRunning()
        guard engine.isRunning, let buffer = render(sound) else { return }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    /// Play the sound that matches a session's new status (nil → silent).
    func play(for status: SessionStatus) {
        switch status {
        case .needsInput: play(.needsInput)
        case .done:       play(.done)
        case .working, .idle: break
        }
    }

    /// Synthesize the note sequence into one PCM buffer: 50%-duty square waves
    /// (the 8-bit timbre) laid end to end, each with a short linear-decay envelope
    /// so notes read as percussive blips and never click at the seam.
    private func render(_ sound: Sound) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let total = sound.notes.reduce(0) { $0 + Int($1.dur * sr) }
        guard total > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(total)
        let out = buffer.floatChannelData![0]

        var i = 0
        for note in sound.notes {
            let n = Int(note.dur * sr)
            guard n > 0 else { continue }
            let inc = 2.0 * Double.pi * note.freq / sr
            // Envelope shaped to match Vibe Island's measured one: a short attack
            // (de-click), a flat sustain (~first third), then an exponential ring-out
            // that lands on exactly 0 at the note's end (no seam click).
            let attack = min(Int(0.008 * sr), n / 6)
            let sustainEnd = max(attack + 1, Int(Double(n) * 0.35))
            let decayLen = Float(max(1, n - sustainEnd))
            let floorE = expf(-3.5)
            var phase = 0.0
            for k in 0..<n {
                let square: Float = sin(phase) >= 0 ? 1 : -1
                let env: Float
                if k < attack {
                    env = Float(k) / Float(attack)
                } else if k < sustainEnd {
                    env = 1
                } else {
                    let t = Float(k - sustainEnd) / decayLen
                    env = max(0, (expf(-3.5 * t) - floorE) / (1 - floorE))
                }
                out[i] = square * sound.volume * env * masterVolume
                phase += inc
                if phase > 2 * .pi { phase -= 2 * .pi }
                i += 1
            }
        }
        return buffer
    }
}

extension SoundSynthesizer.Sound {
    /// Attention — matches Vibe Island's needs-input ping: a rising F-major figure
    /// C5 F5 F5 A5, short and punchy (no long ring-out).
    static let needsInput = SoundSynthesizer.Sound(
        notes: [(523.25, 0.10), (698.46, 0.11), (698.46, 0.10), (880.00, 0.22)],
        volume: 0.16
    )

    /// Completion — matches Vibe Island's task-complete jingle (measured from a
    /// recording): C5 E5 G5 E5 G5 then a long octave-up C6 ring-out. ~1.3s.
    static let done = SoundSynthesizer.Sound(
        notes: [(523.25, 0.08), (659.25, 0.08), (783.99, 0.14),
                (659.25, 0.09), (783.99, 0.08), (1046.50, 0.84)],
        volume: 0.16
    )

    /// Session start — matches Vibe Island's start chime: a short ascending C-major
    /// arpeggio C5 E5 G5 that settles on G5 (no octave jump).
    static let sessionStart = SoundSynthesizer.Sound(
        notes: [(523.25, 0.10), (659.25, 0.10), (783.99, 0.30)],
        volume: 0.15
    )
}
