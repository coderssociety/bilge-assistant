import Foundation
import Testing
@testable import AsistanCore

@Suite("ConversationFlow")
struct ConversationFlowTests {
    let start = Date(timeIntervalSince1970: 1_000)

    func makeFlow() -> ConversationFlow {
        ConversationFlow(matcher: WakePhraseMatcher(phrase: "asistan"), commandTimeout: 6, followUpWindow: 5)
    }

    @Test("ignores speech without the wake phrase")
    func ignoresStrangers() {
        var flow = makeFlow()
        #expect(flow.heard("bugün hava güzel", at: start) == .none)
        #expect(flow.phase == .listeningForWake)
    }

    @Test("wake phrase with a command runs it immediately")
    func wakeWithCommand() {
        var flow = makeFlow()
        #expect(flow.heard("Asistan, Safari'yi aç", at: start) == .runCommand("Safari'yi aç"))
        #expect(flow.phase == .processing)
    }

    @Test("bare wake phrase waits for the command, then runs it")
    func bareWake() {
        var flow = makeFlow()
        #expect(flow.heard("Asistan", at: start) == .acknowledgeWake)
        #expect(flow.phase == .awaitingCommand(deadline: start.addingTimeInterval(6)))
        #expect(flow.heard("saat kaç", at: start.addingTimeInterval(2)) == .runCommand("saat kaç"))
    }

    @Test("command wait times out back to idle")
    func commandTimeout() {
        var flow = makeFlow()
        _ = flow.heard("asistan", at: start)
        #expect(flow.tick(at: start.addingTimeInterval(5)) == .none)
        #expect(flow.tick(at: start.addingTimeInterval(6.1)) == .returnToIdle(timedOut: true))
        #expect(flow.phase == .listeningForWake)
    }

    @Test("speech that has started is not cut by the deadline")
    func speechExtendsDeadline() {
        var flow = makeFlow()
        _ = flow.heard("asistan", at: start)
        flow.speechStarted(at: start.addingTimeInterval(5.5))
        #expect(flow.tick(at: start.addingTimeInterval(7)) == .none)
        #expect(flow.heard("yarın sabah yedide beni uyandır", at: start.addingTimeInterval(8)) ==
            .runCommand("yarın sabah yedide beni uyandır"))
    }

    @Test("speech that ends without being heard lets the window close")
    func unheardSpeechExpires() {
        var flow = makeFlow()
        _ = flow.heard("asistan", at: start)
        flow.speechStarted(at: start.addingTimeInterval(2))
        flow.speechEnded(at: start.addingTimeInterval(2.2))
        #expect(flow.tick(at: start.addingTimeInterval(7)) == .none)
        #expect(flow.tick(at: start.addingTimeInterval(8.3)) == .returnToIdle(timedOut: true))
    }

    @Test("a command transcribed after its speech ended still runs")
    func transcribedAfterSpeechEnded() {
        var flow = makeFlow()
        _ = flow.heard("asistan", at: start)
        flow.speechStarted(at: start.addingTimeInterval(5))
        flow.speechEnded(at: start.addingTimeInterval(7))
        #expect(flow.tick(at: start.addingTimeInterval(8)) == .none)
        #expect(flow.heard("saat kaç", at: start.addingTimeInterval(8.5)) == .runCommand("saat kaç"))
    }

    @Test("unheard speech after an answer does not keep the follow-up open")
    func unheardSpeechInFollowUp() {
        var flow = makeFlow()
        flow.responseStarted()
        flow.responseFinished(at: start, allowFollowUp: true)
        flow.speechStarted(at: start.addingTimeInterval(1))
        flow.speechEnded(at: start.addingTimeInterval(1.5))
        #expect(flow.tick(at: start.addingTimeInterval(7.6)) == .returnToIdle(timedOut: false))
    }

    @Test("cancel words end the exchange")
    func cancel() {
        var flow = makeFlow()
        _ = flow.heard("asistan", at: start)
        #expect(flow.heard("Vazgeç.", at: start.addingTimeInterval(1)) == .returnToIdle(timedOut: false))
        #expect(flow.phase == .listeningForWake)
    }

    @Test("speech while processing or responding is ignored")
    func busyIgnoresSpeech() {
        var flow = makeFlow()
        _ = flow.heard("asistan saat kaç", at: start)
        #expect(flow.heard("asistan müziği aç", at: start) == .none)
        flow.responseStarted()
        #expect(flow.phase == .responding)
        #expect(flow.heard("asistan müziği aç", at: start) == .none)
    }

    @Test("after a reply a follow-up needs no wake phrase until the window closes")
    func followUp() {
        var flow = makeFlow()
        _ = flow.heard("asistan saat kaç", at: start)
        flow.responseStarted()
        flow.responseFinished(at: start.addingTimeInterval(2), allowFollowUp: true)
        #expect(flow.phase == .followUp(deadline: start.addingTimeInterval(7)))
        #expect(flow.heard("peki yarın?", at: start.addingTimeInterval(3)) == .runCommand("peki yarın?"))
    }

    @Test("follow-up window closes silently")
    func followUpExpires() {
        var flow = makeFlow()
        _ = flow.heard("asistan saat kaç", at: start)
        flow.responseFinished(at: start, allowFollowUp: true)
        #expect(flow.tick(at: start.addingTimeInterval(6)) == .returnToIdle(timedOut: false))
    }

    @Test("a repeated wake phrase in follow-up is stripped from the command")
    func followUpStripsWakePhrase() {
        var flow = makeFlow()
        _ = flow.heard("asistan saat kaç", at: start)
        flow.responseFinished(at: start, allowFollowUp: true)
        #expect(flow.heard("Asistan, sesi kıs", at: start.addingTimeInterval(1)) == .runCommand("sesi kıs"))
    }

    @Test("without follow-up the flow returns to wake listening")
    func noFollowUp() {
        var flow = makeFlow()
        _ = flow.heard("asistan saat kaç", at: start)
        flow.responseFinished(at: start, allowFollowUp: false)
        #expect(flow.phase == .listeningForWake)
    }

    @Test("a work session keeps listening longer but only for what it accepts")
    func workSession() {
        var flow = makeFlow()
        _ = flow.heard("Asistan, D3'e B2 ile B1'i topla", at: start)
        flow.responseStarted()
        let session = ConversationFlow.WorkSession(window: 40) { $0.contains("topla") || $0.contains("yaz") }
        flow.responseFinished(at: start, allowFollowUp: false, session: session)
        #expect(flow.phase == .followUp(deadline: start.addingTimeInterval(40)))
        // Chatter in the room is ignored and does not end the session.
        #expect(flow.heard("akşam ne yiyoruz", at: start.addingTimeInterval(5)) == .none)
        #expect(flow.isAwaitingSpeech)
        #expect(flow.heard("C5'e 1250 yaz", at: start.addingTimeInterval(8)) == .runWorkInput("C5'e 1250 yaz"))
    }

    @Test("in a work session the wake phrase still reaches everything")
    func workSessionWakePhrase() {
        var flow = makeFlow()
        flow.responseStarted()
        flow.responseFinished(at: start, allowFollowUp: false, session: .init(window: 40) { _ in false })
        #expect(flow.heard("Asistan, saat kaç", at: start.addingTimeInterval(3)) == .runCommand("saat kaç"))
    }

    @Test("ignored speech in a work session does not keep the window open past its deadline")
    func workSessionExpires() {
        var flow = makeFlow()
        flow.responseStarted()
        flow.responseFinished(at: start, allowFollowUp: false, session: .init(window: 40) { _ in false })
        flow.speechStarted(at: start.addingTimeInterval(39))
        #expect(flow.heard("bir şeyler", at: start.addingTimeInterval(41)) == .none)
        #expect(flow.tick(at: start.addingTimeInterval(41)) == .returnToIdle(timedOut: false))
    }

    @Test("a session that takes everything gets wake-phrase speech and cancel words as input")
    func sessionTakingEverything() {
        var flow = makeFlow()
        flow.responseStarted()
        let session = ConversationFlow.WorkSession(window: 120, takesEverything: true, languages: ["tr", "en"]) { _ in true }
        flow.responseFinished(at: start, allowFollowUp: false, session: session)
        #expect(flow.activeWorkSession?.languages == ["tr", "en"])
        #expect(flow.heard("never mind", at: start.addingTimeInterval(3)) == .runWorkInput("never mind"))
        flow.responseStarted()
        flow.responseFinished(at: start, allowFollowUp: false, session: session)
        #expect(flow.heard("Asistan, saat kaç", at: start.addingTimeInterval(3)) == .runWorkInput("saat kaç"))
        flow.responseStarted()
        flow.responseFinished(at: start, allowFollowUp: false, session: session)
        #expect(flow.heard("Asistan, iptal", at: start.addingTimeInterval(3)) == .returnToIdle(timedOut: false))
        #expect(flow.activeWorkSession == nil)
    }
}

@Suite("ConversationFlow listening shortcut")
struct ConversationFlowShortcutTests {
    let start = Date(timeIntervalSince1970: 1_000)

    func makeFlow() -> ConversationFlow {
        ConversationFlow(matcher: WakePhraseMatcher(phrase: "asistan"), commandTimeout: 6, followUpWindow: 5)
    }

    @Test("the shortcut wakes like the bare wake phrase")
    func wakes() {
        var flow = makeFlow()
        #expect(flow.shortcutPressed(at: start) == .acknowledgeWake)
        #expect(flow.phase == .awaitingCommand(deadline: start.addingTimeInterval(6)))
        #expect(flow.heard("saat kaç", at: start.addingTimeInterval(2)) == .runCommand("saat kaç"))
    }

    @Test("pressing it again while waiting cancels")
    func cancels() {
        var flow = makeFlow()
        _ = flow.shortcutPressed(at: start)
        #expect(flow.shortcutPressed(at: start.addingTimeInterval(1)) == .returnToIdle(timedOut: false))
        #expect(flow.phase == .listeningForWake)
    }

    @Test("in a work session's window it starts a fresh wait outside the session")
    func leavesTheWorkSession() {
        var flow = makeFlow()
        flow.responseStarted()
        flow.responseFinished(at: start, allowFollowUp: true, session: .init(window: 30, accepts: { _ in true }))
        #expect(flow.shortcutPressed(at: start.addingTimeInterval(1)) == .acknowledgeWake)
        #expect(flow.heard("bir sonraki şarkı", at: start.addingTimeInterval(2)) == .runCommand("bir sonraki şarkı"))
    }

    @Test("it changes nothing while the assistant answers")
    func ignoredWhileAnswering() {
        var flow = makeFlow()
        _ = flow.heard("asistan saat kaç", at: start)
        #expect(flow.shortcutPressed(at: start.addingTimeInterval(1)) == .none)
        flow.responseStarted()
        #expect(flow.shortcutPressed(at: start.addingTimeInterval(1)) == .none)
        #expect(flow.phase == .responding)
    }
}
