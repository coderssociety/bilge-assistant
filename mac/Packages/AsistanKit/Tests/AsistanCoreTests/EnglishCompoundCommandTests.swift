import Testing
@testable import AsistanCore

@Suite("English compound commands")
struct EnglishCompoundCommandTests {
    @Test("splits at sequence words and before a verb", arguments: [
        ("Open Safari and set the volume to 30", [String]?.some(["Open Safari", "set the volume to 30"])),
        ("Find Ahmet's number and then text him I'm late", ["Find Ahmet's number", "text him I'm late"]),
        ("Summarize the PDF, then copy the summary", ["Summarize the PDF", "copy the summary"]),
        ("Remind me to buy milk and bread", nil),
        ("Text Ali and Veli that dinner is ready", nil),
        ("What's the weather", nil),
    ])
    func split(text: String, expected: [String]?) {
        #expect(CompoundCommand.split(text, language: .english) == expected)
    }

    @Test("later parts that refer to an earlier result")
    func dependent() {
        #expect(CompoundCommand.hasDependentParts(["Find Ahmet's number", "text him I'm late"], language: .english))
        #expect(CompoundCommand.hasDependentParts(["Summarize the PDF", "copy the summary"], language: .english))
        #expect(!CompoundCommand.hasDependentParts(["Open Safari", "set the volume to 30"], language: .english))
    }
}
