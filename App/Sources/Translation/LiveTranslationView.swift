import SwiftUI
import Translation

/// The Live Translation window: the language pair as one menu in the middle of the toolbar, Start on the trailing edge, the running transcript (translation first,
/// original underneath), and a status line.
struct LiveTranslationView: View {
    static let windowID = "live-translation"

    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var translator = model.translator
        VStack(spacing: 0) {
            TranscriptView(translator: translator)
            Divider()
            StatusBar(translator: translator)
        }
        .frame(minWidth: 600, minHeight: 360)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // One compact menu for the language pair, so Start never overflows.
                Menu {
                    Picker("Translate From", selection: $translator.source) {
                        ForEach(TranslationLanguage.all) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Picker("Translate To", selection: $translator.target) {
                        ForEach(TranslationLanguage.all) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Swap Languages", systemImage: "arrow.left.arrow.right") {
                        translator.swapLanguages()
                    }
                } label: {
                    Label("\(translator.source.name) → \(translator.target.name)", systemImage: "translate")
                        .labelStyle(.titleAndIcon)
                }
                .fixedSize()
                .help("Languages")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $translator.speaksTranslations) {
                    Label("Speak Translations", systemImage: translator.speaksTranslations ? "speaker.wave.2.fill" : "speaker.slash")
                }
                .help("Read translations aloud in the earbuds. Only while a Bluetooth device is the audio output, so the microphone doesn't hear them.")
                Button {
                    translator.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(translator.segments.isEmpty)
                .help("Clear the transcript")
                Button {
                    Task { translator.isActive ? await translator.stop() : await translator.start() }
                } label: {
                    Label(translator.isActive ? "Stop" : "Start", systemImage: translator.isActive ? "stop.fill" : "mic.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
            }
        }
        // The language pair says what the window is; the title stays for the Window menu.
        .navigationTitle("Live Translation")
        .toolbar(removing: .title)
        // Languages can't change mid-sentence: stop when they do.
        .onChange(of: translator.source) { Task { await translator.stop() } }
        .onChange(of: translator.target) { Task { await translator.stop() } }
        .translationTask(translator.translationConfiguration) { session in
            await translator.translate(using: session)
        }
        .onDisappear { Task { await translator.stop() } }
    }
}

private struct TranscriptView: View {
    let translator: LiveTranslator

    var body: some View {
        if translator.segments.isEmpty, translator.volatileText.isEmpty {
            ContentUnavailableView {
                Label(translator.isActive ? "Listening…" : "Not Listening", systemImage: "translate")
            } description: {
                Text(translator.isActive
                    ? "Speak \(translator.source.name), or let the Mac hear the room. Each sentence appears here in \(translator.target.name)."
                    : "Click Start. The Mac's microphone listens for \(translator.source.name) and translates each sentence into \(translator.target.name), on this Mac.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(translator.segments) { segment in
                            SegmentView(segment: segment)
                                .id(segment.id)
                        }
                        if !translator.volatileText.isEmpty {
                            Text(translator.volatileText)
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .id("volatile")
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .onChange(of: translator.segments.count) {
                    withAnimation { proxy.scrollTo(translator.segments.last?.id, anchor: .bottom) }
                }
                .onChange(of: translator.volatileText) {
                    proxy.scrollTo("volatile", anchor: .bottom)
                }
            }
        }
    }
}

private struct SegmentView: View {
    let segment: LiveTranslator.Segment

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let translation = segment.translation {
                Text(translation)
                    .font(.title3)
                    .foregroundStyle(segment.failed ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            } else {
                Text("Translating…")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            Text(segment.original)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatusBar: View {
    let translator: LiveTranslator

    var body: some View {
        HStack(spacing: 6) {
            switch translator.phase {
            case .idle:
                Image(systemName: "mic.slash")
                Text("Not listening. Uses the Mac's built-in microphone so the earbuds keep full audio quality.")
            case let .preparing(message):
                ProgressView().controlSize(.small)
                Text(message)
            case .listening:
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
                Text("Listening on \(translator.inputDeviceName ?? "the microphone")")
            case let .failed(message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
