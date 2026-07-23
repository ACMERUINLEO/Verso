import CryptoKit
import Foundation
import GRDB
import VersoApplication
import VersoDomain
import VersoSyncProtocol

extension WorkspaceDatabase {
    static func phase0Fingerprint(_ components: [String]) -> String {
        let data = Data(components.joined(separator: "\u{1f}").utf8)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func phase0Replay(
        database: Database,
        operationID: OperationID,
        sourceDeviceID: DeviceID,
        commandName: String,
        fingerprint: String
    ) throws -> Bool {
        guard let row = try Row.fetchOne(
            database,
            sql: """
                SELECT source_device_id, command_name, command_fingerprint
                FROM applied_operations
                WHERE operation_id = ?
                """,
            arguments: [operationID.rawValue.uuidString]
        ) else {
            return false
        }
        let storedDeviceID: String = row["source_device_id"]
        let storedCommand: String = row["command_name"]
        let storedFingerprint: String = row["command_fingerprint"]
        guard storedDeviceID == sourceDeviceID.rawValue.uuidString,
              storedCommand == commandName,
              storedFingerprint == fingerprint else {
            throw PersistenceError.operationIDConflict(operationID)
        }
        return true
    }

    static func phase0InsertAppliedOperation(
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

    static func phase0InsertSyncChange<Payload: Encodable>(
        database: Database,
        workspaceID: WorkspaceID,
        sourceDeviceID: DeviceID,
        operationID: OperationID,
        recordKind: SyncRecordKind,
        recordID: UUID,
        baseRevision: Int64,
        revision: Int64,
        payload: Payload,
        createdAt: Date
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        try database.execute(
            sql: """
                INSERT INTO sync_outbox (
                    id, operation_id, workspace_id, source_device_id,
                    record_kind, record_id, mutation_kind,
                    base_revision, revision, payload, state,
                    attempts, available_at, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, 'upsert', ?, ?, ?, 'pending', 0, ?, ?)
                """,
            arguments: [
                SyncOutboxEntryID().rawValue.uuidString,
                operationID.rawValue.uuidString,
                workspaceID.rawValue.uuidString,
                sourceDeviceID.rawValue.uuidString,
                recordKind.rawValue,
                recordID.uuidString,
                baseRevision,
                revision,
                data,
                createdAt.timeIntervalSince1970,
                createdAt.timeIntervalSince1970
            ]
        )
    }

    static func phase0InsertIntegrationEvent<Payload: Encodable>(
        database: Database,
        eventName: String,
        workspaceID: WorkspaceID,
        actorID: ActorID,
        aggregateKind: String,
        aggregateID: UUID,
        operationID: OperationID,
        occurredAt: Date,
        payload: Payload
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        try database.execute(
            sql: """
                INSERT INTO integration_outbox (
                    id, event_name, schema_version, workspace_id, actor_id,
                    aggregate_kind, aggregate_id, operation_id, occurred_at,
                    payload, state, attempts, available_at
                ) VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?, ?, 'pending', 0, ?)
                """,
            arguments: [
                IntegrationEventID().rawValue.uuidString,
                eventName,
                workspaceID.rawValue.uuidString,
                actorID.rawValue.uuidString,
                aggregateKind,
                aggregateID.uuidString,
                operationID.rawValue.uuidString,
                occurredAt.timeIntervalSince1970,
                data,
                occurredAt.timeIntervalSince1970
            ]
        )
    }

    static func phase0UUID(_ value: String) throws -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            throw PersistenceError.invalidStoredIdentity
        }
        return uuid
    }

    static func phase0Date(_ row: Row, _ column: String) -> Date {
        Date(timeIntervalSince1970: row[column])
    }

    static func phase0OptionalDate(_ row: Row, _ column: String) -> Date? {
        (row[column] as Double?).map(Date.init(timeIntervalSince1970:))
    }

    static func phase0SHA256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func pendingIntegrationEventCount() throws -> Int {
        try pool.read { database in
            try Int.fetchOne(
                database,
                sql: """
                    SELECT COUNT(*)
                    FROM integration_outbox
                    WHERE state != 'completed'
                    """
            ) ?? 0
        }
    }

    func integrationEventPayloads() throws -> [Data] {
        try pool.read { database in
            try Data.fetchAll(
                database,
                sql: """
                    SELECT payload
                    FROM integration_outbox
                    ORDER BY occurred_at, id
                    """
            )
        }
    }
}
