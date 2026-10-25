import AsistanCore
import Foundation

/// Prompts for the two constrained routing steps. Written in English: the small on-device model
/// follows structured-task instructions more reliably in English, whichever language the user speaks.
enum RouterInstructions {
    /// Short paraphrases, deliberately different from the benchmark sentences.
    private static let turkishExamples: [(String, String)] = [
        ("Chrome'u açar mısın", "openApp"),
        ("Notları aç", "openApp"),
        ("şu an çalan parça hangisi", "controlMusic"),
        ("hangi komutları anlıyorsun", "conversation"),
        ("Notlar uygulamasını kapat", "quitApp"),
        ("şu an hangi programlar çalışıyor", "listRunningApps"),
        ("Google'da en yakın eczane", "searchWeb"),
        ("sahibinden.com'a gir", "openWebsite"),
        ("tarih ne", "currentDateTime"),
        ("kırk sekiz bölü altı", "calculate"),
        ("şarjım ne kadar", "batteryStatus"),
        ("kopyaladığım yazı ne", "readClipboard"),
        ("sesi sonuna kadar aç", "setVolume"),
        ("şarkıyı değiştir", "controlMusic"),
        ("ekranı karart", "systemAction"),
        ("Belgeler klasörünü göster", "files"),
        ("Cuma günü toplantım var mı", "readCalendar"),
        ("yapılacaklar listemde ne var", "readReminders"),
        ("beş dakika sonra fırına bakmamı hatırlat", "setTimer"),
        ("alarmları sil", "manageTimers"),
        ("makarna alarmını kapat", "manageTimers"),
        ("toplantı notu diye not al", "createNote"),
        ("cumartesi saat ikide halı saha maçı ekle", "addCalendarEvent"),
        ("süt almayı listeme ekle", "addReminder"),
        ("cuma günü dişçiyi unutma", "addReminder"),
        ("eski ekran görüntüsünü sil", "moveFileToTrash"),
        ("hangi kestirmelerim var", "listShortcuts"),
        ("iş modu kestirmesini çalıştır", "runShortcut"),
        ("ekranda ne yazıyor", "readScreen"),
        ("bu hata ne diyor", "readScreen"),
        ("bu sayfayı özetle", "readScreen"),
        ("uyku odağını aç", "runShortcut"),
        ("kaç zamanlayıcım var", "manageTimers"),
        ("Mehmet'in telefonu kaç", "findContact"),
        ("Zeynep'in e-postası ne", "findContact"),
        ("ilacı aldım listeden çıkar", "completeReminder"),
        ("tarif notumu oku", "readNotes"),
        ("Barış Manço çal", "playMusic"),
        ("sabah listemi çal", "playMusic"),
        ("makine kaç saattir çalışıyor", "systemInfo"),
        ("bellek ne kadar dolu", "systemInfo"),
        ("kablosuz ağı kapat", "setWiFi"),
        ("ekranın resmini çek", "takeScreenshot"),
        ("ses ayarlarını aç", "openSettings"),
        ("güncellemeleri kontrol et", "openSettings"),
        ("İndirilenler'de Fotoğraflar adında klasör yap", "createFolder"),
        ("bütçe raporu belgesini özetle", "readDocument"),
        ("bu cevabı kopyala", "copyToClipboard"),
        ("Mail'i gizle", "windowControl"),
        ("pencereyi sağa yasla", "windowControl"),
        ("şunu yaz toplantı ertelendi", "typeText"),
        ("işaretlediğim metni açıkla", "readSelection"),
        ("İzmir'de yarın yağmur var mı", "weather"),
        ("dışarısı kaç derece", "weather"),
        ("sterlin ne kadar", "exchangeRate"),
        ("50 dolar kaç lira eder", "exchangeRate"),
        ("spor haberlerini oku", "news"),
        ("gündemde ne var", "news"),
        ("tarayıcıdaki makaleyi özetle", "readWebPage"),
        ("hürriyet.com.tr'de ne yazıyor", "readWebPage"),
        ("yeni mailim var mı", "readMail"),
        ("Kemal'den e-posta geldi mi", "readMail"),
        ("Burak'a yarınki toplantının iptal olduğunu mail at", "sendEmail"),
        ("Elif'e eve geldiğimi mesaj at", "sendMessage"),
        ("Everest'in yüksekliği ne kadar", "conversation"),
        ("nasılsın", "conversation"),
        ("Ay'a ilk kim gitti", "conversation"),
    ]

    /// Short paraphrases, deliberately different from the English benchmark sentences.
    private static let englishExamples: [(String, String)] = [
        ("could you open Chrome", "openApp"),
        ("launch Notes", "openApp"),
        ("what song is this", "controlMusic"),
        ("what can you do", "conversation"),
        ("quit the Notes app", "quitApp"),
        ("which programs are running right now", "listRunningApps"),
        ("google the nearest pharmacy", "searchWeb"),
        ("go to wikipedia.org", "openWebsite"),
        ("what's the date", "currentDateTime"),
        ("forty eight divided by six", "calculate"),
        ("how much charge do I have", "batteryStatus"),
        ("what did I copy", "readClipboard"),
        ("turn the sound all the way up", "setVolume"),
        ("skip this track", "controlMusic"),
        ("put the display to sleep", "systemAction"),
        ("show me the Documents folder", "files"),
        ("do I have any meetings on Friday", "readCalendar"),
        ("what's on my to-do list", "readReminders"),
        ("remind me in five minutes to check the oven", "setTimer"),
        ("delete all alarms", "manageTimers"),
        ("cancel the pasta timer", "manageTimers"),
        ("take a note called meeting notes", "createNote"),
        ("add a football game on Saturday at two", "addCalendarEvent"),
        ("put buying milk on my list", "addReminder"),
        ("don't forget the dentist on Friday", "addReminder"),
        ("trash the old screenshot", "moveFileToTrash"),
        ("which shortcuts do I have", "listShortcuts"),
        ("run the work mode shortcut", "runShortcut"),
        ("what does the screen say", "readScreen"),
        ("what does this error mean", "readScreen"),
        ("turn on sleep focus", "runShortcut"),
        ("how many timers are running", "manageTimers"),
        ("what's Mehmet's phone number", "findContact"),
        ("what's Zeynep's email address", "findContact"),
        ("I took the medicine, cross it off", "completeReminder"),
        ("read my recipe note", "readNotes"),
        ("play some Queen", "playMusic"),
        ("play my morning playlist", "playMusic"),
        ("how long has this Mac been on", "systemInfo"),
        ("how much memory is used", "systemInfo"),
        ("switch off wi-fi", "setWiFi"),
        ("grab a screenshot", "takeScreenshot"),
        ("open sound settings", "openSettings"),
        ("check for updates", "openSettings"),
        ("make a folder called Photos in Downloads", "createFolder"),
        ("summarize the budget report document", "readDocument"),
        ("copy that answer", "copyToClipboard"),
        ("hide Mail", "windowControl"),
        ("snap the window to the right", "windowControl"),
        ("type meeting is postponed", "typeText"),
        ("explain the text I highlighted", "readSelection"),
        ("is it going to rain in Paris tomorrow", "weather"),
        ("how cold is it outside", "weather"),
        ("what's the pound worth", "exchangeRate"),
        ("convert fifty dollars to euros", "exchangeRate"),
        ("read me the sports news", "news"),
        ("what's in the headlines", "news"),
        ("summarize the article in my browser", "readWebPage"),
        ("what does bbc.com say", "readWebPage"),
        ("any new mail", "readMail"),
        ("did Kemal email me", "readMail"),
        ("email Burak that tomorrow's meeting is cancelled", "sendEmail"),
        ("text Elif that I got home", "sendMessage"),
        ("how tall is Everest", "conversation"),
        ("how are you", "conversation"),
        ("who first walked on the Moon", "conversation"),
    ]

    static func router(tools: [any AssistantTool], language: AssistantLanguage) -> String {
        let actions = tools.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
        let available = Set(tools.map(\.name) + [CommandRouter.conversationAction])
        let examples = language == .english ? englishExamples : turkishExamples
        let shots = examples.filter { available.contains($0.1) }
            .map { "\"\($0.0)\" → \($0.1)" }.joined(separator: "\n")
        let (kind, rules) = language == .english ? ("an English", englishRules) : ("a Turkish", turkishRules)
        let spoken = language == .english ? "English" : "Turkish"
        return """
        You are the intent router of \(AppIdentity.name), \(kind) voice assistant running on the user's Mac.
        Read the user's \(spoken) request and choose exactly one action.

        Actions:
        \(actions)
        - conversation: greetings, thanks, small talk, jokes, general knowledge questions, or anything no action above covers.

        Rules:
        \(rules)

        Examples:
        \(shots)
        """
    }

    /// Unchanged from the Turkish-only version, which routed all 185 benchmark commands correctly.
    private static let turkishRules = """
        - If the user wants something done on the Mac, or asks about the Mac's current state (time, date, battery, calendar, reminders, music, files, volume, timers), choose the matching action, never conversation.
        - "<name> aç" / "<name>'ı aç" with an application name means openApp, even for apps like Takvim, Notlar, Müzik or Mail.
        - Questions about the song that is playing are controlMusic.
        - "hatırlat" after a duration ("10 dakika sonra") or at a time today is setTimer; adding something to the to-do list or for another day is addReminder.
        - Appointments and meetings to put on the calendar are addCalendarEvent; asking what is on the calendar is readCalendar.
        - Turning on Focus/Do Not Disturb, brightness or anything else not covered by an action is runShortcut.
        - Questions about the assistant itself (what it can do, who it is) are conversation.
        - A short follow-up such as "peki yarın?" or "biraz daha" continues the previous action.
        - Questions that ask for knowledge ("…neresi", "…hangisi", "…kimdir", "kaç yaşında") are conversation. Use searchWeb only when the user explicitly asks to search or look something up on the web.
        - Weather and temperature are weather; exchange rates and currency conversion are exchangeRate; news headlines are news.
        - Reading or summarizing the web page open in the browser, or a named web address, is readWebPage; opening a site is openWebsite.
        - Reading unread e-mail is readMail. Sending e-mail is sendEmail; sending a text/iMessage ("mesaj at", "yaz") to a person is sendMessage.
        - Someone's phone number or e-mail address is findContact.
        - Finishing a to-do ("…tamamladım", "…yaptım, işaretle", "listeden çıkar") is completeReminder.
        - Playing a named song, artist, album or playlist is playMusic; play, pause, next and "what is playing" are controlMusic.
        - Uptime, disk space, memory, IP address and macOS version are systemInfo, not currentDateTime.
        - "<section> ayarlarını aç" opens a System Settings section: openSettings, not openApp.
        - Making a new folder is createFolder; opening an existing folder is files.
        - Reading or summarizing a document file is readDocument; a note in the Notes app is readNotes.
        - Text the user selected or highlighted ("seçili", "seçtiğim", "işaretlediğim"), including translating it, is readSelection.
        - "şunu yaz …" / "buraya … yaz" types the words into the current app: typeText. Taking a note is createNote.
        """

    private static let englishRules = """
        - If the user wants something done on the Mac, or asks about the Mac's current state (time, date, battery, calendar, reminders, music, files, volume, timers), choose the matching action, never conversation.
        - "open <name>" / "launch <name>" with an application name means openApp, even for apps like Calendar, Notes, Music or Mail.
        - Questions about the song that is playing are controlMusic.
        - "remind me" after a duration ("in 10 minutes") or at a time today is setTimer; adding something to the to-do list or for another day is addReminder.
        - Appointments and meetings to put on the calendar are addCalendarEvent; asking what is on the calendar is readCalendar.
        - Turning on Focus/Do Not Disturb, brightness or anything else not covered by an action is runShortcut.
        - Questions about the assistant itself (what it can do, who it is) are conversation.
        - A short follow-up such as "what about tomorrow?" or "a bit more" continues the previous action.
        - Questions that ask for knowledge ("where is…", "which…", "who is…", "how old is…") are conversation. Use searchWeb only when the user explicitly asks to search or look something up on the web.
        - Weather and temperature are weather; exchange rates and currency conversion are exchangeRate; news headlines are news.
        - Reading or summarizing the web page open in the browser, or a named web address, is readWebPage; opening a site is openWebsite.
        - Reading unread e-mail is readMail. Sending e-mail is sendEmail; sending a text/iMessage ("text", "message") to a person is sendMessage.
        - Someone's phone number or e-mail address is findContact.
        - Finishing a to-do ("I did…", "mark … as done", "cross … off") is completeReminder.
        - Playing a named song, artist, album or playlist is playMusic; play, pause, next and "what is playing" are controlMusic.
        - Uptime, disk space, memory, the Wi-Fi network, IP address and macOS version are systemInfo, not currentDateTime.
        - "open <section> settings" opens a System Settings section: openSettings, not openApp.
        - Making a new folder is createFolder; opening an existing folder is files.
        - Reading or summarizing a document file is readDocument; a note in the Notes app is readNotes.
        - Text the user selected or highlighted, including translating it, is readSelection.
        - "type …" / "write … here" types the words into the current app: typeText. Taking a note is createNote.
        """

    static func extraction<T: AssistantTool>(for tool: T, language: AssistantLanguage) -> String {
        let now = Date.now.formatted(.dateTime.day().month(.wide).year().weekday(.wide).hour().minute().locale(language.locale))
        let languageNotes = switch language {
        case .turkish: """
            The user speaks Turkish. Use only what the request says; leave optional fields empty when they are not mentioned.
            Write names in their base form without Turkish case suffixes ("Safari'yi" → "Safari", "hesap makinesini" → "Hesap Makinesi").
            Convert spoken numbers to digits ("yirmi beş" → 25, "sabah yedide" → hour 7).
            """
        case .english: """
            The user speaks English. Use only what the request says; leave optional fields empty when they are not mentioned.
            Write names as plain names ("the Safari app" → "Safari"). Field descriptions may give Turkish examples; apply the same rule to English.
            Convert spoken numbers to digits ("twenty five" → 25, "seven in the morning" → hour 7, "7 pm" → hour 19).
            """
        }
        return """
        Fill in the parameters for the action "\(tool.name)": \(tool.description)
        \(languageNotes)
        Current date and time: \(now).
        """
    }
}
