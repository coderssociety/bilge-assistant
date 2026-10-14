import Foundation
import Testing
@testable import AsistanCore

@Suite("English basics")
struct EnglishLanguageTests {
    @Test("yes and no in English", arguments: [
        ("Yes, send it", ConfirmationParser.Answer.confirmed), ("yeah sure", .confirmed), ("go ahead", .confirmed),
        ("No", .rejected), ("cancel that", .rejected), ("never mind", .rejected), ("don't", .rejected),
        ("maybe later", .unclear), ("yes no", .unclear),
    ])
    func confirmation(text: String, expected: ConfirmationParser.Answer) {
        #expect(ConfirmationParser.parse(text, language: .english) == expected)
    }

    @Test("sending needs a clear English yes")
    func strictConfirmation() {
        #expect(ConfirmationParser.parse("okay", strict: true, language: .english) == .unclear)
        #expect(ConfirmationParser.parse("yes", strict: true, language: .english) == .confirmed)
        #expect(ConfirmationParser.parse("send it", strict: true, language: .english) == .confirmed)
    }

    @Test("one language's words do not count in the other")
    func separateLanguages() {
        #expect(ConfirmationParser.parse("süre", language: .turkish) == .unclear)
        #expect(ConfirmationParser.parse("evet", language: .english) == .unclear)
        #expect(ConfirmationParser.parse("yes", language: .turkish) == .unclear)
    }

    @Test("English stop words cut in; filler alone does not")
    func bargeIn() {
        let detector = BargeInDetector(matcher: WakePhraseMatcher(phrase: "bilge"), language: .english)
        #expect(detector.evaluate(heard: "stop", speaking: "The weather is fine") == .stop)
        #expect(detector.evaluate(heard: "okay stop now", speaking: "The weather is fine") == .stop)
        #expect(detector.evaluate(heard: "please", speaking: "The weather is fine") == .none)
        #expect(detector.evaluate(heard: "Bilge, stop", speaking: "The weather is fine") == .stop)
        #expect(detector.evaluate(heard: "Bilge, what time is it", speaking: "Sunny and warm today")
            == .command("what time is it"))
    }

    @Test("the wake phrase after an English greeting")
    func wakeAfterGreeting() {
        let matcher = WakePhraseMatcher(phrase: "bilge")
        #expect(matcher.match("Hey Bilge, what time is it?")?.command == "what time is it?")
        #expect(matcher.match("Okay Bilge open Safari")?.command == "open Safari")
    }

    @Test("cancel phrases end a pending command")
    func cancel() {
        var flow = ConversationFlow(matcher: WakePhraseMatcher(phrase: "bilge"))
        let now = Date()
        _ = flow.heard("Bilge", at: now)
        #expect(flow.heard("never mind", at: now.addingTimeInterval(1)) == .returnToIdle(timedOut: false))
    }

    @Test("English abbreviations do not end a sentence")
    func abbreviations() {
        #expect(SentenceSplitter.split("Mr. Smith is here. He is waiting.") == ["Mr. Smith is here.", "He is waiting."])
    }

    @Test("English speech text spells out symbols and keeps digits", arguments: [
        ("It is 25% cheaper.", "It is 25 percent cheaper."),
        ("**Today** it is 18°C. ☀️", "Today it is 18 degrees Celsius."),
        ("The dollar is 49.39 TL", "The dollar is 49.39 lira"),
        ("It is 3:30 now", "It is 3:30 now"),
    ])
    func englishSpeech(input: String, expected: String) {
        #expect(SpokenText.normalize(input, language: .english) == expected)
    }

    @Test("Turkish speech text is unchanged by the split")
    func turkishSpeech() {
        #expect(SpokenText.normalize("Saat 14:30", language: .turkish) == TurkishSpeechNormalizer.normalize("Saat 14:30"))
        #expect(SpokenText.normalize("**Önemli:** %25", language: .turkish) == "Önemli: yüzde yirmi beş")
    }

    @Test("the Mac's preferred language picks the assistant's", arguments: [
        (["en-US", "tr-TR"], AssistantLanguage.english), (["tr-TR"], .turkish), (["de-DE", "en-GB"], .english),
        (["fr-FR"], .turkish), ([], .turkish),
    ])
    func preferred(identifiers: [String], expected: AssistantLanguage) {
        #expect(AssistantLanguage.preferred(from: identifiers) == expected)
    }
}
