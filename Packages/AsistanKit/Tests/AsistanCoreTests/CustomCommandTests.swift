import Testing
@testable import AsistanCore

@Suite("CustomCommandRequest")
struct CustomCommandRequestTests {
    @Test("finds the name in a Turkish run request", arguments: [
        ("yedekleme komutunu çalıştır", "yedekleme"),
        ("Bilge lütfen sunucuyu kapat komutunu çalıştır", "sunucuyu kapat"),
        ("“Yedek” komutunu başlat", "Yedek"),
    ])
    func turkishRun(command: String, name: String) {
        #expect(CustomCommandRequest.runName(in: command, language: .turkish) == name)
    }

    @Test("other Turkish requests name no command", arguments: ["komutunu çalıştır", "Safari'yi aç", "yedekleme kestirmesini çalıştır"])
    func turkishOther(command: String) {
        #expect(CustomCommandRequest.runName(in: command, language: .turkish) == nil)
    }

    @Test("finds the name in an English run request")
    func englishRun() {
        #expect(CustomCommandRequest.runName(in: "Run the backup command", language: .english) == "backup")
        #expect(CustomCommandRequest.runName(in: "start my deploy site command please", language: .english) == "deploy site")
        #expect(CustomCommandRequest.runName(in: "run the backup", language: .english) == nil)
    }

    @Test("asks for the user's own commands only")
    func list() {
        #expect(CustomCommandRequest.asksForList("komutlarım neler", language: .turkish))
        #expect(CustomCommandRequest.asksForList("hangi komutlarım var", language: .turkish))
        #expect(!CustomCommandRequest.asksForList("hangi komutları biliyorsun", language: .turkish))
        #expect(CustomCommandRequest.asksForList("what are my commands", language: .english))
        #expect(!CustomCommandRequest.asksForList("what commands do you know", language: .english))
    }

    @Test("matches a configured name with suffixes and the command word")
    func matching() {
        let names = ["Yedekleme", "Sunucuyu kapat"]
        #expect(CustomCommandRequest.bestMatch("yedeklemeyi", in: names) == "Yedekleme")
        #expect(CustomCommandRequest.bestMatch("sunucuyu kapat komutu", in: names) == "Sunucuyu kapat")
        #expect(CustomCommandRequest.bestMatch("müzik", in: names) == nil)
        #expect(CustomCommandRequest.namesExactly("yedekleme komutunu", name: "Yedekleme", names: names))
        #expect(!CustomCommandRequest.namesExactly("sunucu", name: "Sunucuyu kapat", names: names))
    }
}

@Suite("CustomCommand")
struct CustomCommandTests {
    @Test("an edited command gets a new fingerprint, the same command keeps it")
    func fingerprint() {
        let command = CustomCommand(name: "yedek", arguments: ["rsync", "-a", "~/Belgeler", "/Volumes/Yedek"])
        var renamed = command
        renamed.name = "yedekle"
        var changed = command
        changed.arguments[1] = "-av"
        #expect(command.fingerprint == CustomCommand(name: "yedek", arguments: command.arguments).fingerprint)
        #expect(command.fingerprint != renamed.fingerprint)
        #expect(command.fingerprint != changed.fingerprint)
        #expect(command.fingerprint.count == 64)
    }
}

@Suite("CommandLineText")
struct CommandLineTextTests {
    @Test("splits words, quotes and escapes like a shell", arguments: [
        ("rsync -a ~/Documents /Volumes/Backup", ["rsync", "-a", "~/Documents", "/Volumes/Backup"]),
        ("open \"/Users/ayşe/Belge Klasörü\"", ["open", "/Users/ayşe/Belge Klasörü"]),
        ("echo 'a \"b\"' c\\ d", ["echo", "a \"b\"", "c d"]),
        ("say \"\"", ["say", ""]),
        ("  ls   -l  ", ["ls", "-l"]),
    ])
    func split(line: String, words: [String]) throws {
        #expect(try CommandLineText.split(line) == words)
    }

    @Test("a tilde is shown as typed, not quoted")
    func tilde() {
        #expect(CommandLineText.join(["rsync", "-a", "~/Documents", "/Volumes/Backup"]) == "rsync -a ~/Documents /Volumes/Backup")
    }

    @Test("an unclosed quote is refused")
    func unclosed() {
        #expect(throws: CommandLineText.SplitError.unclosedQuote) { try CommandLineText.split("echo 'merhaba") }
    }

    @Test("joining gives back the same words", arguments: [
        ["rsync", "-a", "~/Documents"], ["open", "/Users/ayşe/Belge Klasörü"], ["echo", "it's", ""], ["say", "a;b"],
    ])
    func roundTrip(words: [String]) throws {
        #expect(try CommandLineText.split(CommandLineText.join(words)) == words)
    }
}
