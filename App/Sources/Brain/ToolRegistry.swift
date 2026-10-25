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
    var routines = RoutineStore(fileURL: nil)
    /// Only the app passes the user's Home Assistant; without it there is no smart-home tool.
    var home: HomeAssistantConfig?
    var spreadsheet = SpreadsheetSession()
    var dictation = DictationSession()
    var news = NewsReading()
    var weather = WeatherReading()
    var language = AssistantLanguage.turkish

    func makeTools() -> [any AssistantTool] {
        // Rule-routed tools claim commands in this order: a routine's command may name any other tool, and a home
        // command may name a room that other rules would take.
        let first: [any AssistantTool] = [
            AddRoutineTool(store: routines, language: language),
            ManageRoutinesTool(store: routines, language: language),
        ] + (home.map { [SmartHomeTool(home: $0, language: language)] } ?? [])
        return first + [
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
            BrightnessTool(),
            BluetoothTool(),
            FileTool(),
            CalendarQueryTool(),
            RemindersQueryTool(),
            SetTimerTool(service: timers),
            ManageTimersTool(service: timers),
            CreateNoteTool(),
            CreateEventTool(),
            ChangeEventTool(),
            CreateReminderTool(),
            TrashFileTool(),
            ListShortcutsTool(),
            RunShortcutTool(),
            ReadScreenTool(),
            FindContactTool(),
            CallContactTool(),
            CompleteReminderTool(),
            ReadNotesTool(),
            AppendNoteTool(),
            PlayMusicTool(),
            RadioTool(),
            PodcastTool(),
            YouTubeSummaryTool(),
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
            WeatherTool(reading: weather),
            ExchangeRateTool(),
            NewsTool(reading: news),
            NewsSourceTool(news: NewsTool(reading: news)),
            NewsArticleTool(reading: news),
            ReadWebPageTool(),
            ReadMailTool(context: context),
            ReplyMailTool(context: context),
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
            UnitConversionTool(),
            WorldClockTool(),
            PrayerTimesTool(),
            GoldPriceTool(),
            FuelPriceTool(),
            WikipediaTool(),
            EarthquakeTool(),
            FootballTool(),
            StockTool(),
        ]
    }
}
