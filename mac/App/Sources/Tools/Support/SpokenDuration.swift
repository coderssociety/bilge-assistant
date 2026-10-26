import Foundation

extension Duration {
    /// "1 saat 5 dakika" / "1 hour, 5 minutes", in the assistant's language.
    var spoken: String {
        formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide).locale(AppLanguage.locale))
    }
}
