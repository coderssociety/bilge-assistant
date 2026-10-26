import AsistanCore
import Foundation
import FoundationModels

/// "10 mil kaç kilometre", "2 litre kaç bardak": converted by rule, never by the model's arithmetic.
struct UnitConversionTool: RuleRoutedTool {
    let name = "convertUnits"
    let description = "Uzunluk, ağırlık, hacim, sıcaklık, hız, alan, veri ve süre birimlerini çevirir."

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var command: String
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        UnitConversion.parse(command, language: AppLanguage.current) != nil
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(command: command)
    }

    func call(arguments: Arguments) async throws -> String {
        guard let conversion = UnitConversion.parse(arguments.command, language: AppLanguage.current) else {
            return ToolReply.failure(String(localized: "Hangi birimden hangisine çevireceğimi anlayamadım."))
        }
        return conversion.answer(language: AppLanguage.current)
    }
}
