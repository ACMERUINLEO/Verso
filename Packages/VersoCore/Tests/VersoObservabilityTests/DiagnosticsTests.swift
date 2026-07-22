import Foundation
import Testing
import VersoApplication
@testable import VersoObservability

@Suite("Diagnostics")
struct DiagnosticsTests {
    @Test("The unified recorder bounds recent errors and preserves correlation")
    func boundedRecentErrors() async {
        let recorder = UnifiedDiagnosticsRecorder(maximumRecentErrors: 2)

        for index in 0..<3 {
            let trace = await recorder.begin(.workspaceOpen)
            await recorder.record(
                ClassifiedError(
                    category: .persistence,
                    operation: DiagnosticOperation.workspaceOpen.rawValue,
                    technicalCode: "error-\(index)",
                    traceID: trace.id
                )
            )
            await recorder.end(trace, outcome: .failure)
        }

        let errors = await recorder.recentErrorsSnapshot()
        #expect(errors.map(\.technicalCode) == ["error-1", "error-2"])
        #expect(errors.allSatisfy { $0.traceID != nil })
    }

    @Test("Diagnostic exports never retain a user-content flag")
    func safeDiagnosticExport() throws {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "VersoDiagnostics-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: destination) }

        let snapshot = DiagnosticSnapshot(
            appVersion: "test",
            schemaVersion: 1,
            recentErrors: [],
            includesUserContent: true
        )
        try DiagnosticsExporter.export(snapshot, to: destination)

        let data = try Data(contentsOf: destination)
        let exported = try JSONDecoder.withISO8601Dates.decode(
            DiagnosticSnapshot.self,
            from: data
        )
        #expect(!exported.includesUserContent)
    }
}

private extension JSONDecoder {
    static var withISO8601Dates: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
