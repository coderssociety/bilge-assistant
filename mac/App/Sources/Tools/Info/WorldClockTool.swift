import AsistanCore
import Foundation
import FoundationModels

/// "Tokyo'da saat kaç", "New York ile aramızda kaç saat fark var".
struct WorldClockTool: RuleRoutedTool {
    let name = "worldClock"
    let description = "Dünyadaki bir şehirde ya da ülkede saatin kaç olduğunu ve aradaki saat farkını söyler."

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var command: String
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        WorldClockQuery.parse(command, language: AppLanguage.current) != nil
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(command: command)
    }

    func call(arguments: Arguments) async throws -> String {
        guard let query = WorldClockQuery.parse(arguments.command, language: AppLanguage.current) else {
            return ToolReply.failure(String(localized: "Hangi şehrin saatini sorduğunu anlayamadım."))
        }
        return query.answer(now: .now, language: AppLanguage.current)
    }
}
