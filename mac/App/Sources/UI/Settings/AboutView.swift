import AsistanCore
import SwiftUI

/// Version, license and the notices that GPL-3.0 and the bundled components require to ship with the app.
struct AboutView: View {
    private static let noticesFile = "THIRD_PARTY_NOTICES"

    /// Split into paragraphs: the file is over 100 KB, too much for a single text view to lay out quickly.
    private let paragraphs: [String] = {
        guard let url = Bundle.main.url(forResource: noticesFile, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [String(localized: "Lisans bildirimleri bulunamadı.")] }
        return text.components(separatedBy: "\n\n")
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 44, height: 44)
                Text(AppIdentity.name).font(.title2.bold())
                Text("Sürüm \(Self.version)").foregroundStyle(.secondary)
            }
            Text("\(AppIdentity.name) özgür yazılımdır: GNU GPL 3.0 koşullarıyla kullanabilir, değiştirebilir ve dağıtabilirsin. Hiçbir garanti verilmez.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("Kullanılan açık kaynak bileşenler ve modeller").font(.headline).padding(.top, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(paragraphs.indices, id: \.self) { index in
                        Text(paragraphs[index])
                    }
                }
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
        }
        .padding(20)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
