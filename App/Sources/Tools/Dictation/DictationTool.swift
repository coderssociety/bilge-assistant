import AppKit
import AsistanCore
import FoundationModels

/// "Dikte modunu başlat": from then on everything said without the wake phrase is typed into the app
/// in front, until "dikteyi bitir" or a minute of silence. The apps `TypeTextTool` refuses (terminals,
/// code editors, password managers) are refused here too.
struct DictationTool: RuleRoutedTool {
    let name = "startDictation"
    let description = "Dikte modunu başlatır: söylenenleri öndeki uygulamaya yazar."
    let session: DictationSession

    @Generable
    struct Arguments {}

    func emptyArguments() -> Arguments? { Arguments() }

    @MainActor
    func claims(_ command: String) -> Bool {
        DictationCommand.isStart(command, language: AppLanguage.current)
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            do {
                try AccessibilityControl.requireTrust()
            } catch {
                return ToolReply.failure(error)
            }
            guard let front = AccessibilityControl.frontApplication() else {
                return ToolReply.failure(String(localized: "Yazı yazılacak bir uygulama önde değil."))
            }
            if TypeTextTool.refuses(front) {
                return ToolReply.failure(String(
                    localized: "Güvenlik için terminallere, kod düzenleyicilere, uzak masaüstüne ve parola yöneticilerine dikte etmiyorum."))
            }
            session.begin(in: front)
            guard let appName = front.localizedName else {
                return String(localized: "Dikte açık, öndeki uygulamaya yazıyorum. Bitirmek için 'dikteyi bitir' de.")
            }
            return String(localized: "Dikte açık, \(appName) uygulamasına yazıyorum. Bitirmek için 'dikteyi bitir' de.")
        }
    }
}
