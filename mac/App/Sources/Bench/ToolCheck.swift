import AppKit
import AsistanCore
import Foundation
import Network
import Synchronization

/// Checks inside the real app that tools work, not just that their parsing rules do:
/// `open -n -W Bilge.app --args --bench-tools <report.txt>`. Launch it with `open` so macOS asks for
/// (and remembers) permissions for Bilge rather than for the terminal. Only read-only tools run;
/// memory uses a store that lives in memory only, so the user's own facts are never touched.
@MainActor
enum ToolCheck {
    static let flag = "--bench-tools"
    /// Also edits a new, unsaved Excel workbook by voice commands, then closes it without saving.
    static let excelFlag = "--excel"
    /// Also dictates into a new, unsaved TextEdit document, then closes it without saving.
    static let dictationFlag = "--dictation"

    private struct Report {
        var lines: [String] = []
        var failures = 0

        mutating func check(_ name: String, _ passed: Bool, _ detail: String) {
            if !passed { failures += 1 }
            lines.append("\(passed ? "✓" : "✗") \(name): \(detail)")
        }
    }

    /// Commands routed and executed for real; every tool here only reads.
    private static let readOnlyCommands: [(command: String, tool: String)] = [
        ("Saat kaç", "currentDateTime"),
        ("Yüz yirmi beşin yüzde on sekizi kaç eder", "calculate"),
        ("Pil durumu nedir", "batteryStatus"),
        ("Diskte ne kadar boş yer var", "systemInfo"),
        ("Mac ne zamandır açık", "systemInfo"),
        ("Yarın Ankara'da hava nasıl", "weather"),
        ("Yüz euro kaç lira", "exchangeRate"),
        ("Gündemde ne var", "news"),
        ("Bugün takvimimde ne var", "readCalendar"),
        ("Yapılacaklar listemde ne var", "readReminders"),
        ("Hangi kestirmelerim var", "listShortcuts"),
        ("Şu an hangi uygulamalar açık", "listRunningApps"),
    ]

    /// Routed only: these would change something, so the check stops at the routing decision.
    private static let routedOnly: [(command: String, tool: String)] = [
        ("Yarın sabah süt almayı hatırlat", "addReminder"),
        ("On dakika sonra fırına bakmamı hatırlat", "setTimer"),
        ("Süt almayı unutma diye hatırlat", "addReminder"),
    ]

    static func run(arguments: [String]) async -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        let outPath = arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        var report = Report()
        await checkAppleScript(&report)
        await checkWebSafety(&report)
        let memory = MemoryStore(fileURL: nil)
        let registry = ToolRegistry(catalog: AppCatalog(), timers: TimerService { _ in }, memory: memory)
        let tools = registry.makeTools()
        do {
            let router = try CommandRouter(tools: tools)
            router.prewarm()
            await checkReadOnlyTools(router, &report)
            await checkMemory(router, memory, &report)
            await checkMemoryInConversation(tools: tools, memory: memory, &report)
            await checkContext(router, registry.context, &report)
            await checkBrowser(router, &report)
            await checkBriefing(router, &report)
            if arguments.contains(excelFlag) { await checkExcel(router, &report) }
            if arguments.contains(dictationFlag) { await checkDictation(&report) }
        } catch {
            report.check("router", false, "başlatılamadı: \(error)")
        }
        await checkAlerts(&report)
        report.lines.append("\(report.failures == 0 ? "TAMAM" : "\(report.failures) HATA")")
        let text = report.lines.joined(separator: "\n")
        print(text)
        if let outPath { try? text.write(toFile: outPath, atomically: true, encoding: .utf8) }
        return report.failures == 0 ? 0 : 1
    }

    private static func checkAppleScript(_ report: inout Report) async {
        var maxGap = 0.0
        var last = Date()
        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
                maxGap = max(maxGap, Date().timeIntervalSince(last))
                last = Date()
            }
        }
        let result = try? await AppleScriptRunner.run("delay 1\nreturn \"çğış\"")
        ticker.cancel()
        report.check("AppleScript ana iş parçacığı", result == "çğış" && maxGap < 0.3,
                     String(format: "sonuç %@, en uzun takılma %.2f sn", result ?? "yok", maxGap))

        let started = Date()
        let hanging = Task { try await AppleScriptRunner.run("delay 10") }
        try? await Task.sleep(for: .milliseconds(500))
        hanging.cancel()
        let cancelled = await hanging.result
        let elapsed = Date().timeIntervalSince(started)
        let isCancelled = if case .failure(is CancellationError) = cancelled { true } else { false }
        report.check("AppleScript iptal", isCancelled && elapsed < 3, String(format: "%.2f sn", elapsed))

        do {
            _ = try await AppleScriptRunner.run("error \"x\" number -1743")
            report.check("AppleScript hata", false, "hata gelmedi")
        } catch {
            report.check("AppleScript hata", error.localizedDescription.contains("Otomasyon"), error.localizedDescription)
        }
    }

    private static func checkWebSafety(_ report: inout Report) async {
        for address in ["http://localhost/", "http://127.0.0.1:80/", "http://[::1]/"] {
            do {
                _ = try await WebFetch.data(from: URL(string: address)!)
                report.check("yerel adres reddi", false, "\(address) okundu!")
            } catch WebFetchError.localAddress {
                report.check("yerel adres reddi", true, address)
            } catch {
                report.check("yerel adres reddi", false, "\(address): beklenmeyen hata \(error)")
            }
        }
        await checkRebinding(&report)
        let started = Date()
        do {
            let data = try await WebFetch.data(from: URL(string: "https://api.frankfurter.app/latest?from=USD&to=TRY")!)
            report.check("açık internet", String(decoding: data, as: UTF8.self).contains("TRY"),
                         String(format: "%d bayt, %.2f sn", data.count, Date().timeIntervalSince(started)))
        } catch {
            report.check("açık internet", false, error.localizedDescription)
        }
    }

    /// localtest.me is a public name that resolves to 127.0.0.1, the shape of a DNS rebinding attack.
    /// A local listener plays the victim service: the client must refuse before sending a single byte.
    private static func checkRebinding(_ report: inout Report) async {
        let listener: NWListener
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
            listener = try NWListener(using: parameters)
        } catch {
            report.check("DNS rebinding", false, "dinleyici açılamadı: \(error)")
            return
        }
        let received = Mutex(0)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                received.withLock { $0 += data?.count ?? 0 }
                connection.cancel()
            }
        }
        let isReady = Mutex(false)
        listener.stateUpdateHandler = { state in if case .ready = state { isReady.withLock { $0 = true } } }
        listener.start(queue: .global())
        defer { listener.cancel() }
        for _ in 0..<100 where !isReady.withLock({ $0 }) { try? await Task.sleep(for: .milliseconds(20)) }
        guard let port = listener.port?.rawValue, let url = URL(string: "http://localtest.me:\(port)/") else {
            report.check("DNS rebinding", false, "dinleyici hazır olmadı")
            return
        }
        do {
            _ = try await PublicHTTPClient.get(url, headers: [], maxBodyBytes: 1000, timeout: .seconds(5))
            report.check("DNS rebinding", false, "yerel servise istek gitti!")
        } catch WebFetchError.localAddress {
            try? await Task.sleep(for: .milliseconds(200))
            let bytes = received.withLock { $0 }
            report.check("DNS rebinding", bytes == 0, "localtest.me → 127.0.0.1 reddedildi, servise giden bayt: \(bytes)")
        } catch {
            report.check("DNS rebinding", false, "beklenmeyen hata \(error)")
        }
    }

    private static func checkReadOnlyTools(_ router: CommandRouter, _ report: inout Report) async {
        for (command, expected) in readOnlyCommands {
            let started = Date()
            do {
                guard case let .tool(call) = try await router.route(command, previous: nil), call.toolName == expected else {
                    report.check(expected, false, "\(command) → yanlış yönlendirildi")
                    continue
                }
                guard call.risk == .safe else {
                    report.check(expected, false, "\(command) → onay istiyor, çalıştırılmadı")
                    continue
                }
                let result = try await call.execute()
                let detail = String(format: "%.2f sn · %@", Date().timeIntervalSince(started), String(result.prefix(90)))
                report.check(expected, !ToolReply.isFailure(result), detail.replacingOccurrences(of: "\n", with: " "))
            } catch {
                report.check(expected, false, "\(command): \(error)")
            }
        }
        for (command, expected) in routedOnly {
            let route = try? await router.route(command, previous: nil)
            let action = if case let .tool(call)? = route { call.toolName } else { "conversation" }
            report.check("yönlendirme", action == expected, "\(command) → \(action)")
        }
    }

    private static func checkMemory(_ router: CommandRouter, _ memory: MemoryStore, _ report: inout Report) async {
        let steps: [(command: String, tool: String, expect: (String) -> Bool)] = [
            ("Eşimin adının Ayşe olduğunu hatırla", "remember", { _ in memory.book.entries.map(\.text) == ["Eşimin adının Ayşe olduğunu"] }),
            ("Neleri hatırlıyorsun", "listMemories", { $0.contains("Ayşe") }),
            ("Eşimin adını unut", "forget", { _ in memory.book.entries.isEmpty }),
        ]
        for step in steps {
            do {
                guard case let .tool(call) = try await router.route(step.command, previous: nil), call.toolName == step.tool else {
                    report.check("hafıza", false, "\(step.command) → yanlış yönlendirildi")
                    continue
                }
                let result = try await call.execute()
                report.check("hafıza", step.expect(result), "\(step.command) → \(result)")
            } catch {
                report.check("hafıza", false, "\(step.command): \(error)")
            }
        }
    }

    /// A remembered fact must reach the conversation model's instructions and shape its answer.
    private static func checkMemoryInConversation(tools: [any AssistantTool], memory: MemoryStore, _ report: inout Report) async {
        _ = try? memory.remember("Kızımın adı Defne")
        defer { _ = try? memory.forgetAll() }
        let brain = AssistantBrain(tools: tools, memory: memory)
        var answer = ""
        do {
            for try await chunk in brain.respond(to: "Kızımın adı ne?") { answer += chunk }
            report.check("hafıza sohbette", answer.contains("Defne"), answer)
        } catch {
            report.check("hafıza sohbette", false, "\(error)")
        }
    }

    private static func checkExcel(_ router: CommandRouter, _ report: inout Report) async {
        do {
            _ = try await AppleScriptRunner.run("tell application \"Microsoft Excel\" to make new workbook")
        } catch {
            report.check("Excel", false, "yeni çalışma kitabı açılamadı: \(error.localizedDescription)")
            return
        }
        try? await Task.sleep(for: .seconds(1))
        let steps: [(command: String, expected: String, asks: Bool)] = [
            ("B1'e 10 yaz", "B1: 10.", false),
            ("B2'ye 20,5 yaz", "B2: 20,5.", false),
            ("D3'e B2 ile B1'i topla", "D3: 30,5.", false),
            ("D3'ü oku", "D3: 30,5.", false),
            ("B10'a B1'den B9'a kadar topla", "B10: 30,5.", false),
            ("B1'den B2'ye kadar ortalama kaç", "Sonuç 15,25.", false),
            ("D3'e B2 çarpı 2 yaz", "D3: 41.", true),
            ("geri al", "Geri aldım, D3: 30,5.", false),
            ("D3'ü E3'e kopyala", "E3: ", false),
            ("A1'e Kira Gideri yaz", "A1: Kira Gideri.", false),
            ("E3'ü sil", "E3 boş.", false),
            ("B sütununun toplamı kaç", "Sonuç 61.", false),
            ("D3 eşittir B2 bölü 0", "D3 hata veriyor", true),
            ("geri al", "Geri aldım, D3: 30,5.", false),
            ("D4'e B2'nin yüzde yirmi fazlasını hesapla", "D4: 24,6.", true),
            ("C1'e B1'in iki katını hesapla", "C1: 20.", true),
        ]
        for step in steps {
            let started = Date()
            do {
                let route = try await router.route(step.command, previous: nil)
                guard case let .tool(call) = route, call.toolName == "spreadsheet" else {
                    let actual = if case let .tool(other) = route { other.toolName } else { "conversation" }
                    report.check("Excel", false, "\(step.command) → \(actual)")
                    continue
                }
                let asked = call.risk == .needsConfirmation
                if let question = call.confirmationQuestion { report.lines.append("   soru: \(question)") }
                let result = try await call.execute()
                let passed = result.hasPrefix(step.expected) && asked == step.asks
                report.check("Excel", passed, String(format: "%@ → %@%@ (%.2f sn)", step.command, result,
                                                     asked ? " [onay istedi]" : "", Date().timeIntervalSince(started)))
            } catch {
                report.check("Excel", false, "\(step.command): \(error)")
            }
        }
        let chatter = try? await router.route("akşam ne yiyoruz", previous: nil)
        if case let .tool(call)? = chatter, call.toolName == "spreadsheet" {
            report.check("Excel", false, "sohbet Excel'e gitti")
        } else {
            report.check("Excel", true, "sohbet Excel komutu sayılmadı")
        }
        _ = try? await AppleScriptRunner.run("tell application \"Microsoft Excel\" to close active workbook saving no")
    }

    /// What "bu" ("this") refers to, with the screen given rather than read, so the check does not depend on
    /// which app happens to be in front.
    private static func checkContext(_ router: CommandRouter, _ context: ConversationContext, _ report: inout Report) async {
        let document = FileManager.default.temporaryDirectory.appending(path: "bilge-baglam-denemesi.txt")
        try? "Toplantı perşembeye ertelendi. Bütçe onaylandı.".write(to: document, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: document) }
        let cases: [(command: String, screen: ScreenContext, tool: String, expect: (String) -> Bool)] = [
            ("Bu sayfayı özetle", ScreenContext(pageURL: URL(string: "https://example.com")!, pageTitle: "Example"), "useContext",
             { $0.contains("Example Domain") }),
            ("Bu belgede ne yazıyor", ScreenContext(documentURL: document), "useContext", { $0.contains("perşembeye") }),
            ("Seçili metni İngilizceye çevir", ScreenContext(selectedText: "Merhaba dünya"), "useContext", { $0 == "Merhaba dünya" }),
            ("Şu dosyayı aç", ScreenContext(selectedFiles: [URL(filePath: "/System/Applications/Calculator.app")]), "useContext",
             { $0.contains("programları sesle açmıyorum") }),
        ]
        for item in cases {
            context.screen = item.screen
            do {
                let route = try await router.route(item.command, previous: nil)
                guard case let .tool(call) = route, call.toolName == item.tool else {
                    let actual = if case let .tool(other) = route { other.toolName } else { "conversation" }
                    report.check("bağlam", false, "\(item.command) → \(actual)")
                    continue
                }
                let result = try await call.execute()
                report.check("bağlam", item.expect(result), "\(item.command) → \(result.prefix(70).replacingOccurrences(of: "\n", with: " "))")
            } catch {
                report.check("bağlam", false, "\(item.command): \(error)")
            }
        }
        context.screen = ScreenContext(selectedFiles: [document])
        let mail = await SendEmailTool(context: context).makeCall(.init(recipient: "deneme@example.com", subject: nil, body: "bunu"))
        report.check("bağlam", mail.confirmationQuestion?.contains("ekinde bilge-baglam-denemesi.txt") == true,
                     "bunu mail at → \(mail.confirmationQuestion ?? "soru yok")")
        context.screen = nil
        let nothing = try? await router.route("Bunu özetle", previous: nil)
        let routedAway = if case let .tool(call)? = nothing { call.toolName != "useContext" } else { true }
        report.check("bağlam", routedAway, "ekranda bir şey yokken 'bunu özetle' bağlam aracına gitmedi")
    }

    /// Routing only, plus reading tab titles: sending keys would change the user's own browser.
    private static func checkBrowser(_ router: CommandRouter, _ report: inout Report) async {
        let cases = [("Sonraki sekmeye geç", "browserControl"), ("Geri git", "browserControl"), ("Aşağı kaydır", "browserControl"),
                     ("Bu sayfada fiyat kelimesini ara", "browserControl"), ("geri al", "conversation"), ("Safari'yi aç", "openApp")]
        for (command, expected) in cases {
            let route = try? await router.route(command, previous: nil)
            let actual = if case let .tool(call)? = route { call.toolName } else { "conversation" }
            report.check("tarayıcı", actual == expected || (expected == "conversation" && actual != "browserControl"), "\(command) → \(actual)")
        }
        let browser = await MainActor.run {
            NSWorkspace.shared.runningApplications.first { BrowserPage.isScriptable($0.bundleIdentifier) }?.bundleIdentifier
        }
        guard let browser else {
            report.check("tarayıcı", true, "açık tarayıcı yok, sekme okuma atlandı")
            return
        }
        do {
            let titles = try await BrowserPage.tabTitles(in: browser)
            report.check("tarayıcı", !titles.isEmpty, "\(browser): \(titles.count) sekme okundu")
        } catch {
            report.check("tarayıcı", false, "\(browser) sekmeleri okunamadı: \(error.localizedDescription)")
        }
    }

    /// Opens a temporary text file in TextEdit (no Automation permission needed), dictates into it, reads
    /// the text back through Accessibility, then empties, saves and closes it (no save prompt) and deletes it.
    private static func checkDictation(_ report: inout Report) async {
        let file = FileManager.default.temporaryDirectory.appending(path: "bilge-dikte-\(UUID().uuidString.prefix(8)).txt")
        try? "".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
            report.check("dikte", false, "TextEdit bulunamadı")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        guard let app = try? await NSWorkspace.shared.open([file], withApplicationAt: textEdit, configuration: configuration) else {
            report.check("dikte", false, "TextEdit açılamadı")
            return
        }
        for _ in 0..<40 where NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(500))
        let session = DictationSession()
        let start = (try? await DictationTool(session: session).call(arguments: .init())) ?? ""
        report.check("dikte", session.isActive, start)
        for input in ["merhaba virgül nasılsın soru işareti", "yeni satır", "ikinci satır nokta", "son cümleyi sil", "üçüncü deneme"] {
            let reply = await session.handle(input)
            try? await Task.sleep(for: .milliseconds(200))
            let now = ((try? AccessibilityControl.focusedValue()) ?? nil) ?? "?"
            report.lines.append("   \(input) → [\(now.replacingOccurrences(of: "\n", with: "⏎"))] \(reply)")
        }
        let finished = await session.handle("dikteyi bitir")
        try? await Task.sleep(for: .milliseconds(300))
        let typed = ((try? AccessibilityControl.focusedValue()) ?? nil) ?? "(okunamadı)"
        let focused = AccessibilityControl.attribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute)
        let role = focused.flatMap { AccessibilityControl.attribute($0 as! AXUIElement, kAXRoleAttribute) as? String } ?? "yok"
        report.lines.append("   tanı: postEvent=\(CGPreflightPostEventAccess()) ax=\(AXIsProcessTrusted()) önde=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") odak=\(role)")
        let (a, delete, s, w): (CGKeyCode, CGKeyCode, CGKeyCode, CGKeyCode) = (0, 51, 1, 13)
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            try? AccessibilityControl.press(a, flags: .maskCommand)
            try? AccessibilityControl.press(delete)
            try? AccessibilityControl.press(s, flags: .maskCommand)
            try? await Task.sleep(for: .milliseconds(500))
            try? AccessibilityControl.press(w, flags: .maskCommand)
        }
        let expected = "Merhaba, nasılsın?\nÜçüncü deneme"
        report.check("dikte", typed == expected && !session.isActive && finished == "Dikte bitti.",
                     "yazılan: \(typed.replacingOccurrences(of: "\n", with: "⏎")) · bitiş: \(finished)")
    }

    /// Runs the summary for real (it only reads); the "already briefed today" mark is put back after.
    private static func checkBriefing(_ router: CommandRouter, _ report: inout Report) async {
        let markKey = "lastMorningBriefing"
        let mark = UserDefaults.standard.object(forKey: markKey)
        defer { UserDefaults.standard.set(mark, forKey: markKey) }
        let started = Date()
        do {
            guard case let .tool(call) = try await router.route("Günün özeti", previous: nil), call.toolName == "dailyBriefing" else {
                report.check("günlük özet", false, "Günün özeti → yanlış yönlendirildi")
                return
            }
            let text = try await call.execute()
            let greets = ["Günaydın.", "İyi günler.", "İyi akşamlar."].contains { text.hasPrefix($0) }
            report.check("günlük özet", greets, String(format: "%.2f sn · %@", Date().timeIntervalSince(started), text))
        } catch {
            report.check("günlük özet", false, "\(error)")
        }
        let afternoon = try? await router.route("Günaydın", previous: nil)
        let greetingRoute = if case let .tool(call)? = afternoon { call.toolName } else { "conversation" }
        let isMorning = Calendar.current.component(.hour, from: .now) < 12
        report.check("günlük özet", isMorning || greetingRoute != "dailyBriefing", "öğleden sonra 'Günaydın' → \(greetingRoute)")
    }

    private static func checkAlerts(_ report: inout Report) async {
        let now = Date()
        let day = DateInterval(start: now, duration: 24 * 60 * 60)
        let candidates = await CalendarAccess.shared.alertCandidates(eventsIn: day, remindersDueIn: day)
        report.check("hatırlatma sorgusu", true, "önümüzdeki 24 saatte \(candidates.count) etkinlik/anımsatıcı")
    }
}
