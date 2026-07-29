import AVFoundation
import CoreAudio

/// The output device the engine's underlying output unit (AUHAL) is currently
/// bound to, or nil when the engine has never been initialized (no binding yet).
@MainActor
public func engineOutputDevice(_ engine: AVAudioEngine) -> AudioDeviceID? {
    guard let au = engine.outputNode.audioUnit else { return nil }
    var dev = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let err = AudioUnitGetProperty(
        au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev, &size)
    guard err == noErr, dev != kAudioObjectUnknown else { return nil }
    return dev
}

/// The system's current default output device, or nil if none.
public func systemDefaultOutputDevice() -> AudioDeviceID? {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var dev = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let err = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
    guard err == noErr, dev != kAudioObjectUnknown else { return nil }
    return dev
}

/// Whether a device object still exists in the HAL. A device unpublished during
/// sleep answers with kAudioHardwareBadObjectError, not `alive == 0`.
public func audioDeviceIsAlive(_ dev: AudioDeviceID) -> Bool {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsAlive,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var alive: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &alive) == noErr && alive == 1
}

/// Owns an AVAudioEngine + AVAudioPlayerNode pair and recovers from the failure
/// mode that survived two rounds of in-place fixes: after a long display-only
/// sleep (息屏) the output unit can stay bound to a *dead* AudioDeviceID — the
/// device object was unpublished while the screen was off, sometimes without any
/// `AVAudioEngineConfigurationChange`. In that state every layer reports healthy
/// (`isRunning == true`, graph initialized, render clock advancing) while samples
/// go to a device that no longer exists, and `engine.stop()` + `engine.start()`
/// *reuses* the dead binding. The only reliable recovery is a fresh engine, which
/// rebinds to the current default output — so every recovery here is a rebuild.
@MainActor
public final class RecoverableAudioEngine {
    public private(set) var engine: AVAudioEngine
    public private(set) var player: AVAudioPlayerNode
    public let format: AVAudioFormat

    /// Times the config-change observer fired for the *current* engine; the
    /// rebuild-must-move-the-observer regression test reads this.
    internal private(set) var configChangeCount = 0

    private var configObserver: (any NSObjectProtocol)?
    private let log: @MainActor (String) -> Void

    public init(format: AVAudioFormat, log: @escaping @MainActor (String) -> Void = { _ in }) {
        self.format = format
        self.log = log
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        ensurePlayerConnected(engine, player, format: format)
        observeConfigChange()
    }

    /// Recovery trigger for events the engine can't observe itself (NSWorkspace
    /// wake notifications). Stopping poisons the engine; the next ensureRunning()
    /// rebuilds. Stopping a healthy engine is harmless — sounds are infrequent,
    /// so the one-blip restart latency doesn't matter.
    public func stopForRecovery() {
        engine.stop()
    }

    /// True only when the engine is running AND its output unit is bound to the
    /// system's current default output device AND that device is still alive.
    /// Catches the dead-binding state, which no AVAudioEngine-level API reports.
    internal func isHealthy() -> Bool {
        guard engine.isRunning, let dev = engineOutputDevice(engine) else { return false }
        return audioDeviceIsAlive(dev) && dev == systemDefaultOutputDevice()
    }

    /// Ensure a healthy running engine before a play. Anything short of fully
    /// healthy — stopped by a recovery trigger, never started, or silently bound
    /// to a dead/stale device — takes the rebuild path; never restart in place.
    /// Returns false when the engine can't start (e.g. no output hardware).
    public func ensureRunning() -> Bool {
        if isHealthy() {
            ensurePlayerConnected(engine, player, format: format)
            return true
        }
        rebuild()
        do {
            try engine.start()
            player.play()
            let dev = engineOutputDevice(engine).map(String.init) ?? "none"
            log("audio engine rebuilt + started (device=\(dev))")
            return true
        } catch {
            log("audio engine start failed: \(error)")
            return false
        }
    }

    internal func rebuild() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        engine.stop()
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        configChangeCount = 0
        ensurePlayerConnected(engine, player, format: format)
        observeConfigChange()
    }

    /// `AVAudioEngineConfigurationChange` is filtered by `object:`, so this must
    /// be re-registered against every new engine instance.
    private func observeConfigChange() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.configChangeCount += 1
                self.log("audio config change — engine will rebuild on next play")
                self.engine.stop()
            }
        }
    }
}
