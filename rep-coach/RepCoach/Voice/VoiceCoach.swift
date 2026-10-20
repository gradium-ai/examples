import AVFoundation
import CryptoKit
import Foundation
import Observation
import os
import PhononTTS
import RepCoachCore

/// The coach's voice: Phonon on the Neural Engine, entirely on the phone.
///
/// Everything said mid-set (the counts and the encouragement) is synthesized once, ahead of
/// time, and kept on disk and in memory, so a count plays the instant a rep lands rather than
/// after synthesis. Only set and session summaries, spoken while resting, are synthesized live.
/// Until Phonon is ready, the system voice stands in so a count is never silent.
@MainActor
@Observable
final class VoiceCoach {
    enum Status: Equatable {
        case idle
        case installing
        case compiling
        case loading
        case preparing(done: Int, of: Int)
        case ready
        case failed(String)

        var label: String {
            switch self {
            case .idle: "Voice not loaded"
            case .installing: "Installing voice…"
            case .compiling: "Preparing voice for this iPhone (first launch only)…"
            case .loading: "Loading voice…"
            case let .preparing(done, of): "Preparing phrases \(done)/\(of)…"
            case .ready: "Voice ready"
            case let .failed(message): "Voice unavailable: \(message)"
            }
        }
    }

    private(set) var status: Status = .idle
    private(set) var voices: [String] = []
    private(set) var voice: String?
    /// Measured synthesis speed on this phone, seconds of audio per second of work.
    private(set) var realtimeFactor: Double?

    private var tts: Phonon?
    /// Identifies the model export the cached clips were made with.
    private var stamp = ""
    private var clips: [String: AVAudioPCMBuffer] = [:]
    private let output = AudioOutput()
    private var speaking: Task<Void, Never>?
    private let fallback = AVSpeechSynthesizer()
    private let log = Logger(subsystem: "sh.gradium.repcoach", category: "voice")

    /// The counts and phrases are English, so the coach speaks with an English voice. Phonon 31M
    /// names its voices just `<Name>`; a multilingual model also carries French, German, Spanish
    /// and Portuguese voices, named `<lang>_<region>_<Name>`.
    static func isEnglish(_ voice: String) -> Bool {
        voice.hasPrefix("en_") || (!voice.contains("_") && voice != "default")
    }

    /// The voice to use: the saved choice if this model has it (a bare name, like `Freya`, and
    /// the multilingual `en_gb_Freya` match each other), otherwise Harper, otherwise the first
    /// English voice. Never the alphabetically first voice, which may not be English.
    static func pick(_ saved: String?, from voices: [String]) -> String? {
        let english = voices.filter(isEnglish)
        if let saved, !saved.isEmpty {
            if english.contains(saved) { return saved }
            if let match = english.first(where: { $0.hasSuffix("_" + saved) }) { return match }
            if let bare = saved.split(separator: "_").last, english.contains(String(bare)) { return String(bare) }
        }
        return english.first(where: { $0.hasSuffix("_Harper") || $0 == "Harper" }) ?? english.first ?? voices.first
    }

    /// Loads Phonon and prepares every fixed phrase in `voiceName` (or the default voice).
    func prepare(voiceName: String?) async {
        guard status == .idle || { if case .failed = status { true } else { false } }() else { return }
        do {
            guard let bundled = Bundle.main.url(forResource: "Models", withExtension: nil),
                  FileManager.default.fileExists(atPath: bundled.appending(path: "bundle.json").path)
            else {
                throw PhononError(description: "this build has no voice model, using the system voice")
            }
            status = .installing
            let models = try await Task.detached { try PhononModels.install(bundled: bundled) }.value
            status = Phonon.needsCompiling(models) ? .compiling : .loading
            let started = Date()
            let tts = try await Phonon.load(models: models, language: .english)
            log.info("phonon loaded in \(Date().timeIntervalSince(started), format: .fixed(precision: 1)) s")
            self.tts = tts
            voices = tts.voices.filter(Self.isEnglish)
            let chosen = Self.pick(voiceName, from: tts.voices) ?? tts.voice
            if chosen != tts.voice { try await tts.setVoice(chosen) }
            voice = chosen
            stamp = Self.stamp(models)
            try await precompute()
            status = .ready
        } catch {
            log.error("voice: \(String(describing: error))")
            status = .failed(String(describing: error))
        }
    }

    func setVoice(_ name: String) async {
        guard let tts, name != voice, status == .ready else { return }
        do {
            try await tts.setVoice(name)
            voice = name
            clips = [:]
            try await precompute()
            status = .ready
        } catch {
            status = .failed(String(describing: error))
        }
    }

    /// Says `lines` in order, cutting off whatever is being said: a new count must never wait
    /// behind stale encouragement.
    func say(_ lines: [Utterance]) {
        guard !lines.isEmpty else { return }
        interrupt()
        let clips = lines.map { self.clips[$0.text] }
        // Phonon speaks one utterance at a time, so while it is still loading or preparing the
        // phrases, live synthesis would queue behind that work and arrive seconds late. The
        // system voice stands in until it is ready.
        let tts = status == .ready ? self.tts : nil
        if tts == nil && clips.contains(where: { $0 == nil }) {
            for line in lines { fallback.speak(AVSpeechUtterance(string: line.text)) }
            return
        }
        let output = self.output
        let generation = output.begin()
        speaking = Task.detached {
            for (line, clip) in zip(lines, clips) {
                if let clip {
                    output.schedule(clip, generation: generation)
                } else if let tts {
                    do {
                        for try await chunk in tts.stream(line.text) {
                            guard output.enqueue(chunk, generation: generation) else { return }
                        }
                    } catch {
                        return
                    }
                }
            }
        }
    }

    func say(_ line: Utterance) { say([line]) }

    func interrupt() {
        speaking?.cancel()
        speaking = nil
        output.stop()
        if fallback.isSpeaking { fallback.stopSpeaking(at: .immediate) }
    }

    // MARK: - Precomputed phrases

    private func precompute() async throws {
        guard let tts, let voice else { return }
        let phrases = PhraseBook.precomputed
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "phrases/\(voice)-\(stamp)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var audioSeconds = 0.0, workSeconds = 0.0
        for (i, text) in phrases.enumerated() {
            status = .preparing(done: i, of: phrases.count)
            let file = dir.appending(path: Self.fileName(text))
            var samples: [Float]
            if let cached = Self.readSamples(file) {
                samples = cached
            } else {
                let collected = Collector()
                let stats = try await tts.speak(text) { collected.append($0) }
                samples = collected.samples
                audioSeconds += stats.audioSeconds
                workSeconds += stats.realtimeFactor > 0 ? stats.audioSeconds / stats.realtimeFactor : 0
                // Atomic, so a crash mid-write cannot leave a truncated clip that plays as noise.
                try samples.withUnsafeBytes { try Data($0).write(to: file, options: .atomic) }
            }
            clips[text] = AudioOutput.buffer(Self.trimSilence(samples))
        }
        if workSeconds > 0 {
            realtimeFactor = audioSeconds / workSeconds
            log.info("precomputed \(phrases.count) phrases at \(self.realtimeFactor ?? 0, format: .fixed(precision: 1))x realtime")
        }
    }

    /// A cached clip, or nil if it is missing or not a whole number of samples.
    private static func readSamples(_ file: URL) -> [Float]? {
        guard let data = try? Data(contentsOf: file), !data.isEmpty,
              data.count % MemoryLayout<Float>.size == 0
        else { return nil }
        return [Float](unsafeUninitializedCapacity: data.count / MemoryLayout<Float>.size) { buffer, count in
            count = data.copyBytes(to: buffer) / MemoryLayout<Float>.size
        }
    }

    /// Cached clips are keyed by the model export, so a new model never plays an old voice.
    private static func stamp(_ models: URL) -> String {
        let data = (try? Data(contentsOf: models.appending(path: "bundle.json"))) ?? Data()
        return SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private static func fileName(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined() + ".f32"
    }

    /// Drops leading and trailing near-silence, so a count starts at once and the next can
    /// follow straight after.
    private static func trimSilence(_ samples: [Float], threshold: Float = 0.01) -> [Float] {
        guard let first = samples.firstIndex(where: { abs($0) > threshold }),
              let last = samples.lastIndex(where: { abs($0) > threshold })
        else { return samples }
        let pad = Int(Phonon.sampleRate * 0.03)
        return Array(samples[max(0, first - pad)...min(samples.count - 1, last + pad)])
    }
}

private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [Float] = []
    var samples: [Float] { lock.withLock { buffer } }
    func append(_ chunk: [Float]) { lock.withLock { buffer += chunk } }
}

/// One audio engine for the whole app, playing Phonon's 24 kHz mono audio. It restarts itself
/// when the route changes (AirPods connecting or dropping), which otherwise stops the engine
/// silently.
final class AudioOutput: @unchecked Sendable {
    static let format = AVAudioFormat(standardFormatWithSampleRate: Phonon.sampleRate, channels: 1)!

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let log = Logger(subsystem: "sh.gradium.repcoach", category: "audio")
    /// Guards `generation` and the engine. Each utterance gets a generation; a buffer from an
    /// older one is dropped, so audio from an interrupted utterance can never be queued after
    /// the stop that cut it off.
    private let lock = NSLock()
    private var generation = 0

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            log.error("audio session: \(error.localizedDescription)")
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: Self.format)
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            guard let self else { return }
            log.info("audio route changed, restarting engine")
            lock.withLock { self.ensureRunning() }
        }
        lock.withLock { ensureRunning() }
    }

    static func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    /// Drops everything queued and starts a new utterance, returning its generation.
    func begin() -> Int {
        lock.withLock {
            generation += 1
            node.stop()
            ensureRunning()
            return generation
        }
    }

    /// Drops everything queued.
    func stop() {
        _ = begin()
    }

    /// Queues `buffer` if its utterance is still the current one. Returns false once it is not.
    @discardableResult
    func schedule(_ buffer: AVAudioPCMBuffer, generation: Int) -> Bool {
        lock.withLock {
            guard generation == self.generation else { return false }
            ensureRunning()
            node.scheduleBuffer(buffer)
            return true
        }
    }

    @discardableResult
    func enqueue(_ samples: [Float], generation: Int) -> Bool {
        guard let buffer = Self.buffer(samples) else { return true }
        return schedule(buffer, generation: generation)
    }

    /// Call with `lock` held.
    private func ensureRunning() {
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                log.error("audio engine: \(error.localizedDescription)")
                return
            }
        }
        if !node.isPlaying { node.play() }
    }
}
