import os

enum Log {
    private static let subsystem = "com.vrnsoft.asistan"

    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let speech = Logger(subsystem: subsystem, category: "speech")
    static let wake = Logger(subsystem: subsystem, category: "wake")
    static let brain = Logger(subsystem: subsystem, category: "brain")
    static let tools = Logger(subsystem: subsystem, category: "tools")
}
