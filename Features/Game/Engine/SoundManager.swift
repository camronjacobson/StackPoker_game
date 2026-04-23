import Foundation
import AVFoundation

// ─── Sound Manager ────────────────────────────────────────────────────────────
// Loads bundled audio samples (mp3) from the app's Sounds/ folder and plays
// them through a small pool of AVAudioPlayerNodes so multiple sfx can overlap.
// If a sample is missing or fails to load, falls back to procedural synthesis
// so the app never runs silent.

final class SoundManager {
    static let shared = SoundManager()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0

    private let sampleRate: Double = 44_100
    private lazy var format: AVAudioFormat = {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }()

    private var buffers: [GameSound: AVAudioPCMBuffer] = [:]

    // Win sound uses a pool of files (win1/win2/win3) that rotate each play
    // so back-to-back wins don't sound identical.
    private var winBuffers: [AVAudioPCMBuffer] = []
    private var nextWinIndex = 0

    // Settings keys (also read by the Settings UI via @AppStorage)
    static let enabledKey = "soundEnabled"
    static let volumeKey  = "soundVolume"

    private init() {
        setupSession()
        setupEngine()
        loadBuffers()
        _ = engine.mainMixerNode
        applyVolumeFromDefaults()
        do { try engine.start() }
        catch { print("[SoundManager] engine start failed: \(error)") }
    }

    // ─── Setup ────────────────────────────────────────────────────────────────

    private func setupSession() {
        let session = AVAudioSession.sharedInstance()
        // .playback so sfx play even when the ringer switch is muted.
        // .mixWithOthers lets background music keep playing underneath.
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func setupEngine() {
        // Pool of 8 player nodes so overlapping sfx (chip drop + timer tick
        // + card deal) don't cut each other off.
        for _ in 0..<8 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
    }

    // ─── Settings ─────────────────────────────────────────────────────────────

    private var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool) ?? true
    }

    private var volumeLevel: Float {
        let raw = UserDefaults.standard.object(forKey: Self.volumeKey) as? Double
        return Float(raw ?? 0.8)
    }

    /// Call this after the user toggles mute or drags the volume slider.
    func applyVolumeFromDefaults() {
        engine.mainMixerNode.outputVolume = isEnabled ? volumeLevel : 0
    }

    // ─── Public API ───────────────────────────────────────────────────────────

    /// Stops every player in the pool immediately. Use when leaving a game so
    /// lingering sounds (e.g. a scheduled timer tick) don't keep playing after
    /// the view is gone.
    func stopAll() {
        for p in players { p.stop() }
    }

    func play(_ sound: GameSound) {
        guard isEnabled else { return }
        let buffer: AVAudioPCMBuffer?
        if sound == .win, !winBuffers.isEmpty {
            buffer = winBuffers[nextWinIndex]
            nextWinIndex = (nextWinIndex + 1) % winBuffers.count
        } else {
            buffer = buffers[sound]
        }
        guard let buffer = buffer else { return }
        engine.mainMixerNode.outputVolume = volumeLevel
        if !engine.isRunning {
            do { try engine.start() }
            catch { print("[SoundManager] engine start failed: \(error)"); return }
        }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    // ─── Buffer loading ───────────────────────────────────────────────────────
    // Each event tries its bundled mp3 first; if missing (or fails to load),
    // falls back to the synthesized approximation from the previous build.

    private func loadBuffers() {
        buffers[.cardDeal] = loadSampleBuffer(named: "pulling_out_cards_newhand", gain: 0.95)
            ?? makeCardSlide(duration: 0.14, sweepStart: 5500, sweepEnd: 2300, thump: false, gain: 0.50)

        buffers[.fold] = loadSampleBuffer(named: "foldingsound", gain: 0.95)
            ?? makeCardSlide(duration: 0.30, sweepStart: 3500, sweepEnd: 700, thump: true, gain: 0.55)

        // No matching file for check — knuckle knock stays synthesized.
        buffers[.check] = makeFeltKnock(gain: 0.55)

        buffers[.call] = loadSampleBuffer(named: "placingpokerchips", gain: 0.95)
            ?? makeChipStack(chips: 1, spread: 0.0, gain: 0.60)

        buffers[.chipBet] = loadSampleBuffer(named: "placingpokerchips", gain: 0.95)
            ?? makeChipStack(chips: 3, spread: 0.04, gain: 0.58)

        buffers[.raise] = loadSampleBuffer(named: "placingpokerchips1", gain: 0.95)
            ?? makeChipStack(chips: 4, spread: 0.06, gain: 0.60)

        buffers[.allIn] = loadSampleBuffer(named: "soundforallin", gain: 1.0)
            ?? makeChipStack(chips: 9, spread: 0.14, gain: 0.65)

        // Win sound — rotate through win1/win2/win3 so consecutive wins
        // don't sound identical. Falls back to the synthesized chip cascade
        // if no files load.
        winBuffers = ["win1", "win2", "win3"].compactMap {
            loadSampleBuffer(named: $0, gain: 0.95)
        }
        if winBuffers.isEmpty,
           let fallback = makeChipCascade(duration: 0.75, hits: 26, gain: 0.60) {
            winBuffers = [fallback]
        }
        buffers[.win] = winBuffers.first

        // `timer.mp3` is a long ticking recording. We only want a single tick
        // per play (one per second in the last 5s), so clip the loaded buffer
        // to ~180ms. Without this, each call plays the full recording and
        // overlapping plays layer into a constant drone.
        buffers[.timerWarning] = loadSampleBuffer(named: "timer", gain: 0.6, trimmedTo: 0.18)
            ?? makeSoftTick(frequency: 760, duration: 0.05, gain: 0.28)
    }

    /// Load an mp3 from the app bundle, convert it to the engine's standard
    /// mono/44.1kHz format, and apply a gain so loudness matches other samples.
    /// Tries the top-level bundle first, then Sounds/ subdirectory (in case the
    /// Sounds folder is bundled as a folder reference, preserving hierarchy).
    private func loadSampleBuffer(named name: String, gain: Float, trimmedTo maxSeconds: Double? = nil) -> AVAudioPCMBuffer? {
        let url = Bundle.main.url(forResource: name, withExtension: "mp3")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Sounds")
        guard let url = url else {
            print("[SoundManager] missing sample: \(name).mp3")
            return nil
        }
        do {
            let file = try AVAudioFile(forReading: url)
            let srcFormat = file.processingFormat
            let srcFrames = AVAudioFrameCount(file.length)
            guard srcFrames > 0,
                  let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: srcFrames)
            else { return nil }
            try file.read(into: srcBuffer)

            // Convert to our engine's standard mono/44.1kHz format
            guard let converter = AVAudioConverter(from: srcFormat, to: format) else { return nil }
            let ratio = format.sampleRate / srcFormat.sampleRate
            let outCapacity = AVAudioFrameCount(Double(srcBuffer.frameLength) * ratio) + 1024
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outCapacity)
            else { return nil }

            var didSupply = false
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if didSupply {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                didSupply = true
                outStatus.pointee = .haveData
                return srcBuffer
            }
            var error: NSError?
            converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
            if let error = error {
                print("[SoundManager] convert error for \(name): \(error)")
                return nil
            }

            // Optional trim: clip the buffer to `maxSeconds` with a short
            // fade-out so the cut doesn't click. Used for long source files
            // (e.g. timer.mp3) that we only want a brief slice of.
            if let maxSeconds = maxSeconds {
                let maxFrames = AVAudioFrameCount(min(Double(outBuffer.frameLength) / format.sampleRate, maxSeconds) * format.sampleRate)
                if maxFrames < outBuffer.frameLength {
                    outBuffer.frameLength = maxFrames
                    if let data = outBuffer.floatChannelData {
                        let n = Int(maxFrames)
                        let fadeFrames = min(n, Int(format.sampleRate * 0.02)) // 20ms fade
                        for i in (n - fadeFrames)..<n {
                            let f = Float(n - i) / Float(fadeFrames)
                            data[0][i] *= f
                        }
                    }
                }
            }

            // Apply gain
            if let data = outBuffer.floatChannelData {
                let n = Int(outBuffer.frameLength)
                for i in 0..<n { data[0][i] *= gain }
            }
            return outBuffer
        } catch {
            print("[SoundManager] load error for \(name): \(error)")
            return nil
        }
    }

    // ─── Synthesis fallbacks ──────────────────────────────────────────────────
    // Used when a bundled sample is missing or fails to decode. These keep the
    // app audible during development and on any config that ships without the
    // Sounds folder.

    private func makeBuffer(duration: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return nil }
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) { data[i] = 0 }
        return buffer
    }

    private func makeCardSlide(duration: Double,
                               sweepStart: Float,
                               sweepEnd: Float,
                               thump: Bool,
                               gain: Float) -> AVAudioPCMBuffer? {
        guard let buffer = makeBuffer(duration: duration) else { return nil }
        let data = buffer.floatChannelData![0]
        let n = Int(buffer.frameLength)
        let dt = 1.0 / Float(sampleRate)
        var lp: Float = 0
        let thumpStart = thump ? Int(duration * 0.70 * sampleRate) : n
        for i in 0..<n {
            let pct      = Float(i) / Float(n)
            let cutoffHz = sweepStart + (sweepEnd - sweepStart) * pct
            let rc       = 1.0 / (2 * .pi * cutoffHz)
            let alpha    = rc / (rc + dt)
            let noise    = Float.random(in: -1...1)
            lp = alpha * lp + (1 - alpha) * noise
            let hp = noise - lp

            let attack = min(1, Float(i) / (Float(sampleRate) * 0.005))
            let fade   = 1 - pct * pct
            var sample = hp * attack * fade * gain

            if i >= thumpStart {
                let t  = Float(i - thumpStart) / Float(sampleRate)
                let f0: Float = 90
                let body     = sin(2 * .pi * f0 * t)
                let bodyEnv  = exp(-t * 28)
                let clickEnv = exp(-t * 350)
                let click    = Float.random(in: -1...1) * clickEnv * 0.35
                sample += (body * bodyEnv + click) * gain * 0.55
            }
            data[i] = sample
        }
        return buffer
    }

    private func makeFeltKnock(gain: Float) -> AVAudioPCMBuffer? {
        let duration = 0.13
        guard let buffer = makeBuffer(duration: duration) else { return nil }
        let data = buffer.floatChannelData![0]
        let n = Int(buffer.frameLength)
        for i in 0..<n {
            let t = Float(i) / Float(sampleRate)
            let pitch = 130 - 35 * min(1, t * 12)
            let body     = sin(2 * .pi * pitch * t)
            let bodyEnv  = exp(-t * 38)
            let clickEnv = exp(-t * 700)
            let click    = Float.random(in: -1...1) * clickEnv * 0.70
            data[i] = (body * bodyEnv * 0.75 + click) * gain
        }
        return buffer
    }

    private func renderChipHit(into data: UnsafeMutablePointer<Float>,
                               startSample: Int,
                               totalFrames: Int,
                               pitchHz: Float,
                               gain: Float) {
        let chipFrames = Int(sampleRate * 0.055)
        let p2 = pitchHz * 2.3
        for j in 0..<chipFrames {
            let i = startSample + j
            if i < 0 || i >= totalFrames { continue }
            let t = Float(j) / Float(sampleRate)
            let clickEnv = exp(-t * 800)
            let click    = Float.random(in: -1...1) * clickEnv
            let ringEnv  = exp(-t * 55)
            let ring     = (sin(2 * .pi * pitchHz * t) + sin(2 * .pi * p2 * t) * 0.35) * ringEnv
            data[i] += (click * 0.55 + ring * 0.55) * gain
        }
    }

    private func makeChipStack(chips: Int, spread: Double, gain: Float) -> AVAudioPCMBuffer? {
        let duration = 0.08 + spread + 0.02
        guard let buffer = makeBuffer(duration: duration) else { return nil }
        let data = buffer.floatChannelData![0]
        let n = Int(buffer.frameLength)
        for c in 0..<chips {
            let baseOffset = spread > 0 ? Double(c) / Double(max(1, chips - 1)) * spread : 0
            let jitter     = Double.random(in: -0.003...0.003)
            let startSec   = max(0, baseOffset + jitter)
            let startSample = Int(startSec * sampleRate)
            let pitchHz = Float.random(in: 430...680)
            let hitGain = gain * Float.random(in: 0.72...1.0)
            renderChipHit(into: data, startSample: startSample, totalFrames: n, pitchHz: pitchHz, gain: hitGain)
        }
        normalize(data: data, count: n, target: 0.88)
        return buffer
    }

    private func makeChipCascade(duration: Double, hits: Int, gain: Float) -> AVAudioPCMBuffer? {
        guard let buffer = makeBuffer(duration: duration + 0.08) else { return nil }
        let data = buffer.floatChannelData![0]
        let n = Int(buffer.frameLength)
        for _ in 0..<hits {
            let u = Double.random(in: 0...1)
            let t = u * u * (3 - 2 * u)
            let startSec    = 0.02 + t * duration * 0.82
            let startSample = Int(startSec * sampleRate)
            let pitchHz     = Float.random(in: 400...720)
            let hitGain     = gain * Float.random(in: 0.30...0.80)
            renderChipHit(into: data, startSample: startSample, totalFrames: n, pitchHz: pitchHz, gain: hitGain)
        }
        normalize(data: data, count: n, target: 0.82)
        return buffer
    }

    private func makeSoftTick(frequency: Float, duration: Double, gain: Float) -> AVAudioPCMBuffer? {
        guard let buffer = makeBuffer(duration: duration) else { return nil }
        let data = buffer.floatChannelData![0]
        let n = Int(buffer.frameLength)
        for i in 0..<n {
            let t = Float(i) / Float(sampleRate)
            let sine = sin(2 * .pi * frequency * t)
            let env  = exp(-t * 140)
            data[i] = sine * env * gain
        }
        return buffer
    }

    private func normalize(data: UnsafeMutablePointer<Float>, count: Int, target: Float) {
        var peak: Float = 0
        for i in 0..<count { peak = max(peak, abs(data[i])) }
        if peak > target {
            let scale = target / peak
            for i in 0..<count { data[i] *= scale }
        }
    }
}

// ─── Events ───────────────────────────────────────────────────────────────────

enum GameSound {
    case cardDeal
    case chipBet
    case fold
    case check
    case call
    case raise
    case allIn
    case win
    case timerWarning
}
