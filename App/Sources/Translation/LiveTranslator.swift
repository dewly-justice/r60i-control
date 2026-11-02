import AVFoundation
import Observation
import os
import Speech
import Translation

/// Live translation, all on this Mac: the built-in microphone feeds Apple's speech recognizer
/// (`SpeechAnalyzer`), each finished sentence is translated (`TranslationSession`), and the
/// translation can be read aloud, which plays in the earbuds when they're the audio output.
///
/// This stands in for the Soundcore app's "AI Translation", which runs in the phone app and
/// Anker's cloud; the earbuds have no translation feature of their own.
@MainActor
@Observable
final class LiveTranslator {
    struct Segment: Identifiable, Equatable {
        let id = UUID()
        let original: String
        var translation: String?
        var failed = false
    }

    enum Phase: Equatable {
        case idle
        case preparing(String)
        case listening
        case failed(String)
    }

    enum TranslatorError: LocalizedError {
        case speechUnsupported(String)
        case noAudioFormat

        var errorDescription: String? {
            switch self {
            case let .speechUnsupported(language): "This Mac can't recognize \(language) speech."
            case .noAudioFormat: "Speech recognition has no usable audio format."
            }
        }
    }

    var source = TranslationLanguage.english
    var target = TranslationLanguage.vietnamese
    var speaksTranslations = true

    private(set) var phase: Phase = .idle
    private(set) var segments: [Segment] = []
    /// The sentence being heard right now, before the recognizer settles on it.
    private(set) var volatileText = ""
    private(set) var inputDeviceName: String?

    var isActive: Bool {
        switch phase {
        case .preparing, .listening: true
        case .idle, .failed: false
        }
    }

    /// What the window's `translationTask` uses. A new value restarts the translation session.
    var translationConfiguration: TranslationSession.Configuration {
        TranslationSession.Configuration(source: source.language, target: target.language)
    }

    @ObservationIgnored private var capture: AudioCapture?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    @ObservationIgnored private var requests: AsyncStream<Segment.ID>.Continuation?
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let log = Logger(subsystem: "dev.local.R60iControl", category: "translation")

    // MARK: Listening

    func start() async {
        guard !isActive else { return }
        phase = .preparing("Asking for microphone access…")
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            phase = .failed("Allow the microphone for R60i Control in System Settings → Privacy & Security → Microphone.")
            return
        }
        do {
            phase = .preparing("Preparing \(source.name) speech recognition…")
            let module = try await makeModule(for: source)
            try await installAssets(for: module)
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
                throw TranslatorError.noAudioFormat
            }
            let analyzer = SpeechAnalyzer(modules: [module])
            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            let capture = AudioCapture()
            try capture.start(analyzerFormat: format, into: continuation)

            self.analyzer = analyzer
            self.capture = capture
            inputContinuation = continuation
            inputDeviceName = capture.deviceName
            resultsTask = Task { [weak self] in await self?.consumeResults(of: module) }
            try await analyzer.start(inputSequence: stream)
            phase = .listening
            log.info("Listening for \(self.source.id, privacy: .public) on \(capture.deviceName ?? "?", privacy: .public)")
        } catch {
            await tearDown()
            phase = .failed(error.localizedDescription)
            log.error("Live translation failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() async {
        guard isActive else { return }
        await tearDown()
        phase = .idle
    }

    func clear() {
        segments = []
        volatileText = ""
    }

    func swapLanguages() {
        (source, target) = (target, source)
    }

    private func tearDown() async {
        capture?.stop()
        capture = nil
        inputContinuation?.finish()
        inputContinuation = nil
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        analyzer = nil
        resultsTask?.cancel()
        resultsTask = nil
        volatileText = ""
    }

    /// The long-form recognizer where it supports the language (English here), otherwise the
    /// dictation recognizer, which covers more languages (Vietnamese).
    private func makeModule(for language: TranslationLanguage) async throws -> any LocaleDependentSpeechModule {
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: language.speechLocale) {
            return SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        }
        if let locale = await DictationTranscriber.supportedLocale(equivalentTo: language.speechLocale) {
            return DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        }
        throw TranslatorError.speechUnsupported(language.name)
    }

    private func installAssets(for module: any LocaleDependentSpeechModule) async throws {
        guard await AssetInventory.status(forModules: [module]) != .installed else { return }
        phase = .preparing("Downloading the \(source.name) speech model…")
        _ = try? await AssetInventory.reserve(locale: module.selectedLocales.first ?? source.speechLocale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }

    private func consumeResults(of module: any SpeechModule) async {
        do {
            if let transcriber = module as? SpeechTranscriber {
                for try await result in transcriber.results {
                    handle(String(result.text.characters), isFinal: result.isFinal)
                }
            } else if let dictation = module as? DictationTranscriber {
                for try await result in dictation.results {
                    handle(String(result.text.characters), isFinal: result.isFinal)
                }
            }
        } catch is CancellationError {
        } catch {
            if isActive { phase = .failed(error.localizedDescription) }
        }
    }

    private func handle(_ text: String, isFinal: Bool) {
        guard isFinal else {
            volatileText = text
            return
        }
        volatileText = ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let segment = Segment(original: trimmed)
        segments.append(segment)
        requests?.yield(segment.id)
    }

    // MARK: Translating

    /// Runs inside the window's `translationTask` for as long as the session is valid, and
    /// translates finished sentences in order.
    func translate(using session: TranslationSession) async {
        // The session belongs to this window's translationTask and is only used from here.
        nonisolated(unsafe) let session = session
        let (stream, continuation) = AsyncStream.makeStream(of: Segment.ID.self)
        requests?.finish()
        requests = continuation
        for segment in segments where segment.translation == nil {
            continuation.yield(segment.id)
        }
        for await id in stream {
            guard let text = segments.first(where: { $0.id == id })?.original else { continue }
            do {
                let response = try await session.translate(text)
                update(id) { $0.translation = response.targetText }
                speak(response.targetText)
            } catch {
                update(id) {
                    $0.translation = error.localizedDescription
                    $0.failed = true
                }
                log.error("Translation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func update(_ id: Segment.ID, _ change: (inout Segment) -> Void) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        change(&segments[index])
    }

    private func speak(_ text: String) {
        // Through the Mac's speakers the microphone would hear the translation and transcribe it.
        guard speaksTranslations, phase == .listening, AudioCapture.outputIsBluetooth() else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: target.speechLocale.identifier(.bcp47))
        synthesizer.speak(utterance)
    }
}
