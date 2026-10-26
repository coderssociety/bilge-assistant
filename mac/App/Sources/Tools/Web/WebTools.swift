import AppKit
import FoundationModels

/// Opens a search in the default browser for the user to read; the results are never read back.
struct WebSearchTool: AssistantTool {
    let name = "searchWeb"
    let description = "Kullanıcı açıkça aramamı istediğinde ('Google\'da ara', 'YouTube\'da bul') tarayıcıda arama sayfasını açar. Soruları yanıtlamak için kullanılmaz."

    @Generable
    enum Service {
        case google, youtube, maps, wikipedia
    }

    @Generable
    struct Arguments {
        @Guide(description: "Aranacak ifade")
        var query: String
        @Guide(description: "Arama yapılacak servis")
        var service: Service
    }

    func call(arguments: Arguments) async throws -> String {
        var components: URLComponents
        switch arguments.service {
        case .google:
            components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: arguments.query)]
        case .youtube:
            components = URLComponents(string: "https://www.youtube.com/results")!
            components.queryItems = [URLQueryItem(name: "search_query", value: arguments.query)]
        case .maps:
            components = URLComponents(string: "https://maps.apple.com/")!
            components.queryItems = [URLQueryItem(name: "q", value: arguments.query)]
        case .wikipedia:
            components = URLComponents(string: "https://\(AppLanguage.current.code).wikipedia.org/w/index.php")!
            components.queryItems = [URLQueryItem(name: "search", value: arguments.query)]
        }
        guard let url = components.url else {
            return ToolReply.failure(String(localized: "Arama adresi oluşturulamadı."))
        }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        return opened
            ? String(localized: "Tarayıcıda '\(arguments.query)' araması açıldı.")
            : ToolReply.failure(String(localized: "Tarayıcı açılamadı."))
    }
}

struct OpenWebsiteTool: AssistantTool {
    let name = "openWebsite"
    let description = "Bilinen bir web sitesini tarayıcıda açar. Örnek: 'github.com', 'sahibinden.com'."

    @Generable
    struct Arguments {
        @Guide(description: "Alan adı veya tam adres, örn. 'github.com'")
        var address: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let url = Self.webURL(from: arguments.address) else {
            return ToolReply.failure(String(localized: "'\(arguments.address)' geçerli bir web adresi değil."))
        }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        let host = url.host() ?? arguments.address
        return opened ? String(localized: "\(host) açıldı.") : ToolReply.failure(String(localized: "Tarayıcı açılamadı."))
    }

    /// Only http(s) URLs with a host; blocks file:, javascript: and custom schemes.
    static func webURL(from address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = url.host(), host.contains(".")
        else { return nil }
        return url
    }
}
