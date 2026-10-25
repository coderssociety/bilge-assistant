import AsistanCore
import FoundationModels

/// Builds the tool set handed to the language model. Kept small on purpose: every tool's schema
/// costs context tokens, and the on-device model has an 8K window.
@MainActor
struct ToolRegistry {
    let catalog: AppCatalog
    let timers: TimerService
    var context = ConversationContext()
    /// In memory only unless the app passes its stored one, so benchmarks never touch the user's facts.
    var memory = MemoryStore(fileURL: nil)
    var spreadsheet = SpreadsheetSession()
    var dictation = DictationSession()
    var news = NewsReading()
    var language = AssistantLanguage.turkish

    func makeTools() -> [any AssistantTool] {
        [
            OpenAppTool(catalog: catalog),
            QuitAppTool(catalog: catalog),
            RunningAppsTool(),
            WebSearchTool(),
            OpenWebsiteTool(),
            DateTimeTool(),
            CalculatorTool(language: language),
            BatteryTool(),
            ClipboardReadTool(),
            VolumeTool(),
            MediaTool(),
            SystemActionTool(),
            FileTool(),
            CalendarQueryTool(),
            RemindersQueryTool(),
            SetTimerTool(service: timers),
            ManageTimersTool(service: timers),
            CreateNoteTool(),
            CreateEventTool(),
            CreateReminderTool(),
            TrashFileTool(),
            ListShortcutsTool(),
            RunShortcutTool(),
            ReadScreenTool(),
            FindContactTool(),
            CompleteReminderTool(),
            ReadNotesTool(),
            PlayMusicTool(),
            SystemInfoTool(),
            WiFiTool(),
            ScreenshotTool(),
            SettingsPaneTool(),
            CreateFolderTool(),
            ReadDocumentTool(),
            CopyToClipboardTool(context: context),
            WindowTool(),
            TypeTextTool(),
            ReadSelectionTool(),
            WeatherTool(),
            ExchangeRateTool(),
            NewsTool(reading: news),
            NewsSourceTool(news: NewsTool(reading: news)),
            NewsArticleTool(reading: news),
            ReadWebPageTool(),
            ReadMailTool(),
            SendEmailTool(context: context),
            SendMessageTool(context: context),
            RememberTool(memory: memory, context: context, language: language),
            ForgetTool(memory: memory, language: language),
            ListMemoriesTool(memory: memory),
            SpreadsheetTool(session: spreadsheet),
            ContextTool(context: context),
            BrowserTool(),
            DictationTool(session: dictation),
            BriefingTool(),
        ]
    }
}
