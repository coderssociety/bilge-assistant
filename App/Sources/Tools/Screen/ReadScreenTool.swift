import Foundation
import FoundationModels

/// "Ekranda ne yazıyor?", "bu hatayı oku", "bu sayfayı özetle". The captured text is untrusted:
/// it is only ever summarized by a tool-less model session, so text on screen cannot trigger actions.
struct ReadScreenTool: AssistantTool {
    let name = "readScreen"
    let description = "Ekranda, öndeki pencerede yazanları okur; hata mesajını okur ya da sayfayı özetler."
    let answersWithLanguageModel = true

    @Generable
    enum Scope {
        case frontWindow, wholeScreen
    }

    @Generable
    struct Arguments {
        @Guide(description: "Öndeki pencere mi, tüm ekran mı. Belirtilmediyse frontWindow.")
        var scope: Scope
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            let text = try await ScreenReader.readText(scope: arguments.scope == .wholeScreen ? .wholeScreen : .frontWindow)
            return text.isEmpty ? ToolReply.failure(String(localized: "Ekranda okunabilir bir yazı bulamadım.")) : text
        } catch {
            return ToolReply.failure(error)
        }
    }
}
