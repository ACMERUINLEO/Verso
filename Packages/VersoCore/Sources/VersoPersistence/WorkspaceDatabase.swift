import Foundation
import GRDB
import VersoApplication
import VersoDomain
import VersoSyncProtocol

final class WorkspaceDatabase: @unchecked Sendable {
    let layout: WorkspaceLayout
    private let pool: DatabasePool

    init(layout: WorkspaceLayout, readOnly: Bool = false) throws {
        self.layout = layout
        var configuration = Configuration()
        configuration.readonly = readOnly
        configuration.label = "Verso Workspace"
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
            try database.execute(sql: "PRAGMA busy_timeout = 5000")
        }
        pool = try DatabasePool(
            path: layout.database.path,
            configuration: configuration
        )
    }

    func prepareSchema() throws {
        try pool.writeWithoutTransaction { database in
            try database.execute(sql: "PRAGMA journal_mode = WAL")
        }
        try DatabaseSchema.migrator().migrate(pool)
    }

    func needsMigration() throws -> Bool {
        try pool.read { database in
            try !DatabaseSchema.migrator().hasCompletedMigrations(database)
        }
    }

    func verifyIntegrity() throws {
        let result = try pool.read { database in
            try String.fetchOne(database, sql: "PRAGMA quick_check")
        }
        guard result == "ok" else {
            throw PersistenceError.integrityCheckFailed(result ?? "no result")
        }
    }

    func insertInitialWorkspace(
        _ workspace: Workspace,
        operationID: OperationID,
        sourceDeviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> WorkspaceMutationDisposition {
        try pool.write { database in
            let fingerprint = "name:\(workspace.name)"
            if let disposition = try Self.replayedDisposition(
                database: database,
                operationID: operationID,
                sourceDeviceID: sourceDeviceID,
                commandName: "workspace.create.v1",
                fingerprint: fingerprint
            ) {
                return disposition
            }
            if try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM workspaces"
            ) ?? 0 > 0 {
                throw PersistenceError.workspaceAlreadyExists
            }
            try database.execute(
                sql: """
                    INSERT INTO workspaces (
                        id, name, schema_version, root_node_id,
                        created_at, modified_at, default_time_zone_id,
                        lifecycle_state, revision, deleted_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                    """,
                arguments: [
                    workspace.id.rawValue.uuidString,
                    workspace.name,
                    workspace.schemaVersion,
                    workspace.rootNodeID.rawValue.uuidString,
                    workspace.createdAt.timeIntervalSince1970,
                    workspace.modifiedAt.timeIntervalSince1970,
                    workspace.defaultTimeZoneID,
                    workspace.lifecycleState.rawValue,
                    workspace.revision
                ]
            )
            try database.execute(
                sql: """
                    INSERT INTO nodes (
                        id, workspace_id, parent_id, kind, display_name,
                        rank, created_at, modified_at, deleted_at,
                        revision, operation_id
                    ) VALUES (?, ?, NULL, 'folder', ?, '0', ?, ?, NULL, 1, ?)
                    """,
                arguments: [
                    workspace.rootNodeID.rawValue.uuidString,
                    workspace.id.rawValue.uuidString,
                    workspace.name,
                    workspace.createdAt.timeIntervalSince1970,
                    workspace.modifiedAt.timeIntervalSince1970,
                    operationID.rawValue.uuidString
                ]
            )
            try Self.insertAppliedOperation(
                database: database,
                operationID: operationID,
                workspaceID: workspace.id,
                sourceDeviceID: sourceDeviceID,
                commandName: "workspace.create.v1",
                fingerprint: fingerprint,
                appliedAt: workspace.createdAt
            )
            try Self.insertWorkspaceSyncChange(
                database: database,
                workspace: workspace,
                operationID: operationID,
                sourceDeviceID: sourceDeviceID,
                baseRevision: 0,
                createdAt: workspace.createdAt
            )
            try database.execute(
                sql: """
                    INSERT INTO outbox_jobs (
                        id, kind, payload, idempotency_key, state,
                        attempts, available_at, created_at
                    ) VALUES (?, 'workspace.created', ?, ?, 'pending', 0, ?, ?)
                    """,
                arguments: [
                    JobID().rawValue.uuidString,
                    Data(workspace.id.rawValue.uuidString.utf8),
                    "workspace.created:\(workspace.id.rawValue.uuidString)",
                    workspace.createdAt.timeIntervalSince1970,
                    workspace.createdAt.timeIntervalSince1970
                ]
            )

            if failBeforeCommit {
                throw ReliabilityError.injected(.databaseTransactionBeforeCommit)
            }
            return .applied
        }
    }

    func renameWorkspace(
        id: WorkspaceID,
        to name: String,
        expectedRevision: Int64,
        operationID: OperationID,
        sourceDeviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> WorkspaceMutationResult {
        try pool.write { database in
            let normalizedName = name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !normalizedName.isEmpty else {
                throw DomainError.invalidWorkspaceName
            }
            let fingerprint = [
                "workspace:\(id.rawValue.uuidString)",
                "name:\(normalizedName)",
                "expected:\(expectedRevision)"
            ].joined(separator: "|")

            if let disposition = try Self.replayedDisposition(
                database: database,
                operationID: operationID,
                sourceDeviceID: sourceDeviceID,
                commandName: "workspace.rename.v1",
                fingerprint: fingerprint
            ) {
                let workspace = try Self.fetchWorkspace(
                    database: database,
                    id: id
                )
                return WorkspaceMutationResult(
                    workspace: workspace,
                    operationID: operationID,
                    disposition: disposition
                )
            }

            let current = try Self.fetchWorkspace(database: database, id: id)
            guard current.revision == expectedRevision else {
                throw PersistenceError.revisionConflict(
                    expected: expectedRevision,
                    actual: current.revision
                )
            }
            let updated = try current.renamed(to: normalizedName)
            try database.execute(
                sql: """
                    UPDATE workspaces
                    SET name = ?, modified_at = ?, revision = ?
                    WHERE id = ? AND revision = ?
                    """,
                arguments: [
                    updated.name,
                    updated.modifiedAt.timeIntervalSince1970,
                    updated.revision,
                    id.rawValue.uuidString,
                    expectedRevision
                ]
            )
            guard database.changesCount == 1 else {
                throw PersistenceError.revisionConflict(
                    expected: expectedRevision,
                    actual: current.revision
                )
            }
            try Self.insertAppliedOperation(
                database: database,
                operationID: operationID,
                workspaceID: id,
                sourceDeviceID: sourceDeviceID,
                commandName: "workspace.rename.v1",
                fingerprint: fingerprint,
                appliedAt: updated.modifiedAt
            )
            try Self.insertWorkspaceSyncChange(
                database: database,
                workspace: updated,
                operationID: operationID,
                sourceDeviceID: sourceDeviceID,
                baseRevision: current.revision,
                createdAt: updated.modifiedAt
            )

            if failBeforeCommit {
                throw ReliabilityError.injected(.databaseTransactionBeforeCommit)
            }
            let persisted = try Self.fetchWorkspace(database: database, id: id)
            return WorkspaceMutationResult(
                workspace: persisted,
                operationID: operationID,
                disposition: .applied
            )
        }
    }

    func fetchWorkspace() throws -> Workspace {
        try pool.read { database in
            guard let row = try Row.fetchOne(
                database,
                sql: "SELECT * FROM workspaces LIMIT 1"
            ) else {
                throw PersistenceError.workspaceMetadataMissing
            }
            return try Self.decodeWorkspace(row)
        }
    }

    func setLifecycleState(_ state: WorkspaceLifecycleState) throws -> Workspace {
        try pool.write { database in
            try database.execute(
                sql: "UPDATE workspaces SET lifecycle_state = ?",
                arguments: [state.rawValue]
            )
            guard let row = try Row.fetchOne(
                database,
                sql: "SELECT * FROM workspaces LIMIT 1"
            ) else {
                throw PersistenceError.workspaceMetadataMissing
            }
            return try Self.decodeWorkspace(row)
        }
    }

    func createBackup(at destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        let backupDatabase = try DatabaseQueue(path: destination.path)
        try pool.backup(to: backupDatabase)
    }

    func claimNextJob() throws -> OutboxJob? {
        try pool.write { database in
            let now = Date().timeIntervalSince1970
            guard let row = try Row.fetchOne(
                database,
                sql: """
                    SELECT id, kind, payload, idempotency_key, attempts
                    FROM outbox_jobs
                    WHERE state = 'pending' AND available_at <= ?
                    ORDER BY created_at ASC
                    LIMIT 1
                    """,
                arguments: [now]
            ) else {
                return nil
            }

            let idString: String = row["id"]
            guard let uuid = UUID(uuidString: idString) else {
                throw PersistenceError.invalidStoredIdentity
            }
            try database.execute(
                sql: """
                    UPDATE outbox_jobs
                    SET state = 'running', attempts = attempts + 1
                    WHERE id = ? AND state = 'pending'
                    """,
                arguments: [idString]
            )
            guard database.changesCount == 1 else {
                return nil
            }
            let attempts: Int = row["attempts"]
            return OutboxJob(
                id: JobID(rawValue: uuid),
                kind: row["kind"],
                payload: row["payload"],
                idempotencyKey: row["idempotency_key"],
                attempts: attempts + 1
            )
        }
    }

    func markJobCompleted(id: JobID) throws {
        try pool.write { database in
            try database.execute(
                sql: """
                    UPDATE outbox_jobs
                    SET state = 'completed', completed_at = ?, last_error = NULL
                    WHERE id = ? AND state = 'running'
                    """,
                arguments: [
                    Date().timeIntervalSince1970,
                    id.rawValue.uuidString
                ]
            )
        }
    }

    func markJobFailed(id: JobID, reason: String) throws {
        try pool.write { database in
            let attempts = try Int.fetchOne(
                database,
                sql: "SELECT attempts FROM outbox_jobs WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            ) ?? 1
            let delay = min(pow(2.0, Double(attempts)), 300.0)
            try database.execute(
                sql: """
                    UPDATE outbox_jobs
                    SET state = 'pending', available_at = ?, last_error = ?
                    WHERE id = ? AND state = 'running'
                    """,
                arguments: [
                    Date().addingTimeInterval(delay).timeIntervalSince1970,
                    String(reason.prefix(500)),
                    id.rawValue.uuidString
                ]
            )
        }
    }

    func pendingJobCount() throws -> Int {
        try pool.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM outbox_jobs WHERE state != 'completed'"
            ) ?? 0
        }
    }

    func pendingSyncChangeCount() throws -> Int {
        try pool.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM sync_outbox WHERE state != 'completed'"
            ) ?? 0
        }
    }

    func syncOutboxRecords() throws -> [SyncOutboxRecord] {
        try pool.read { database in
            try Row.fetchAll(
                database,
                sql: """
                    SELECT id, operation_id, workspace_id, source_device_id,
                           record_kind, record_id, mutation_kind,
                           base_revision, revision, payload
                    FROM sync_outbox
                    ORDER BY created_at, id
                    """
            ).map(Self.decodeSyncOutboxRecord)
        }
    }

    func close() throws {
        try pool.close()
    }

    private static func decodeWorkspace(_ row: Row) throws -> Workspace {
        guard
            let workspaceUUID = UUID(uuidString: row["id"]),
            let rootNodeUUID = UUID(uuidString: row["root_node_id"]),
            let lifecycle = WorkspaceLifecycleState(rawValue: row["lifecycle_state"])
        else {
            throw PersistenceError.invalidStoredIdentity
        }

        return Workspace(
            id: WorkspaceID(rawValue: workspaceUUID),
            name: row["name"],
            schemaVersion: row["schema_version"],
            rootNodeID: NodeID(rawValue: rootNodeUUID),
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            modifiedAt: Date(timeIntervalSince1970: row["modified_at"]),
            defaultTimeZoneID: row["default_time_zone_id"],
            lifecycleState: lifecycle,
            revision: row["revision"],
            deletedAt: (row["deleted_at"] as Double?).map {
                Date(timeIntervalSince1970: $0)
            }
        )
    }

    private static func fetchWorkspace(
        database: Database,
        id: WorkspaceID
    ) throws -> Workspace {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM workspaces WHERE id = ?",
            arguments: [id.rawValue.uuidString]
        ) else {
            throw PersistenceError.workspaceMetadataMissing
        }
        return try decodeWorkspace(row)
    }

    private static func replayedDisposition(
        database: Database,
        operationID: OperationID,
        sourceDeviceID: DeviceID,
        commandName: String,
        fingerprint: String
    ) throws -> WorkspaceMutationDisposition? {
        guard let row = try Row.fetchOne(
            database,
            sql: """
                SELECT source_device_id, command_name, command_fingerprint
                FROM applied_operations
                WHERE operation_id = ?
                """,
            arguments: [operationID.rawValue.uuidString]
        ) else {
            return nil
        }
        let storedDeviceID: String = row["source_device_id"]
        let storedCommand: String = row["command_name"]
        let storedFingerprint: String = row["command_fingerprint"]
        guard
            storedDeviceID == sourceDeviceID.rawValue.uuidString,
            storedCommand == commandName,
            storedFingerprint == fingerprint
        else {
            throw PersistenceError.operationIDConflict(operationID)
        }
        return .replayed
    }

    private static func insertAppliedOperation(
        database: Database,
        operationID: OperationID,
        workspaceID: WorkspaceID,
        sourceDeviceID: DeviceID,
        commandName: String,
        fingerprint: String,
        appliedAt: Date
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO applied_operations (
                    operation_id, workspace_id, source_device_id,
                    command_name, command_fingerprint, applied_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                operationID.rawValue.uuidString,
                workspaceID.rawValue.uuidString,
                sourceDeviceID.rawValue.uuidString,
                commandName,
                fingerprint,
                appliedAt.timeIntervalSince1970
            ]
        )
    }

    private static func insertWorkspaceSyncChange(
        database: Database,
        workspace: Workspace,
        operationID: OperationID,
        sourceDeviceID: DeviceID,
        baseRevision: Int64,
        createdAt: Date
    ) throws {
        let payload = WorkspaceSyncPayload(
            workspaceID: workspace.id,
            name: workspace.name,
            defaultTimeZoneID: workspace.defaultTimeZoneID,
            rootNodeID: workspace.rootNodeID,
            revision: workspace.revision,
            modifiedAt: workspace.modifiedAt,
            deletedAt: workspace.deletedAt
        )
        let encodedPayload = try JSONEncoder().encode(payload)
        try database.execute(
            sql: """
                INSERT INTO sync_outbox (
                    id, operation_id, workspace_id, source_device_id,
                    record_kind, record_id, mutation_kind,
                    base_revision, revision, payload, state,
                    attempts, available_at, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 0, ?, ?)
                """,
            arguments: [
                SyncOutboxEntryID().rawValue.uuidString,
                operationID.rawValue.uuidString,
                workspace.id.rawValue.uuidString,
                sourceDeviceID.rawValue.uuidString,
                SyncRecordKind.workspace.rawValue,
                workspace.id.rawValue.uuidString,
                SyncMutationKind.upsert.rawValue,
                baseRevision,
                workspace.revision,
                encodedPayload,
                createdAt.timeIntervalSince1970,
                createdAt.timeIntervalSince1970
            ]
        )
    }

    private static func decodeSyncOutboxRecord(
        _ row: Row
    ) throws -> SyncOutboxRecord {
        guard
            let entryUUID = UUID(uuidString: row["id"]),
            let operationUUID = UUID(uuidString: row["operation_id"]),
            let workspaceUUID = UUID(uuidString: row["workspace_id"]),
            let deviceUUID = UUID(uuidString: row["source_device_id"]),
            let recordUUID = UUID(uuidString: row["record_id"]),
            let recordKind = SyncRecordKind(rawValue: row["record_kind"]),
            let mutation = SyncMutationKind(rawValue: row["mutation_kind"])
        else {
            throw PersistenceError.invalidStoredIdentity
        }
        let change = SyncChange(
            operationID: OperationID(rawValue: operationUUID),
            recordKind: recordKind,
            recordID: recordUUID,
            mutation: mutation,
            baseRevision: row["base_revision"],
            revision: row["revision"],
            payload: row["payload"]
        )
        return SyncOutboxRecord(
            id: SyncOutboxEntryID(rawValue: entryUUID),
            workspaceID: WorkspaceID(rawValue: workspaceUUID),
            sourceDeviceID: DeviceID(rawValue: deviceUUID),
            change: change
        )
    }
}
