import OSLog
import VersoApplication

public enum LogCategory: String, Sendable {
    case lifecycle
    case persistence
    case fileSystem
    case jobs
    case performance
    case diagnostics
}

public struct VersoLogger: Sendable {
    private let logger: Logger

    public init(category: LogCategory) {
        logger = Logger(
            subsystem: "com.acmeruin.verso",
            category: category.rawValue
        )
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    public func error(_ error: ClassifiedError) {
        logger.error(
            "category=\(error.category.rawValue, privacy: .public) operation=\(error.operation, privacy: .public) trace=\(error.traceID?.uuidString ?? "none", privacy: .public) code=\(error.technicalCode, privacy: .private(mask: .hash))"
        )
    }
}
