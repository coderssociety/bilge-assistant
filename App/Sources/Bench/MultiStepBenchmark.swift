import AsistanCore
import Foundation

/// Times the multi-step planner step by step: `Asistan --bench-multistep <lmstudio:<id> | vmlx:<publisher/id>> [--interleave-chat]`.
/// `--interleave-chat` asks a chat question before each request, as real use mixes the two.
/// Read-only tools run for real; anything with side effects (clipboard, messages, notes…) is only
/// reported as done, so the benchmark never changes the user's Mac.
@MainActor
enum MultiStepBenchmark {
    static let flag = "--bench-multistep"
    static let interleaveFlag = "--interleave-chat"

    private static let commands = [
        "Son indirdiğim PDF'i özetle ve özeti panoya kopyala",
        "Yarın İstanbul'da hava nasıl öğren ve sonucu panoya kopyala",
        "Dolar kaç lira bul ve bunu Ahmet'e mesaj at",
        "Diskte ne kadar yer kaldığını bul ve onu not olarak kaydet",
    ]

    private static let readOnlyTools: Set<String> = [
        "currentDateTime", "calculate", "batteryStatus", "systemInfo", "weather", "exchangeRate", "news",
        "readCalendar", "readReminders", "listShortcuts", "listRunningApps", "findContact", "readDocument", "files",
    ]

    static func run(arguments: [String]) async -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1),
              let choice = LocalModelChoice(storageKey: arguments[index + 1]) else {
            print("Kullanım: Asistan \(flag) <lmstudio:<model> | vmlx:<yayıncı/model>>")
            return 2
        }
        let responder = LocalModelResponder()
        responder.keepAlive = .always
        responder.select(choice)
        guard await responder.waitUntilReady() else {
            print("Model hazırlanamadı")
            return 1
        }
        let tools = ToolRegistry(catalog: AppCatalog(), timers: TimerService { _ in }).makeTools()
        let (_, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let interleave = arguments.contains(interleaveFlag)
        for command in commands {
            if interleave {
                let chatStart = Date()
                _ = try? await responder.answer("Bana kısa bir söz söyle.", instructions: BrainInstructions.make(), into: continuation)
                print(String(format: "  (sohbet %.2f sn)", Date().timeIntervalSince(chatStart)))
            }
            var log: [String] = []
            let started = Date()
            let agent = MultiStepAgent(
                tools: tools,
                complete: { messages in
                    let stepStart = Date()
                    let reply = try await responder.complete(messages, maxTokens: MultiStepAgent.maxReplyTokens,
                                                             announcingWaitTo: continuation)
                    log.append(String(format: "  model %.2f sn, %d karakter: %@", Date().timeIntervalSince(stepStart),
                                      reply.count, String(reply.prefix(110)).replacingOccurrences(of: "\n", with: " ")))
                    return reply
                },
                execute: { call in
                    let stepStart = Date()
                    let result = readOnlyTools.contains(call.toolName)
                        ? try await call.execute()
                        : "Tamam (deneme: \(call.toolName) çalıştırılmadı)."
                    log.append(String(format: "  araç %@ %.2f sn", call.toolName, Date().timeIntervalSince(stepStart)))
                    return result
                })
            do {
                let outcome = try await agent.run(command)
                print(String(format: "■ %.2f sn · %@\n  → %@", Date().timeIntervalSince(started), command, outcome.summary))
            } catch {
                print("■ HATA · \(command): \(error)")
            }
            log.forEach { print($0) }
        }
        responder.shutDown()
        return 0
    }
}
