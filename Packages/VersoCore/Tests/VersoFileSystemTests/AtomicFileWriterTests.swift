import Foundation
import Testing
import VersoApplication
@testable import VersoFileSystem

@Suite("Atomic file writes")
struct AtomicFileWriterTests {
    @Test("Failure before replacement preserves the old file")
    func replacementFailurePreservesOldFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "VersoAtomicWrite-\(UUID().uuidString)")
        let target = root.appending(path: "note.md")
        let recovery = root.appending(path: "Recovery")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: target)
        defer { try? FileManager.default.removeItem(at: root) }

        let injector = OneShotFailureInjector(points: [.fileWriteBeforeReplace])
        let diagnostics = FileRecordingDiagnostics()
        let writer = AtomicFileWriter(
            recoveryDirectory: recovery,
            failureInjector: injector,
            diagnostics: diagnostics
        )

        await #expect(
            throws: ReliabilityError.injected(.fileWriteBeforeReplace)
        ) {
            try await writer.write(Data("new".utf8), to: target)
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "old")

        let report = try await writer.recoverInterruptedWrites()
        #expect(report.discardedPreparedOperations == 1)
        #expect(try String(contentsOf: target, encoding: .utf8) == "old")
        let diagnosticSnapshot = await diagnostics.snapshot()
        #expect(diagnosticSnapshot.operations == [.fileWrite])
        #expect(diagnosticSnapshot.outcomes == [.failure])
        #expect(diagnosticSnapshot.errorCategories == [.fileSystem])
    }

    @Test("Recovery finalizes a write interrupted after file commit")
    func recoveryFinalizesCommittedWrite() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "VersoAtomicWrite-\(UUID().uuidString)")
        let target = root.appending(path: "note.md")
        let recovery = root.appending(path: "Recovery")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let injector = OneShotFailureInjector(
            points: [.applicationTerminationAfterFileCommit]
        )
        let writer = AtomicFileWriter(
            recoveryDirectory: recovery,
            failureInjector: injector
        )

        await #expect(
            throws: ReliabilityError.injected(.applicationTerminationAfterFileCommit)
        ) {
            try await writer.write(Data("committed".utf8), to: target)
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "committed")

        let report = try await writer.recoverInterruptedWrites()
        #expect(report.finalizedCommittedOperations == 1)
    }
}

private actor FileRecordingDiagnostics: DiagnosticsRecording {
    private var operations: [DiagnosticOperation] = []
    private var outcomes: [DiagnosticOutcome] = []
    private var errors: [ClassifiedError] = []

    func begin(_ operation: DiagnosticOperation) -> DiagnosticTrace {
        operations.append(operation)
        return DiagnosticTrace(operation: operation)
    }

    func end(_ trace: DiagnosticTrace, outcome: DiagnosticOutcome) {
        outcomes.append(outcome)
    }

    func record(_ error: ClassifiedError) {
        errors.append(error)
    }

    func snapshot() -> (
        operations: [DiagnosticOperation],
        outcomes: [DiagnosticOutcome],
        errorCategories: [ErrorCategory]
    ) {
        (operations, outcomes, errors.map(\.category))
    }
}
