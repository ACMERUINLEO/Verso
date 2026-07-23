import Foundation
import VersoApplication
import VersoDomain
import VersoSyncProtocol

public actor WorkspaceLifecycleService: WorkspaceLifecycleServicing {
    var sessions: [WorkspaceID: WorkspaceDatabase] = [:]
    let failureInjector: any FailureInjecting
    private let backupPolicy: BackupPolicy
    private let diskCapacityProvider: any DiskCapacityProviding
    let diagnostics: any DiagnosticsRecording
    let deviceID: DeviceID

    public init(
        deviceID: DeviceID = DeviceID(),
        failureInjector: any FailureInjecting = NoFailureInjector(),
        backupPolicy: BackupPolicy = BackupPolicy(),
        diskCapacityProvider: any DiskCapacityProviding = VolumeDiskCapacityProvider(),
        diagnostics: any DiagnosticsRecording = NoopDiagnosticsRecorder()
    ) {
        self.deviceID = deviceID
        self.failureInjector = failureInjector
        self.backupPolicy = backupPolicy
        self.diskCapacityProvider = diskCapacityProvider
        self.diagnostics = diagnostics
    }

    public func createWorkspace(
        name: String,
        at location: WorkspaceLocation
    ) async throws -> Workspace {
        try await createWorkspace(
            name: name,
            at: location,
            operationID: OperationID()
        )
    }

    public func createWorkspace(
        name: String,
        at location: WorkspaceLocation,
        operationID: OperationID
    ) async throws -> Workspace {
        let trace = await diagnostics.begin(.workspaceCreate)
        do {
            let layout = WorkspaceLayout(root: URL(filePath: location.rawValue))
            try layout.createDirectories()
            let database = try WorkspaceDatabase(layout: layout)
            try await prepareSchemaWithDiagnostics(database)
            let workspace = try Workspace.create(
                name: name,
                schemaVersion: DatabaseSchema.currentVersion
            )
            let shouldFail = await failureInjector.shouldFail(
                at: .databaseTransactionBeforeCommit
            )
            _ = try database.insertInitialWorkspace(
                workspace,
                operationID: operationID,
                sourceDeviceID: deviceID,
                failBeforeCommit: shouldFail
            )
            try database.verifyIntegrity()
            let resolvedWorkspace = try database.fetchWorkspace()
            sessions[resolvedWorkspace.id] = database
            await diagnostics.end(trace, outcome: .success)
            return resolvedWorkspace
        } catch {
            await recordFailure(error, trace: trace, category: .persistence)
            throw error
        }
    }

    public func renameWorkspace(
        id: WorkspaceID,
        to name: String,
        expectedRevision: Int64,
        operationID: OperationID
    ) async throws -> WorkspaceMutationResult {
        let trace = await diagnostics.begin(.workspaceMutate)
        do {
            guard let database = sessions[id] else {
                throw PersistenceError.workspaceNotOpen
            }
            let shouldFail = await failureInjector.shouldFail(
                at: .databaseTransactionBeforeCommit
            )
            let result = try database.renameWorkspace(
                id: id,
                to: name,
                expectedRevision: expectedRevision,
                operationID: operationID,
                sourceDeviceID: deviceID,
                failBeforeCommit: shouldFail
            )
            await diagnostics.end(trace, outcome: .success)
            return result
        } catch {
            await recordFailure(error, trace: trace, category: .persistence)
            throw error
        }
    }

    public func openWorkspace(
        at location: WorkspaceLocation
    ) async -> WorkspaceOpenOutcome {
        let trace = await diagnostics.begin(.workspaceOpen)
        let layout = WorkspaceLayout(root: URL(filePath: location.rawValue))
        guard FileManager.default.fileExists(atPath: layout.database.path) else {
            let error = PersistenceError.workspaceDatabaseMissing
            await recordFailure(error, trace: trace, category: .persistence)
            return recoveryOutcome(
                layout: layout,
                reason: String(describing: error)
            )
        }

        guard hasSQLiteHeader(at: layout.database) else {
            let error = PersistenceError.integrityCheckFailed(
                "invalid SQLite header"
            )
            await recordFailure(error, trace: trace, category: .corruption)
            return recoveryOutcome(
                layout: layout,
                reason: String(describing: error)
            )
        }

        do {
            let database = try WorkspaceDatabase(layout: layout)
            try database.verifyIntegrity()
            try createPreMigrationBackupIfNeeded(database: database)
            try await prepareSchemaWithDiagnostics(database)
            var workspace = try database.fetchWorkspace()
            if workspace.lifecycleState != .active {
                workspace = try database.setLifecycleState(.active)
            }
            sessions[workspace.id] = database
            await diagnostics.end(trace, outcome: .success)
            return .ready(workspace)
        } catch {
            await recordFailure(
                error,
                trace: trace,
                category: errorCategory(for: error)
            )
            return recoveryOutcome(layout: layout, reason: String(describing: error))
        }
    }

    public func closeWorkspace(id: WorkspaceID) async throws -> Workspace {
        guard let database = sessions.removeValue(forKey: id) else {
            throw PersistenceError.workspaceNotOpen
        }
        let workspace = try database.setLifecycleState(.closed)
        try database.close()
        return workspace
    }

    public func createBackup(workspaceID: WorkspaceID) async throws -> WorkspaceLocation {
        let trace = await diagnostics.begin(.workspaceBackup)
        do {
            guard let database = sessions[workspaceID] else {
                throw PersistenceError.workspaceNotOpen
            }
            try requireCapacity(
                additionalBytes: estimatedDatabaseBytes(database.layout),
                at: database.layout.backups
            )
            let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
            let destination = database.layout.backups
                .appending(
                    path: "workspace-\(timestamp)-\(UUID().uuidString).sqlite"
                )
            try database.createBackup(at: destination)

            if await failureInjector.shouldFail(at: .backupBeforeFinalize) {
                try? FileManager.default.removeItem(at: destination)
                throw ReliabilityError.injected(.backupBeforeFinalize)
            }
            try enforceRegularBackupRetention(in: database.layout.backups)
            await diagnostics.end(trace, outcome: .success)
            return WorkspaceLocation(
                rawValue: destination.resolvingSymlinksInPath().path
            )
        } catch {
            await recordFailure(error, trace: trace, category: .persistence)
            throw error
        }
    }

    public func outboxQueue(
        for workspaceID: WorkspaceID
    ) throws -> WorkspaceOutboxQueue {
        guard let database = sessions[workspaceID] else {
            throw PersistenceError.workspaceNotOpen
        }
        return WorkspaceOutboxQueue(database: database)
    }

    public func pendingOutboxJobCount(
        for workspaceID: WorkspaceID
    ) throws -> Int {
        guard let database = sessions[workspaceID] else {
            throw PersistenceError.workspaceNotOpen
        }
        return try database.pendingJobCount()
    }

    public func pendingSyncChangeCount(
        for workspaceID: WorkspaceID
    ) throws -> Int {
        guard let database = sessions[workspaceID] else {
            throw PersistenceError.workspaceNotOpen
        }
        return try database.pendingSyncChangeCount()
    }

    public func syncOutboxRecords(
        for workspaceID: WorkspaceID
    ) throws -> [SyncOutboxRecord] {
        guard let database = sessions[workspaceID] else {
            throw PersistenceError.workspaceNotOpen
        }
        return try database.syncOutboxRecords()
    }

    public func restoreWorkspace(
        at location: WorkspaceLocation,
        from backupLocation: WorkspaceLocation
    ) async throws -> WorkspaceOpenOutcome {
        let trace = await diagnostics.begin(.workspaceRestore)
        do {
            let layout = WorkspaceLayout(root: URL(filePath: location.rawValue))
            let backupURL = URL(filePath: backupLocation.rawValue)
            guard FileManager.default.fileExists(atPath: backupURL.path) else {
                throw PersistenceError.backupMissing
            }

            for (id, database) in sessions where database.layout == layout {
                try database.close()
                sessions.removeValue(forKey: id)
            }

            let currentDatabaseBytes = fileSize(at: layout.database)
            let selectedBackupBytes = fileSize(at: backupURL)
            try requireCapacity(
                additionalBytes: currentDatabaseBytes + selectedBackupBytes,
                at: layout.recovery
            )
            try createPreRestoreProtectionBackup(layout: layout)

            let temporaryURL = layout.recovery
                .appending(path: "workspace-restore-\(UUID().uuidString).sqlite")
            try FileManager.default.copyItem(at: backupURL, to: temporaryURL)
            if FileManager.default.fileExists(atPath: layout.database.path) {
                _ = try FileManager.default.replaceItemAt(
                    layout.database,
                    withItemAt: temporaryURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
            } else {
                try FileManager.default.moveItem(
                    at: temporaryURL,
                    to: layout.database
                )
            }

            let outcome = await openWorkspace(at: location)
            switch outcome {
            case .ready:
                await diagnostics.end(trace, outcome: .success)
            case let .recoveryRequired(context):
                let error = PersistenceError.integrityCheckFailed(context.reason)
                await recordFailure(error, trace: trace, category: .corruption)
            }
            return outcome
        } catch {
            await recordFailure(
                error,
                trace: trace,
                category: errorCategory(for: error)
            )
            throw error
        }
    }

    private func prepareSchemaWithDiagnostics(
        _ database: WorkspaceDatabase
    ) async throws {
        let trace = await diagnostics.begin(.databaseMigration)
        do {
            try database.prepareSchema()
            await diagnostics.end(trace, outcome: .success)
        } catch {
            await recordFailure(error, trace: trace, category: .persistence)
            throw error
        }
    }

    private func recordFailure(
        _ error: Error,
        trace: DiagnosticTrace,
        category: ErrorCategory
    ) async {
        await diagnostics.record(
            ClassifiedError(
                category: category,
                operation: trace.operation.rawValue,
                technicalCode: String(describing: error),
                traceID: trace.id
            )
        )
        await diagnostics.end(trace, outcome: .failure)
    }

    private func errorCategory(for error: Error) -> ErrorCategory {
        guard let persistenceError = error as? PersistenceError else {
            return .persistence
        }
        switch persistenceError {
        case .integrityCheckFailed:
            return .corruption
        default:
            return .persistence
        }
    }

    private func createPreMigrationBackupIfNeeded(
        database: WorkspaceDatabase
    ) throws {
        guard try database.needsMigration() else {
            return
        }
        let destination = database.layout.backups
            .appending(path: "pre-migration-v\(DatabaseSchema.currentVersion).sqlite")
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            return
        }
        try requireCapacity(
            additionalBytes: estimatedDatabaseBytes(database.layout),
            at: database.layout.backups
        )
        try database.createBackup(at: destination)
    }

    private func createPreRestoreProtectionBackup(
        layout: WorkspaceLayout
    ) throws {
        guard FileManager.default.fileExists(atPath: layout.database.path) else {
            return
        }
        let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
        let destination = layout.backups.appending(
            path: "pre-restore-\(timestamp)-\(UUID().uuidString).sqlite"
        )
        try FileManager.default.copyItem(at: layout.database, to: destination)
    }

    private func enforceRegularBackupRetention(in directory: URL) throws {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .creationDateKey
        ]
        let backups = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys)
        )
        .filter {
            $0.lastPathComponent.hasPrefix("workspace-") &&
                $0.pathExtension == "sqlite"
        }
        .sorted { lhs, rhs in
            let lhsValues = try? lhs.resourceValues(forKeys: keys)
            let rhsValues = try? rhs.resourceValues(forKeys: keys)
            let lhsDate = lhsValues?.contentModificationDate ??
                lhsValues?.creationDate ?? .distantPast
            let rhsDate = rhsValues?.contentModificationDate ??
                rhsValues?.creationDate ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.lastPathComponent > rhs.lastPathComponent
            }
            return lhsDate > rhsDate
        }

        for expired in backups.dropFirst(backupPolicy.maximumRegularBackups) {
            try FileManager.default.removeItem(at: expired)
        }
    }

    private func requireCapacity(
        additionalBytes: Int64,
        at destination: URL
    ) throws {
        guard let available = try diskCapacityProvider.availableCapacity(
            at: destination
        ) else {
            return
        }
        let required = additionalBytes +
            backupPolicy.minimumFreeSpaceReserveBytes
        guard available >= required else {
            throw PersistenceError.insufficientDiskSpace(
                requiredBytes: required,
                availableBytes: available
            )
        }
    }

    private func estimatedDatabaseBytes(_ layout: WorkspaceLayout) -> Int64 {
        fileSize(at: layout.database) +
            fileSize(at: URL(filePath: layout.database.path + "-wal")) +
            fileSize(at: URL(filePath: layout.database.path + "-shm"))
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey
        ]) else {
            return 0
        }
        if let totalAllocated = values.totalFileAllocatedSize {
            return Int64(totalAllocated)
        }
        if let allocated = values.fileAllocatedSize {
            return Int64(allocated)
        }
        return Int64(values.fileSize ?? 0)
    }

    private func recoveryOutcome(
        layout: WorkspaceLayout,
        reason: String
    ) -> WorkspaceOpenOutcome {
        let backupURLs = (try? FileManager.default.contentsOfDirectory(
            at: layout.backups,
            includingPropertiesForKeys: nil
        )) ?? []
        let backups = backupURLs
            .filter { $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { WorkspaceLocation(rawValue: $0.path) }
        return .recoveryRequired(
            RecoveryContext(
                location: WorkspaceLocation(rawValue: layout.root.path),
                reason: reason,
                backupLocations: backups
            )
        )
    }

    private func hasSQLiteHeader(at databaseURL: URL) -> Bool {
        guard
            let handle = try? FileHandle(forReadingFrom: databaseURL),
            let header = try? handle.read(upToCount: 16)
        else {
            return false
        }
        try? handle.close()
        return header == Data("SQLite format 3\0".utf8)
    }
}
