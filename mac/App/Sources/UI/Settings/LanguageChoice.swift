import AsistanCore
import SwiftUI

/// Picks the assistant's language. Labels are shown in both languages, since the user may not read
/// the current one; applying restarts the app so menus switch too.
struct LanguageChoice: View {
    let settings: AssistantSettings
    @State private var selection: AssistantLanguage

    init(settings: AssistantSettings) {
        self.settings = settings
        _selection = State(initialValue: settings.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Dil · Language", selection: $selection) {
                ForEach(AssistantLanguage.allCases, id: \.self) { Text($0.nativeName).tag($0) }
            }
            .pickerStyle(.radioGroup)
            Text("Bilge seni bu dilde dinler, bu dilde konuşur ve menüleri bu dilde gösterir.\nBilge listens, speaks and shows its menus in this language.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if selection != settings.language {
                Button("Uygula ve yeniden başlat · Apply and restart") {
                    settings.chooseLanguage(selection)
                    AppRelauncher.relaunch()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
