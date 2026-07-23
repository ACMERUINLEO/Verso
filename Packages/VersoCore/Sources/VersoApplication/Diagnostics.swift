import Foundation

public enum DiagnosticOperation: String, Codable, CaseIterable, Sendable {
    case appStartup = "app.startup"
    case databaseMigration = "database.migration"
    case workspaceCreate = "workspace.create"
    case workspaceMutate = "workspace.mutate"
    case workspaceOpen = "workspace.open"
    case workspaceBackup = "workspace.backup"
    case workspaceRestore = "workspace.restore"
    case fileWrite = "file.write"
    case backgroundJob = "job.run"
    case bundleBuild = "bundle.build"
    case outputValidation = "output.validation"
    case outputMerge = "output.merge"
}

public enum DiagnosticOutcome: String, Codable, Sendable {
    case success
    case failure
}

public enum ErrorCategory: String, Codable, CaseIterable, Sendable {
    case validation
    case permission
    case persistence
    case corruption
    case fileSystem
    case network
    case cancelled
    case invariantViolation
    case unknown
}

public struct ClassifiedError: Codable, Equatable, Sendable {
    public let category: ErrorCategory
    public let operation: String
    public let technicalCode: String
    public let occurredAt: Date
    public let traceID: UUID?

    public init(
        category: ErrorCategory,
        operation: String,
        technicalCode: String,
        occurredAt: Date = Date(),
        traceID: UUID? = nil
    ) {
        self.category = category
        self.operation = operation
        self.technicalCode = technicalCode
        self.occurredAt = occurredAt
        self.traceID = traceID
    }
}

public struct DiagnosticTrace: Hashable, Sendable {
    public let id: UUID
    public let operation: DiagnosticOperation

    public init(
        id: UUID = UUID(),
        operation: DiagnosticOperation
    ) {
        self.id = id
        self.operation = operation
    }
}

public protocol DiagnosticsRecording: Sendable {
    func begin(_ operation: DiagnosticOperation) async -> DiagnosticTrace
    func end(_ trace: DiagnosticTrace, outcome: DiagnosticOutcome) async
    func record(_ error: ClassifiedError) async
}

public struct NoopDiagnosticsRecorder: DiagnosticsRecording {
    public init() {}

    public func begin(_ operation: DiagnosticOperation) async -> DiagnosticTrace {
        DiagnosticTrace(operation: operation)
    }

    public func end(
        _ trace: DiagnosticTrace,
        outcome: DiagnosticOutcome
    ) async {}

    public func record(_ error: ClassifiedError) async {}
}
