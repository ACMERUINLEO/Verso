import Foundation
import VersoApplication

public struct AtomicWriteRecoveryReport: Equatable, Sendable {
    public let discardedPreparedOperations: Int
    public let finalizedCommittedOperations: Int

    public init(
        discardedPreparedOperations: Int,
        finalizedCommittedOperations: Int
    ) {
        self.discardedPreparedOperations = discardedPreparedOperations
        self.finalizedCommittedOperations = finalizedCommittedOperations
    }
}

public actor AtomicFileWriter {
    private struct Journal: Codable {
        enum State: String, Codable {
            case prepared
            case fileCommitted
        }

        let operationID: UUID
        let targetPath: String
        let temporaryPath: String
        var state: State
    }

    private let recoveryDirectory: URL
    private let failureInjector: any FailureInjecting
    private let diagnostics: any DiagnosticsRecording

    public init(
        recoveryDirectory: URL,
        failureInjector: any FailureInjecting = NoFailureInjector(),
        diagnostics: any DiagnosticsRecording = NoopDiagnosticsRecorder()
    ) {
        self.recoveryDirectory = recoveryDirectory
        self.failureInjector = failureInjector
        self.diagnostics = diagnostics
    }

    public func write(_ data: Data, to targetURL: URL) async throws {
        let trace = await diagnostics.begin(.fileWrite)
        do {
            try await performWrite(data, to: targetURL)
            await diagnostics.end(trace, outcome: .success)
        } catch {
            await diagnostics.record(
                ClassifiedError(
                    category: .fileSystem,
                    operation: DiagnosticOperation.fileWrite.rawValue,
                    technicalCode: String(describing: error),
                    traceID: trace.id
                )
            )
            await diagnostics.end(trace, outcome: .failure)
            throw error
        }
    }

    private func performWrite(_ data: Data, to targetURL: URL) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: recoveryDirectory,
            withIntermediateDirectories: true
        )

        let operationID = UUID()
        let temporaryURL = targetURL.deletingLastPathComponent()
            .appending(path: ".verso-write-\(operationID.uuidString).tmp")
        let journalURL = recoveryDirectory
            .appending(path: "\(operationID.uuidString).json")
        var journal = Journal(
            operationID: operationID,
            targetPath: targetURL.path,
            temporaryPath: temporaryURL.path,
            state: .prepared
        )

        try persist(journal, at: journalURL)
        fileManager.createFile(atPath: temporaryURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporaryURL)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        if await failureInjector.shouldFail(at: .fileWriteBeforeReplace) {
            throw ReliabilityError.injected(.fileWriteBeforeReplace)
        }

        if fileManager.fileExists(atPath: targetURL.path) {
            _ = try fileManager.replaceItemAt(
                targetURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: targetURL)
        }

        journal.state = .fileCommitted
        try persist(journal, at: journalURL)

        if await failureInjector.shouldFail(
            at: .applicationTerminationAfterFileCommit
        ) {
            throw ReliabilityError.injected(.applicationTerminationAfterFileCommit)
        }

        try fileManager.removeItem(at: journalURL)
    }

    public func recoverInterruptedWrites() throws -> AtomicWriteRecoveryReport {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: recoveryDirectory.path) else {
            return AtomicWriteRecoveryReport(
                discardedPreparedOperations: 0,
                finalizedCommittedOperations: 0
            )
        }

        let journalURLs = try fileManager.contentsOfDirectory(
            at: recoveryDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        var discarded = 0
        var finalized = 0
        for journalURL in journalURLs {
            let data = try Data(contentsOf: journalURL)
            let journal = try JSONDecoder().decode(Journal.self, from: data)
            let temporaryURL = URL(filePath: journal.temporaryPath)

            switch journal.state {
            case .prepared:
                if fileManager.fileExists(atPath: temporaryURL.path) {
                    try fileManager.removeItem(at: temporaryURL)
                }
                discarded += 1
            case .fileCommitted:
                finalized += 1
            }

            try fileManager.removeItem(at: journalURL)
        }

        return AtomicWriteRecoveryReport(
            discardedPreparedOperations: discarded,
            finalizedCommittedOperations: finalized
        )
    }

    private func persist(_ journal: Journal, at url: URL) throws {
        let data = try JSONEncoder().encode(journal)
        try data.write(to: url, options: .atomic)
    }
}
