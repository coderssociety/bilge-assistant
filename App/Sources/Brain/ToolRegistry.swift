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

    func makeTools() -> [any AssistantTool] {
        [
            OpenAppTool(catalog: catalog),
            QuitAppTool(catalog: catalog),
            RunningAppsTool(),
            WebSearchTool(),
            OpenWebsiteTool(),
            DateTimeTool(),
            CalculatorTool(),
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
            NewsTool(),
            ReadWebPageTool(),
            ReadMailTool(),
            SendEmailTool(),
            SendMessageTool(),
            RememberTool(memory: memory, context: context),
            ForgetTool(memory: memory),
            ListMemoriesTool(memory: memory),
            SpreadsheetTool(session: spreadsheet),
        ]
    }
}
