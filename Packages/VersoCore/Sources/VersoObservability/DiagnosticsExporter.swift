import Foundation
import VersoApplication

public struct DiagnosticSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let appVersion: String
    public let schemaVersion: Int?
    public let recentErrors: [ClassifiedError]
    public let includesUserContent: Bool

    public init(
        generatedAt: Date = Date(),
        appVersion: String,
        schemaVersion: Int?,
        recentErrors: [ClassifiedError],
        includesUserContent: Bool = false
    ) {
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.schemaVersion = schemaVersion
        self.recentErrors = recentErrors
        self.includesUserContent = includesUserContent
    }
}

public enum DiagnosticsExporter {
    public static func export(
        _ snapshot: DiagnosticSnapshot,
        to destination: URL
    ) throws {
        var safeSnapshot = snapshot
        if snapshot.includesUserContent {
            safeSnapshot = DiagnosticSnapshot(
                generatedAt: snapshot.generatedAt,
                appVersion: snapshot.appVersion,
                schemaVersion: snapshot.schemaVersion,
                recentErrors: snapshot.recentErrors,
                includesUserContent: false
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(safeSnapshot).write(to: destination, options: .atomic)
    }
}
