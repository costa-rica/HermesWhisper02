import OSLog

enum AppLog {
    static let subsystem = "com.dashanddata.hw02"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let voice = Logger(subsystem: subsystem, category: "voice")
}
