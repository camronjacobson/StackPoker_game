import Foundation
import AVFoundation

// ─── Replay Narrator ─────────────────────────────────────────────────────────
// Optional voice-over for the analysis stream. When the user enables narration,
// each new analysis card is read aloud in a soft, measured female voice so the
// review feels like having a calm coach next to you.
//
// Voice selection prefers Apple's premium / enhanced female voices in this
// order: Ava → Allison → Samantha → system default. The "premium" tier in
// iOS Settings → Accessibility → Spoken Content sounds dramatically better
// than the compact fallback; we still degrade gracefully if it isn't
// installed.
//
// Speech tweaks aimed at "respectable, soothing":
//   • rate slightly under default (more measured)
//   • pitch a touch above neutral (warmer, less robotic)
//   • short pre/post utterance pauses so cards don't bleed together

@MainActor
final class ReplayNarrator: ObservableObject {
    static let shared = ReplayNarrator()

    @Published var enabled: Bool = false {
        didSet { if !enabled { stop() } }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenAnalysisId: String?

    private init() {
        // Mix with other audio (chip/win sounds keep playing) and don't
        // interrupt music the user might already have running.
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.mixWithOthers, .duckOthers]
        )
        #endif
    }

    // ─── Public API ───────────────────────────────────────────────────────────

    func toggle() { enabled.toggle() }

    /// Speak this analysis if it's different from the last one we spoke and
    /// narration is enabled. Safe to call on every frame change — duplicate
    /// calls are deduped by id.
    func speak(_ analysis: FrameAnalysis) {
        guard enabled else { return }
        guard analysis.id != lastSpokenAnalysisId else { return }
        lastSpokenAnalysisId = analysis.id

        let text = buildSpokenText(analysis)
        guard !text.isEmpty else { return }

        // If we're mid-sentence, cut over to the new card immediately —
        // the user has scrubbed or playback advanced.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92  // slightly slower
        utterance.pitchMultiplier = 1.05                            // a hair warmer
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.20
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        lastSpokenAnalysisId = nil
    }

    // ─── Voice selection ──────────────────────────────────────────────────────

    /// Walk a preference list of high-quality female US English voices,
    /// returning the first one the device actually has installed.
    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        // Try identifier-based premium voices first (iOS 16+ adds these
        // via Settings → Accessibility → Spoken Content → Voices).
        let identifiers = [
            "com.apple.voice.premium.en-US.Ava",
            "com.apple.voice.enhanced.en-US.Ava",
            "com.apple.voice.premium.en-US.Allison",
            "com.apple.voice.enhanced.en-US.Allison",
            "com.apple.voice.premium.en-US.Samantha",
            "com.apple.voice.enhanced.en-US.Samantha",
            "com.apple.voice.premium.en-US.Zoe",
            "com.apple.voice.enhanced.en-US.Zoe",
            "com.apple.voice.compact.en-US.Samantha",
        ]
        for id in identifiers {
            if let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        }

        // Fallback: scan installed voices for a US English female with
        // the highest quality available.
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en-US") }
            .filter { $0.gender == .female || $0.name.lowercased().contains("samantha") }
            .sorted { lhs, rhs in
                rank(lhs.quality) > rank(rhs.quality)
            }
        return candidates.first ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private func rank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
        switch q {
        case .premium:  return 3
        case .enhanced: return 2
        case .default:  return 1
        @unknown default: return 0
        }
    }

    // ─── Text shaping ─────────────────────────────────────────────────────────

    /// Produce a sentence the synth can read naturally. Strips visual
    /// punctuation, expands poker abbreviations, and joins the card's three
    /// possible commentary fields with sensible pauses.
    private func buildSpokenText(_ a: FrameAnalysis) -> String {
        var pieces: [String] = []

        // Lead with a brief verdict-flavoured prefix so the listener knows
        // what kind of card this is without parsing the title.
        switch a.verdict {
        case .correct:      pieces.append("Nice play.")
        case .mistake:      pieces.append("Worth a look.")
        case .questionable: pieces.append("Borderline spot.")
        case .fine, .info:  break
        }

        if let your = a.yourMove { pieces.append(your) }
        if let rec  = a.recommendation { pieces.append("Try this. \(rec)") }
        if let read = a.opponentRead { pieces.append(read) }

        var text = pieces.joined(separator: " ")

        // Expand and clean for natural speech.
        let replacements: [(String, String)] = [
            ("·", ","),
            ("—", ","),
            ("–", ","),
            (" / ", " or "),
            ("3-bet", "three-bet"),
            ("3bet",  "three-bet"),
            ("4-bet", "four-bet"),
            ("c-bet", "continuation bet"),
            (" bb",   " big blinds"),
            ("BTN",   "the button"),
            ("UTG",   "under the gun"),
            ("OOP",   "out of position"),
            ("EV",    "expected value"),
            ("QQ+",   "queens or better"),
            ("AK",    "ace king"),
            ("AQ",    "ace queen"),
            ("JJ",    "jacks"),
            ("TT",    "tens"),
            ("99",    "nines"),
        ]
        for (from, to) in replacements {
            text = text.replacingOccurrences(of: from, with: to)
        }
        return text
    }
}
