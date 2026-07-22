import Foundation
import GRDB
import Testing
import VersoApplication
import VersoDomain
@testable import VersoPersistence

@Suite("Workspace lifecycle")
struct WorkspaceLifecycleTests {
    @Test("An empty workspace can be created, closed, and reopened")
    func createCloseReopen() async throws {
        let root = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = WorkspaceLocation(rawValue: root.path)
        let service = WorkspaceLifecycleService()

        let created = try await service.createWorkspace(name: "Test", at: location)
        #expect(created.lifecycleState == .active)
        #expect(created.revision == 1)
        #expect(try await service.pendingOutboxJobCount(for: created.id) == 1)
        #expect(try await service.pendingSyncChangeCount(for: created.id) == 1)

        let closed = try await service.closeWorkspace(id: created.id)
        #expect(closed.lifecycleState == .closed)

        let outcome = await service.openWorkspace(at: location)
        guard case let .ready(reopened) = outcome else {
            Issue.record("Expected the workspace to reopen")
            return
        }
        #expect(reopened.id == created.id)
        #expect(reopened.rootNodeID == created.rootNodeID)
        #expect(reopened.lifecycleState == .active)
        #expect(reopened.revision == created.revision)
        #expect(reopened.modifiedAt == created.modifiedAt)
        #expect(try await service.pendingSyncChangeCount(for: reopened.id) == 1)
    }

    @Test("Workspace commands atomically append provider-neutral sync changes")
    func workspaceSyncOutbox() async throws {
        let root = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let deviceID = DeviceID()
        let service = WorkspaceLifecycleService(deviceID: deviceID)
        let workspace = try await service.createWorkspace(
            name: "Sync Baseline",
            at: WorkspaceLocation(rawValue: root.path)
        )
        let operationID = OperationID()

        let first = try await service.renameWorkspace(
            id: workspace.id,
            to: "Renamed Once",
            expectedRevision: workspace.revision,
            operationID: operationID
        )
        let replay = try await service.renameWorkspace(
            id: workspace.id,
            to: "Renamed Once",
            expectedRevision: workspace.revision,
            operationID: operationID
        )

        #expect(first.disposition == .applied)
        #expect(first.workspace.revision == 2)
        #expect(replay.disposition == .replayed)
        #expect(replay.workspace == first.workspace)

        let records = try await service.syncOutboxRecords(for: workspace.id)
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.sourceDeviceID == deviceID })
        #expect(records.last?.change.operationID == operationID)
        #expect(records.last?.change.baseRevision == 1)
        #expect(records.last?.change.revision == 2)

        guard let payload = records.last?.change.payload else {
            Issue.record("Expected a sync payload")
            return
        }
        let decoded = try JSONDecoder().decode(
            WorkspaceSyncPayload.self,
            from: payload
        )
        #expect(decoded.name == "Renamed Once")
        #expect(decoded.revision == 2)

        let serialized = String(decoding: payload, as: UTF8.self).lowercased()
        #expect(!serialized.contains("bookmark"))
        #expect(!serialized.contains(root.path.lowercased()))
        #expect(!serialized.contains("api_key"))
        #expect(!serialized.contains("credential"))
    }

    @Test("Workspace creation replays the same operation without duplicate facts")
    func idempotentWorkspaceCreation() async throws {
        let root = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = WorkspaceLocation(rawValue: root.path)
        let deviceID = DeviceID()
        let operationID = OperationID()
        let firstService = WorkspaceLifecycleService(deviceID: deviceID)

        let first = try await firstService.createWorkspace(
            name: "Create Once",
            at: location,
            operationID: operationID
        )
        _ = try await firstService.closeWorkspace(id: first.id)

        let retryService = WorkspaceLifecycleService(deviceID: deviceID)
        let replay = try await retryService.createWorkspace(
            name: "Create Once",
            at: location,
            operationID: operationID
        )

        #expect(replay.id == first.id)
        #expect(replay.rootNodeID == first.rootNodeID)
        #expect(try await retryService.pendingSyncChangeCount(for: replay.id) == 1)

        await #expect(throws: PersistenceError.operationIDConflict(operationID)) {
            try await retryService.createWorkspace(
                name: "Different Creation",
                at: location,
                operationID: operationID
            )
        }
        #expect(try await retryService.pendingSyncChangeCount(for: replay.id) == 1)
    }

    @Test("Reusing an operation ID for another intent fails closed")
    func operationIDConflict() async throws {
        let root = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceLifecycleService()
        let workspace = try await service.createWorkspace(
            name: "Conflict",
            at: WorkspaceLocation(rawValue: root.path)
        )
        let operationID = OperationID()
        _ = try await service.renameWorkspace(
            id: workspace.id,
            to: "First Intent",
            expectedRevision: 1,
            operationID: operationID
        )

        await #expect(throws: PersistenceError.operationIDConflict(operationID)) {
            try await service.renameWorkspace(
                id: workspace.id,
                to: "Different Intent",
                expectedRevision: 1,
                operationID: operationID
            )
        }
        #expect(try await service.pendingSyncChangeCount(for: workspace.id) == 2)
    }

    @Test("A stale revision cannot overwrite a newer workspace fact")
    func revisionConflict() async throws {
        let root = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceLifecycleService()
        let workspace = try await service.createWorkspace(
            name: "Revision",
            at: WorkspaceLocation(rawValue: root.path)
        )

        await #expect(
            throws: PersistenceError.revisionConflict(expected: 0, actual: 1)
        ) {
            try await service.renameWorkspace(
                id: workspace.id,
                to: "Stale Write",
                expectedRevision: 0,
                operationID: OperationID()
            )
        }
        #expect(try await service.pendingSyncChangeCount(for: workspace.id) == 1)
    }

    @Test("A failed mutation rolls back both the fact and sync outbox")
    func syncMutationRollbackAndRetry() async throws {
        let root = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = WorkspaceLocation(rawValue: root.path)
        let setupService = WorkspaceLifecycleService()
        let workspace = try await setupService.createWorkspace(
            name: "Before Failure",
            at: location
        )
        _ = try await setupService.closeWorkspace(id: workspace.id)

        let service = WorkspaceLifecycleService(
            failureInjector: OneShotFailureInjector(
                points: [.databaseTransactionBeforeCommit]
            )
        )
        guard case .ready = await service.openWorkspace(at: location) else {
            Issue.record("Expected the workspace to open")
            return
        }
        let operationID = OperationID()

        await #expect(
            throws: ReliabilityError.injected(.databaseTransactionBeforeCommit)
        ) {
            try await service.renameWorkspace(
                id: workspace.id,
                to: "After Retry",
                expectedRevision: 1,
                operationID: operationID
            )
        }
        #expect(try await service.pendingSyncChangeCount(for: workspace.id) == 1)

        let retry = try await service.renameWorkspace(
            id: workspace.id,
            to: "After Retry",
            expectedRevision: 1,
            operationID: operationID
        )
        #expect(retry.disposition == .applied)
        #expect(retry.workspace.name == "After Retry")
        #expect(retry.workspace.revision == 2)
        #expect(try await service.pendingSyncChangeCount(for: workspace.id) == 2)
    }

    @Test("Workspace creation, migration, and opening share diagnostic traces")
    func workspaceDiagnostics() async throws {
        let root = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let diagnostics = PersistenceRecordingDiagnostics()
        let service = WorkspaceLifecycleService(diagnostics: diagnostics)
        let location = WorkspaceLocation(rawValue: root.path)

        let workspace = try await service.createWorkspace(
            name: "Diagnostics",
            at: location
        )
        _ = try await service.closeWorkspace(id: workspace.id)
        _ = await service.openWorkspace(at: location)

        let snapshot = await diagnostics.snapshot()
        #expect(snapshot.operations.contains(.workspaceCreate))
        #expect(snapshot.operations.contains(.databaseMigration))
        #expect(snapshot.operations.contains(.workspaceOpen))
        #expect(snapshot.outcomes.allSatisfy { $0 == .success })
        #expect(snapshot.errorCount == 0)
    }

    @Test("A transaction failure leaves no partial workspace facts")
    func transactionRollback() async throws {
        let root = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = WorkspaceLocation(rawValue: root.path)
        let injector = OneShotFailureInjector(
            points: [.databaseTransactionBeforeCommit]
        )
        let service = WorkspaceLifecycleService(failureInjector: injector)

        await #expect(
            throws: ReliabilityError.injected(.databaseTransactionBeforeCommit)
        ) {
            try await service.createWorkspace(name: "Interrupted", at: location)
        }

        let retryService = WorkspaceLifecycleService()
        let workspace = try await retryService.createWorkspace(
            name: "Recovered",
            at: location
        )
        #expect(workspace.name == "Recovered")
    }

    @Test("A corrupt database enters recovery and restores from backup")
    func corruptDatabaseRecovery() async throws {
        let root = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = WorkspaceLocation(rawValue: root.path)
        let service = WorkspaceLifecycleService()

        let workspace = try await service.createWorkspace(name: "Backup", at: location)
        let backup = try await service.createBackup(workspaceID: workspace.id)
        _ = try await service.closeWorkspace(id: workspace.id)
        try Data("not a sqlite database".utf8).write(
            to: WorkspaceLayout(root: root).database
        )

        let recoveryOutcome = await service.openWorkspace(at: location)
        guard case let .recoveryRequired(context) = recoveryOutcome else {
            Issue.record("Expected read-only recovery mode")
            return
        }
        let backupName = URL(filePath: backup.rawValue).lastPathComponent
        #expect(
            context.backupLocations.contains {
                URL(filePath: $0.rawValue).lastPathComponent == backupName
            }
        )

        let restoredOutcome = try await service.restoreWorkspace(
            at: location,
            from: backup
        )
        guard case let .ready(restored) = restoredOutcome else {
            Issue.record("Expected the restored workspace to open")
            return
        }
        #expect(restored.id == workspace.id)

        let protectionBackups = try FileManager.default.contentsOfDirectory(
            at: WorkspaceLayout(root: root).backups,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("pre-restore-") }
        #expect(protectionBackups.count == 1)
        #expect(
            try Data(contentsOf: protectionBackups[0])
                == Data("not a sqlite database".utf8)
        )
    }

    private func temporaryWorkspaceURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "VersoWorkspace-\(UUID().uuidString)")
    }

    @Test("New workspaces keep metadata hidden and use the selected folder as content")
    func hiddenMetadataLayout() async throws {
        let root = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceLifecycleService()

        let workspace = try await service.createWorkspace(
            name: "Hidden Metadata",
            at: WorkspaceLocation(rawValue: root.path)
        )
        let layout = WorkspaceLayout(root: root)

        #expect(layout.metadataRoot.lastPathComponent == ".verso")
        #expect(layout.documents == layout.root)
        #expect(FileManager.default.fileExists(atPath: layout.database.path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "workspace.sqlite").path))

        _ = try await service.closeWorkspace(id: workspace.id)
    }

    @Test("Legacy root metadata workspaces remain openable")
    func legacyLayoutCompatibility() async throws {
        let root = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try Data().write(to: root.appending(path: "workspace.sqlite"))

        let location = WorkspaceLocation(rawValue: root.path)
        let service = WorkspaceLifecycleService()
        let workspace = try await service.createWorkspace(
            name: "Legacy",
            at: location
        )
        let layout = WorkspaceLayout(root: root)

        #expect(layout.metadataRoot == layout.root)
        #expect(layout.documents.lastPathComponent == "Documents")
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".verso").path))

        _ = try await service.closeWorkspace(id: workspace.id)
        let outcome = await service.openWorkspace(at: location)
        guard case let .ready(reopened) = outcome else {
            Issue.record("Expected the legacy workspace to reopen")
            return
        }
        #expect(reopened.id == workspace.id)
    }

    @Test(
        "Published schema snapshots remain compatible",
        arguments: [
            ("schema-v1-active", "Fixture Active", 1, 1, 0),
            ("schema-v1-closed", "Fixture Closed", 0, 1, 0),
            ("schema-v2-synced", "Fixture Synced", 0, 3, 1)
        ]
    )
    func schemaFixtureCompatibility(
        fixtureName: String,
        expectedName: String,
        expectedPendingJobs: Int,
        expectedRevision: Int64,
        expectedSyncChanges: Int
    ) async throws {
        let root = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: root) }
        try installFixture(named: fixtureName, at: root)

        let service = WorkspaceLifecycleService()
        let outcome = await service.openWorkspace(
            at: WorkspaceLocation(rawValue: root.path)
        )
        guard case let .ready(workspace) = outcome else {
            Issue.record("Expected fixture \(fixtureName) to open")
            return
        }

        #expect(workspace.name == expectedName)
        #expect(workspace.schemaVersion == DatabaseSchema.currentVersion)
        #expect(workspace.revision == expectedRevision)
        #expect(workspace.lifecycleState == .active)
        #expect(
            try await service.pendingOutboxJobCount(for: workspace.id)
                == expectedPendingJobs
        )
        #expect(
            try await service.pendingSyncChangeCount(for: workspace.id)
                == expectedSyncChanges
        )
        let migrationBackup = WorkspaceLayout(root: root).backups
            .appending(path: "pre-migration-v2.sqlite")
        #expect(
            FileManager.default.fileExists(atPath: migrationBackup.path)
                == fixtureName.hasPrefix("schema-v1-")
        )
    }

    @Test("Regular backup retention keeps only the configured newest backups")
    func backupRetention() async throws {
        let root = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let policy = BackupPolicy(
            maximumRegularBackups: 2,
            minimumFreeSpaceReserveBytes: 0
        )
        let service = WorkspaceLifecycleService(
            backupPolicy: policy,
            diskCapacityProvider: FixedDiskCapacityProvider(
                availableBytes: Int64.max
            )
        )
        let workspace = try await service.createWorkspace(
            name: "Retention",
            at: WorkspaceLocation(rawValue: root.path)
        )

        for _ in 0..<3 {
            _ = try await service.createBackup(workspaceID: workspace.id)
        }

        let regularBackups = try FileManager.default.contentsOfDirectory(
            at: WorkspaceLayout(root: root).backups,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("workspace-") }
        #expect(regularBackups.count == 2)
    }

    @Test("Backup creation fails before writing when disk capacity is insufficient")
    func backupDiskSpacePreflight() async throws {
        let root = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceLifecycleService(
            backupPolicy: BackupPolicy(
                maximumRegularBackups: 2,
                minimumFreeSpaceReserveBytes: 1
            ),
            diskCapacityProvider: FixedDiskCapacityProvider(
                availableBytes: 0
            )
        )
        let workspace = try await service.createWorkspace(
            name: "No Space",
            at: WorkspaceLocation(rawValue: root.path)
        )

        do {
            _ = try await service.createBackup(workspaceID: workspace.id)
            Issue.record("Expected backup preflight to reject insufficient space")
        } catch {
            guard let persistenceError = error as? VersoPersistence.PersistenceError else {
                throw error
            }
            switch persistenceError {
            case let .insufficientDiskSpace(requiredBytes, availableBytes):
                #expect(requiredBytes > 0)
                #expect(availableBytes == 0)
            default:
                throw persistenceError
            }
        }

        let regularBackups = try FileManager.default.contentsOfDirectory(
            at: WorkspaceLayout(root: root).backups,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("workspace-") }
        #expect(regularBackups.isEmpty)
    }

    private func installFixture(named name: String, at root: URL) throws {
        guard let fixtureURL = Bundle.module.url(
            forResource: name,
            withExtension: "sql"
        ) else {
            throw FixtureError.missing(name)
        }
        let sql = try String(contentsOf: fixtureURL, encoding: .utf8)
        let layout = WorkspaceLayout(root: root)
        try layout.createDirectories()
        let queue = try DatabaseQueue(path: layout.database.path)
        try queue.writeWithoutTransaction { database in
            try database.execute(sql: sql)
        }
    }

    private enum FixtureError: Error {
        case missing(String)
    }
}

private struct FixedDiskCapacityProvider: DiskCapacityProviding {
    let availableBytes: Int64?

    func availableCapacity(at url: URL) throws -> Int64? {
        availableBytes
    }
}

private actor PersistenceRecordingDiagnostics: DiagnosticsRecording {
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
        errorCount: Int
    ) {
        (operations, outcomes, errors.count)
    }
}
