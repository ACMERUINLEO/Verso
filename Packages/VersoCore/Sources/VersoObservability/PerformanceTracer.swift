import OSLog
import VersoApplication

public final class PerformanceTracer: @unchecked Sendable {
    public struct Token: @unchecked Sendable {
        fileprivate let id: OSSignpostID
        fileprivate let operation: DiagnosticOperation
    }

    private let log = OSLog(
        subsystem: "com.acmeruin.verso",
        category: "performance"
    )

    public init() {}

    public func begin(_ operation: DiagnosticOperation) -> Token {
        let id = OSSignpostID(log: log)
        emit(.begin, operation: operation, id: id)
        return Token(id: id, operation: operation)
    }

    public func end(_ token: Token) {
        emit(.end, operation: token.operation, id: token.id)
    }

    private func emit(
        _ type: OSSignpostType,
        operation: DiagnosticOperation,
        id: OSSignpostID
    ) {
        switch operation {
        case .appStartup:
            os_signpost(type, log: log, name: "App Startup", signpostID: id)
        case .databaseMigration:
            os_signpost(type, log: log, name: "Database Migration", signpostID: id)
        case .workspaceOpen:
            os_signpost(type, log: log, name: "Workspace Open", signpostID: id)
        case .workspaceCreate:
            os_signpost(type, log: log, name: "Workspace Create", signpostID: id)
        case .workspaceMutate:
            os_signpost(type, log: log, name: "Workspace Mutate", signpostID: id)
        case .workspaceBackup:
            os_signpost(type, log: log, name: "Workspace Backup", signpostID: id)
        case .workspaceRestore:
            os_signpost(type, log: log, name: "Workspace Restore", signpostID: id)
        case .fileWrite:
            os_signpost(type, log: log, name: "File Write", signpostID: id)
        case .backgroundJob:
            os_signpost(type, log: log, name: "Background Job", signpostID: id)
        case .bundleBuild:
            os_signpost(type, log: log, name: "Bundle Build", signpostID: id)
        case .outputValidation:
            os_signpost(type, log: log, name: "Output Validation", signpostID: id)
        case .outputMerge:
            os_signpost(type, log: log, name: "Output Merge", signpostID: id)
        }
    }
}
