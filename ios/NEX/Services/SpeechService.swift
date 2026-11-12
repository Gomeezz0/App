import AVFoundation

/// Indicaciones por voz. Baja el volumen de la música mientras habla y lo restaura al terminar.
@MainActor
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "es-ES")
    var isMuted = false {
        didSet { if isMuted { synthesizer.stopSpeaking(at: .immediate) } }
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// - Parameter urgent: interrumpe lo que se esté diciendo (órdenes de giro inmediatas).
    func speak(_ text: String, urgent: Bool = false) {
        guard !isMuted, !text.isEmpty else { return }
        if urgent, synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        MainActor.assumeIsolated {
            guard !synthesizer.isSpeaking else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
