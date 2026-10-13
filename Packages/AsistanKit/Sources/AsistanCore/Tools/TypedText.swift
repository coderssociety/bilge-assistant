/// Text that is safe to type as key events: control characters (Return, Tab, Escape, line and
/// paragraph separators…) would act as keys and could submit a form or a message.
public enum TypedText {
    public static func sanitized(_ text: String) -> String {
        let scalars = text.unicodeScalars.map { scalar -> Unicode.Scalar in
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: " "
            default: scalar
            }
        }
        return String(String.UnicodeScalarView(scalars)).split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}
