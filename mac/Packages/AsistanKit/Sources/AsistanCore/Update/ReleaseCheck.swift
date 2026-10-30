import Foundation

/// Whether a newer Bilge has been published on GitHub, the page about it, and the files it comes in. GitHub's
/// "latest" release already leaves drafts and pre-releases out.
public enum ReleaseCheck {
    public struct Asset: Equatable, Codable, Sendable {
        public let name: String
        public let url: URL

        public init(name: String, url: URL) {
            self.name = name
            self.url = url
        }
    }

    public struct Release: Equatable, Codable, Sendable {
        public let version: String
        public let page: URL
        /// Only files under this project's release downloads; empty for a release remembered by an older Bilge.
        public let assets: [Asset]

        public init(version: String, page: URL, assets: [Asset] = []) {
            self.version = version
            self.page = page
            self.assets = assets
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(String.self, forKey: .version)
            page = try container.decode(URL.self, forKey: .page)
            assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
        }

        /// The Mac app's disk image, as the release workflow names it.
        public var macPackage: Asset? { assets.first { $0.name == "Bilge-\(version).dmg" } }
        public var checksums: Asset? { assets.first { $0.name == ReleaseCheck.checksumsName } }
    }

    public enum Failure: Error, Equatable {
        case unexpectedAnswer
        /// A release page outside this project, which is never opened.
        case foreignPage(String)
    }

    public static let repository = "serdarvaran/bilge-assistant"
    public static let latestURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    public static let releasePages = "https://github.com/\(repository)/releases/"
    public static let downloads = "https://github.com/\(repository)/releases/download/"
    public static let checksumsName = "SHA256SUMS"
    public static let interval: TimeInterval = 24 * 60 * 60

    /// "v0.3.0" against "0.2.0"; a pre-release ("0.3.0-rc1") comes before its release.
    public static func isNewer(_ published: String, than running: String) -> Bool {
        guard let remote = Version(published), let local = Version(running) else { return false }
        return remote > local
    }

    public static func latest(from data: Data) throws -> Release {
        struct Answer: Decodable {
            struct File: Decodable {
                let name: String
                let browser_download_url: String
            }
            let tag_name: String
            let html_url: String
            let assets: [File]?
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data), Version(answer.tag_name) != nil,
              let page = URL(string: answer.html_url)
        else { throw Failure.unexpectedAnswer }
        guard isProjectPage(page) else { throw Failure.foreignPage(answer.html_url) }
        let assets = (answer.assets ?? []).compactMap { file in
            URL(string: file.browser_download_url).flatMap { isProjectDownload($0) ? Asset(name: file.name, url: $0) : nil }
        }
        return Release(version: Version.stripped(answer.tag_name), page: page, assets: assets)
    }

    /// The SHA-256 of each file in a `SHA256SUMS` file (`sha256sum` output: "<hex>  <name>", or "<hex> *<name>").
    public static func checksums(in text: String) -> [String: String] {
        var sums: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let hash = parts[0].lowercased()
            let name = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            guard hash.count == 64, hash.allSatisfy(\.isHexDigit), !name.isEmpty else { continue }
            sums[name] = hash
        }
        return sums
    }

    /// Only this project's own release pages are ever opened: https on github.com, under its releases, with no
    /// ".." that a browser would resolve into another repository.
    public static func isProjectPage(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == "https",
              parts.host == "github.com", parts.port == nil, parts.user == nil, parts.password == nil
        else { return false }
        let path = parts.percentEncodedPath.lowercased()
        return url.absoluteString.hasPrefix(releasePages) && !path.contains("..") && !path.contains("%2e")
            && !path.contains("%2f")
    }

    /// Files are only fetched from this project's own release downloads; GitHub then redirects to its file storage.
    public static func isProjectDownload(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == "https",
              parts.host == "github.com", parts.port == nil, parts.user == nil, parts.password == nil
        else { return false }
        let path = parts.percentEncodedPath.lowercased()
        return url.absoluteString.hasPrefix(downloads) && !path.contains("..") && !path.contains("%2e")
            && !path.contains("%2f")
    }

    /// A clock set back makes the last check look like the future; a check is then due.
    public static func isDue(lastChecked: Date?, now: Date) -> Bool {
        guard let lastChecked else { return true }
        return !(lastChecked > now.addingTimeInterval(-interval) && lastChecked <= now)
    }

    struct Version: Comparable {
        let numbers: [Int]
        /// "rc1" of "1.0.0-rc1"; empty for a release.
        let preRelease: String

        static func stripped(_ text: String) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        }

        init?(_ text: String) {
            let body = Self.stripped(text)
            let release = body.prefix { ($0.isASCII && $0.isNumber) || $0 == "." }
            let parts = release.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
            guard !release.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
            numbers = parts.compactMap(\.self)
            preRelease = String(body.dropFirst(release.count)).trimmingCharacters(in: CharacterSet(charactersIn: "-+."))
        }

        static func == (lhs: Version, rhs: Version) -> Bool {
            !(lhs < rhs) && !(rhs < lhs)
        }

        static func < (lhs: Version, rhs: Version) -> Bool {
            let count = max(lhs.numbers.count, rhs.numbers.count)
            let left = lhs.numbers + Array(repeating: 0, count: count - lhs.numbers.count)
            let right = rhs.numbers + Array(repeating: 0, count: count - rhs.numbers.count)
            if left != right { return left.lexicographicallyPrecedes(right) }
            switch (lhs.preRelease.isEmpty, rhs.preRelease.isEmpty) {
            case (true, true), (true, false): return false
            case (false, true): return true
            case (false, false): return lhs.preRelease.compare(rhs.preRelease, options: .numeric) == .orderedAscending
            }
        }
    }
}
