import CoreAudio
import Foundation
import os

/// Silences the default output device by fading its scalar volume.
/// Media keeps playing. The pre-duck volume and mute state are remembered.
final class OutputDucker {
    private let log = Logger(subsystem: "app.reily.autopause", category: "duck")
    private let queue = DispatchQueue(label: "app.reily.autopause.duck")
    private var fadeTimer: DispatchSourceTimer?
    private var deviceID: AudioDeviceID?
    private var savedVolumes: [UInt32: Float]?
    private var lastWritten: [UInt32: Float] = [:]
    private var listenedElements: [UInt32] = []
    private var ducking = false
    private var leftAloneBecauseMuted = false
    private var userTookOver = false
    private var usedMuteFallback = false
    private var systemListenerInstalled = false
    private var suppressListenerUntil = Date.distantPast
    private var fadeDuration: TimeInterval = 0.3
    /// Pre-duck levels while a restore fade is still running. A new duck during
    /// that fade must remember these, not the half-restored volume.
    private var volumeToRestore: [UInt32: Float]?
    private let volumeEpsilon: Float = 0.03
    /// Larger than one fade step, smaller than a deliberate slider jump.
    private let userJump: Float = 0.12

    private lazy var listenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        // Never hop synchronously: the HAL can deliver this inline on `queue`.
        self?.queue.async {
            self?.handleListener()
        }
    }

    var isDucking: Bool {
        queue.sync { ducking }
    }

    func duck(fade duration: TimeInterval) {
        queue.async {
            self.fadeDuration = duration
            self.beginDuck(fade: duration)
        }
    }

    func restore(fade duration: TimeInterval) {
        queue.async {
            self.restoreLocked(fade: duration)
        }
    }

    /// Used from `applicationWillTerminate`. Restores immediately so the process
    /// cannot exit while the output is still faded.
    func restoreImmediately() {
        queue.sync {
            self.restoreLocked(fade: 0)
        }
    }

    private func beginDuck(fade duration: TimeInterval) {
        guard !ducking else { return }
        let remembered = volumeToRestore
        cancelFade()
        volumeToRestore = nil
        installSystemListener()
        guard let device = defaultOutputDevice() else {
            log.error("no default output device")
            return
        }
        ducking = true
        userTookOver = false
        leftAloneBecauseMuted = false
        usedMuteFallback = false
        deviceID = device
        let elements = volumeElements(device)
        installVolumeListeners(device: device, elements: elements)

        if isMuted(device) {
            // Already silent. Leave the user's mute alone, including on restore.
            leftAloneBecauseMuted = true
            savedVolumes = nil
            return
        }

        let current = readVolumes(device, elements: elements)
        if current.isEmpty {
            if setMuted(true, device: device) {
                usedMuteFallback = true
            } else {
                log.error("output device has no settable volume or mute")
                ducking = false
                removeVolumeListeners()
            }
            return
        }

        savedVolumes = remembered ?? current
        let target = Dictionary(uniqueKeysWithValues: current.keys.map { ($0, Float(0)) })
        fade(from: current, to: target, duration: duration, device: device)
    }

    private func restoreLocked(fade duration: TimeInterval) {
        guard ducking else { return }
        cancelFade()
        let device = deviceID
        let saved = savedVolumes
        let tookOver = userTookOver
        let leftAlone = leftAloneBecauseMuted
        let muteFallback = usedMuteFallback
        ducking = false
        savedVolumes = nil
        lastWritten = [:]
        leftAloneBecauseMuted = false
        userTookOver = false
        usedMuteFallback = false
        removeVolumeListeners()

        guard let device else { return }
        if leftAlone || tookOver {
            return
        }
        if muteFallback {
            setMuted(false, device: device)
            return
        }
        guard let saved else { return }
        let from = readVolumes(device, elements: Array(saved.keys))
        let start = from.isEmpty ? Dictionary(uniqueKeysWithValues: saved.keys.map { ($0, Float(0)) }) : from
        fade(from: start, to: saved, duration: duration, device: device, restoringTo: saved)
    }

    private func handleListener() {
        guard let output = defaultOutputDevice() else { return }
        if ducking, output != deviceID {
            let previous = deviceID
            let saved = savedVolumes
            let shouldRestorePrevious = ducking && !userTookOver && !leftAloneBecauseMuted && !usedMuteFallback
            cancelFade()
            if shouldRestorePrevious, let previous, let saved {
                writeVolumes(saved, device: previous)
            }
            // Follow the new default device. `beginDuck` no-ops while `ducking`
            // is set, so clear it first. The previous device was just restored.
            ducking = false
            savedVolumes = nil
            userTookOver = false
            leftAloneBecauseMuted = false
            usedMuteFallback = false
            removeVolumeListeners()
            beginDuck(fade: fadeDuration)
            return
        }

        guard ducking, !leftAloneBecauseMuted, !userTookOver, !usedMuteFallback, let deviceID else {
            return
        }
        let volumes = readVolumes(deviceID, elements: listenedElements)
        if Date() < suppressListenerUntil && !isUserJump(volumes) {
            return
        }
        if isMuted(deviceID) {
            // User muted while we were ducked. Their mute sticks.
            userTookOver = true
            cancelFade()
            return
        }
        let changedBySomeoneElse = volumes.contains { element, value in
            guard let written = lastWritten[element] else { return false }
            return abs(value - written) > volumeEpsilon
        }
        if changedBySomeoneElse {
            // Adopt the user's level and stop forcing ours, including on restore.
            userTookOver = true
            savedVolumes = volumes
            cancelFade()
        }
    }

    private func fade(
        from: [UInt32: Float],
        to: [UInt32: Float],
        duration: TimeInterval,
        device: AudioDeviceID,
        restoringTo: [UInt32: Float]? = nil
    ) {
        cancelFade()
        if duration <= 0 {
            volumeToRestore = nil
            writeVolumes(to, device: device)
            return
        }
        volumeToRestore = restoringTo
        let started = Date().timeIntervalSinceReferenceDate
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let elapsed = Date().timeIntervalSinceReferenceDate - started
            let t = min(1, Float(elapsed / duration))
            var frame: [UInt32: Float] = [:]
            for (element, start) in from {
                let end = to[element] ?? start
                frame[element] = start + (end - start) * t
            }
            self.writeVolumes(frame, device: device)
            if t >= 1 {
                self.volumeToRestore = nil
                self.cancelFade()
            }
        }
        fadeTimer = timer
        timer.resume()
    }

    private func cancelFade() {
        fadeTimer?.setEventHandler {}
        fadeTimer?.cancel()
        fadeTimer = nil
    }

    private func isUserJump(_ current: [UInt32: Float]) -> Bool {
        current.contains { element, value in
            guard let written = lastWritten[element] else { return false }
            return abs(value - written) > userJump
        }
    }

    private func writeVolumes(_ values: [UInt32: Float], device: AudioDeviceID) {
        lastWritten = values
        suppressListenerUntil = Date().addingTimeInterval(0.05)
        for (element, value) in values {
            let clamped = min(1, max(0, value))
            CoreAudioProperty.writeFloat(
                clamped,
                device,
                kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            )
        }
    }

    private func readVolumes(_ device: AudioDeviceID, elements: [UInt32]) -> [UInt32: Float] {
        var values: [UInt32: Float] = [:]
        for element in elements {
            if let value = CoreAudioProperty.readFloat(
                device,
                kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            ) {
                values[element] = value
            }
        }
        return values
    }

    /// Prefer the main element when the device has one settable control.
    /// Otherwise fade each output channel on its own.
    private func volumeElements(_ device: AudioDeviceID) -> [UInt32] {
        if CoreAudioProperty.isSettable(
            device,
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) {
            return [kAudioObjectPropertyElementMain]
        }
        let count = outputChannelCount(device)
        guard count > 0 else { return [] }
        return (1...count).compactMap { index -> UInt32? in
            let element = UInt32(index)
            guard CoreAudioProperty.isSettable(
                device,
                kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            ) else {
                return nil
            }
            return element
        }
    }

    private func outputChannelCount(_ device: AudioDeviceID) -> Int {
        var address = CoreAudioProperty.address(
            kAudioDevicePropertyStreamConfiguration,
            scope: kAudioObjectPropertyScopeOutput
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else {
            return 0
        }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func isMuted(_ device: AudioDeviceID) -> Bool {
        if CoreAudioProperty.isSettable(
            device,
            kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) || CoreAudioProperty.readUInt32(
            device,
            kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) != nil {
            return CoreAudioProperty.readUInt32(
                device,
                kAudioDevicePropertyMute,
                scope: kAudioObjectPropertyScopeOutput,
                element: kAudioObjectPropertyElementMain
            ) == 1
        }
        return false
    }

    @discardableResult
    private func setMuted(_ muted: Bool, device: AudioDeviceID) -> Bool {
        guard CoreAudioProperty.isSettable(
            device,
            kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) else {
            return false
        }
        return CoreAudioProperty.writeUInt32(
            muted ? 1 : 0,
            device,
            kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
    }

    private func defaultOutputDevice() -> AudioDeviceID? {
        let id = CoreAudioProperty.readUInt32(
            AudioObjectID(kAudioObjectSystemObject),
            kAudioHardwarePropertyDefaultOutputDevice
        ).map { AudioDeviceID($0) }
        guard let id, id != kAudioObjectUnknown else { return nil }
        return id
    }

    private func installSystemListener() {
        guard !systemListenerInstalled else { return }
        systemListenerInstalled = true
        var address = CoreAudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            listenerBlock
        )
    }

    private func installVolumeListeners(device: AudioDeviceID, elements: [UInt32]) {
        removeVolumeListeners()
        listenedElements = elements
        for element in elements {
            var address = CoreAudioProperty.address(
                kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            )
            AudioObjectAddPropertyListenerBlock(device, &address, queue, listenerBlock)
        }
        var mute = CoreAudioProperty.address(
            kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(device, &mute, queue, listenerBlock)
    }

    private func removeVolumeListeners() {
        guard let deviceID else {
            listenedElements = []
            return
        }
        for element in listenedElements {
            var address = CoreAudioProperty.address(
                kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, queue, listenerBlock)
        }
        var mute = CoreAudioProperty.address(
            kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(deviceID, &mute, queue, listenerBlock)
        listenedElements = []
    }
}
