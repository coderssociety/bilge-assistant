import AsistanCore
import Foundation

/// Interpreting and meeting transcription: sessions that need Whisper whichever engine listens.
extension AssistantBrain {
    /// Starting or stopping the interpreter and the meeting commands; false for anything else.
    func handleSessionCommand(
        _ command: String,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws -> Bool {
        if interpreter.isActive, InterpreterCommand.isStop(command) {
            endInterpreter()
            continuation.yield(String(localized: "Tercüman kapandı."))
            return true
        }
        if let pair = InterpreterCommand.start(in: command, language: language) {
            await startInterpreter(pair, continuation: continuation)
            return true
        }
        switch MeetingCommand.parse(command, language: language) {
        case .startRecording:
            await startRecording(continuation: continuation)
        case .stopRecording:
            guard let recording = meetings.finish() else {
                continuation.yield(String(localized: "Şu an bir kayıt yok."))
                return true
            }
            try await finishRecording(recording, continuation: continuation)
        case let .transcribeFile(reference):
            try await transcribeFile(reference, continuation: continuation)
        case nil:
            return false
        }
        return true
    }

    /// One utterance heard while interpreting: translated and spoken in the other language, or the stop phrase.
    func interpret(_ speech: String, heard: String?) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    if InterpreterCommand.isStop(speech) {
                        endInterpreter()
                        continuation.yield(String(localized: "Tercüman kapandı."))
                    } else if !speech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              let direction = interpreter.direction(heard: heard, assistant: language) {
                        let instructions = InterpreterPrompt.instructions(from: direction.source, to: direction.target)
                        _ = try await streamUntrusted(InterpreterPrompt.prompt(speech), instructions: instructions, into: continuation)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    Log.brain.error("Interpreting failed: \(String(describing: error), privacy: .public)")
                    continuation.yield(Self.spokenMessage(for: error))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func startInterpreter(_ pair: InterpreterPair, continuation: AsyncThrowingStream<String, any Error>.Continuation) async {
        guard await prepareWhisper(continuation: continuation) != nil else { return }
        interpreter.begin(pair)
        let first = pair.first.name(in: language)
        let second = pair.second.name(in: language)
        continuation.yield(String(localized: "Tercüman açık: \(first) ve \(second). Her konuşmayı öbür dile çevirip o dilde söyleyeceğim. Bitirmek için “tercümanı kapat” de."))
    }

    private func endInterpreter() {
        interpreter.end()
        releaseWhisperIfIdle()
    }

    private func startRecording(continuation: AsyncThrowingStream<String, any Error>.Continuation) async {
        guard !meetings.isRecording else {
            continuation.yield(String(localized: "Zaten kaydediyorum. Bitirmek için “kaydı bitir” de."))
            return
        }
        guard await prepareWhisper(continuation: continuation) != nil else { return }
        interpreter.end()
        meetings.begin()
        continuation.yield(String(localized: "Kayıt başladı. Sen bitirene kadar konuşulanları yazıya döküyorum, sesin kendisi saklanmıyor. Bitirmek için “kaydı bitir” de."))
    }

    private func finishRecording(
        _ recording: MeetingRecorder.Recording,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws {
        releaseWhisperIfIdle()
        guard !recording.chunks.isEmpty else {
            continuation.yield(String(localized: "Kaydı bitirdim ama konuşma duymadım, dosya oluşturmadım."))
            return
        }
        continuation.yield(String(localized: "Kaydı bitirdim, özetliyorum. "))
        let when = recording.startedAt.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(language.locale))
        try await saveNotes(title: String(localized: "Toplantı — \(when)"), source: nil, duration: recording.duration,
                            chunks: recording.chunks, date: recording.startedAt, continuation: continuation)
    }

    private func transcribeFile(
        _ reference: MeetingCommand.AudioFileReference,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws {
        guard let file = await audioFile(reference) else {
            continuation.yield(reference == .latestDownload
                ? String(localized: "İndirilenler'de bir ses kaydı bulamadım.")
                : String(localized: "Seçili bir ses dosyası göremedim. Finder'da dosyayı seçip yeniden söyle ya da “son indirdiğim ses kaydını yazıya dök” de."))
            return
        }
        guard let recognizer = await prepareWhisper(continuation: continuation) else { return }
        defer { releaseWhisperIfIdle() }
        continuation.yield(String(localized: "“\(file.lastPathComponent)” dosyasını yazıya döküyorum, uzun kayıtlar birkaç dakika sürebilir. "))
        let transcript: AudioFileTranscriber.Transcript
        do {
            transcript = try await AudioFileTranscriber.transcribe(file, with: recognizer)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            Log.tools.error("Transcribing a file failed: \(String(describing: error), privacy: .public)")
            continuation.yield(ToolReply.spoken(ToolReply.failure(error)))
            return
        }
        guard !transcript.chunks.isEmpty else {
            continuation.yield(String(localized: "Dosyada yazıya dökülecek konuşma bulamadım."))
            return
        }
        try await saveNotes(title: String(localized: "Ses dökümü — \(file.lastPathComponent)"), source: file.lastPathComponent,
                            duration: transcript.duration, chunks: transcript.chunks, date: .now, continuation: continuation)
    }

    /// Writes the notes even when the summary fails or the user cuts the reply off, so a transcript is never lost;
    /// then says where they are and offers to read the summary.
    private func saveNotes(
        title: String,
        source: String?,
        duration: TimeInterval,
        chunks: [TranscriptChunk],
        date: Date,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws {
        var summary: String?
        var wasCancelled = false
        do {
            let summarizer = MeetingSummarizer(language: language) { prompt, instructions in
                try await self.generate(prompt, instructions: instructions, maxTokens: MeetingSummarizer.maximumSummaryTokens,
                                        announcingWaitTo: continuation)
            }
            summary = try await summarizer.summarize(chunks)
        } catch {
            wasCancelled = error is CancellationError || Task.isCancelled
            if !wasCancelled { Log.brain.error("Meeting summary failed: \(String(describing: error), privacy: .public)") }
        }
        let notes = MeetingNotes(title: title, source: source, duration: duration, summary: summary, chunks: chunks,
                                 language: language)
        do {
            let file = try MeetingNotesFile.write(notes, date: date)
            Log.tools.info("Meeting notes saved: \(file.path, privacy: .private)")
        } catch {
            Log.tools.error("Saving meeting notes failed: \(String(describing: error), privacy: .public)")
            continuation.yield(ToolReply.spoken(ToolReply.failure(error)))
            return
        }
        if wasCancelled { throw CancellationError() }
        let saved = String(localized: "Notları Belgeler'deki \(AppIdentity.name) klasöründe, Toplantılar'a kaydettim.")
        guard let summary else {
            continuation.yield(saved + " " + String(localized: "Özeti yazamadım, döküm dosyada."))
            return
        }
        guard let confirmer else {
            continuation.yield(saved)
            return
        }
        let answer = await confirmer.confirm(saved + " " + String(localized: "Özeti okumamı ister misin?"), strict: false)
        try Task.checkCancellation()
        continuation.yield(answer == .confirmed ? summary : String(localized: "Tamam."))
    }

    /// Loads Whisper for a session when it is on this Mac; otherwise says what is needed.
    private func prepareWhisper(continuation: AsyncThrowingStream<String, any Error>.Continuation) async -> (any SpeechRecognizer)? {
        guard whisper.isAvailable else {
            continuation.yield(WhisperProvider.missingMessage)
            return nil
        }
        if whisper.loaded == nil { continuation.yield(String(localized: "Konuşma tanımayı hazırlıyorum. ")) }
        do {
            return try await whisper.prepared()
        } catch {
            Log.speech.error("Whisper could not be loaded: \(String(describing: error), privacy: .public)")
            continuation.yield(ToolReply.spoken(ToolReply.failure(error)))
            return nil
        }
    }

    private func releaseWhisperIfIdle() {
        guard !interpreter.isActive, !meetings.isRecording else { return }
        whisper.releaseUnlessListening()
    }

    private func audioFile(_ reference: MeetingCommand.AudioFileReference) async -> URL? {
        let isAudio = { (url: URL) in MeetingCommand.audioExtensions.contains(url.pathExtension.lowercased()) }
        switch reference {
        case .latestDownload:
            let downloads = (try? FileManager.default.contentsOfDirectory(at: .downloadsDirectory, includingPropertiesForKeys: nil)) ?? []
            return FileSearch.sortedByRecency(downloads).first(where: isAudio)
        case .pointed:
            let screen = await ScreenContextReader.snapshot()
            return screen.selectedFiles.first(where: isAudio) ?? screen.documentURL.flatMap { isAudio($0) ? $0 : nil }
        }
    }
}
