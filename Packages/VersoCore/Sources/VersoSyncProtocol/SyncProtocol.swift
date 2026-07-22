import Foundation
import VersoDomain

public enum SyncRecordKind: String, Codable, CaseIterable, Sendable {
    case workspace
    case node
    case document
    case asset
    case conversation
    case task
}

public enum SyncMutationKind: String, Codable, Sendable {
    case upsert
    case tombstone
}

public struct SyncChange: Codable, Equatable, Sendable {
    public let operationID: OperationID
    public let recordKind: SyncRecordKind
    public let recordID: UUID
    public let mutation: SyncMutationKind
    public let baseRevision: Int64
    public let revision: Int64
    public let payload: Data

    public init(
        operationID: OperationID,
        recordKind: SyncRecordKind,
        recordID: UUID,
        mutation: SyncMutationKind,
        baseRevision: Int64,
        revision: Int64,
        payload: Data
    ) {
        self.operationID = operationID
        self.recordKind = recordKind
        self.recordID = recordID
        self.mutation = mutation
        self.baseRevision = baseRevision
        self.revision = revision
        self.payload = payload
    }
}

public struct SyncTombstone: Codable, Equatable, Sendable {
    public let operationID: OperationID
    public let recordKind: SyncRecordKind
    public let recordID: UUID
    public let revision: Int64
    public let deletedAt: Date

    public init(
        operationID: OperationID,
        recordKind: SyncRecordKind,
        recordID: UUID,
        revision: Int64,
        deletedAt: Date
    ) {
        self.operationID = operationID
        self.recordKind = recordKind
        self.recordID = recordID
        self.revision = revision
        self.deletedAt = deletedAt
    }
}

public struct SyncChangeBatch: Codable, Equatable, Sendable {
    public static let currentProtocolVersion = 1

    public let protocolVersion: Int
    public let workspaceID: WorkspaceID
    public let sourceDeviceID: DeviceID
    public let changes: [SyncChange]

    public init(
        protocolVersion: Int = currentProtocolVersion,
        workspaceID: WorkspaceID,
        sourceDeviceID: DeviceID,
        changes: [SyncChange]
    ) {
        self.protocolVersion = protocolVersion
        self.workspaceID = workspaceID
        self.sourceDeviceID = sourceDeviceID
        self.changes = changes
    }
}

public struct SyncCursor: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct SyncPullPage: Codable, Equatable, Sendable {
    public let batches: [SyncChangeBatch]
    public let nextCursor: SyncCursor?
    public let hasMore: Bool

    public init(
        batches: [SyncChangeBatch],
        nextCursor: SyncCursor?,
        hasMore: Bool
    ) {
        self.batches = batches
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

public protocol SyncTransport: Sendable {
    func push(_ batch: SyncChangeBatch) async throws
    func pull(
        workspaceID: WorkspaceID,
        after cursor: SyncCursor?,
        limit: Int
    ) async throws -> SyncPullPage
}

public enum SyncDataClassification: String, Codable, Sendable {
    case syncedFact
    case localOnlyFact
    case rebuildableCache
}

public enum SyncDataCategory: String, Codable, CaseIterable, Sendable {
    case workspaceMetadata
    case nodeMetadata
    case immutableRevision
    case tombstone
    case operationIdentity
    case securityScopedBookmark
    case absoluteFilePath
    case apiKey
    case oauthToken
    case deviceCredential
    case jobLease
    case localExecutionState
    case fullTextIndex
    case embedding
    case thumbnail
    case previewArtifact
}

public enum SyncDataPolicy {
    public static func classification(
        of category: SyncDataCategory
    ) -> SyncDataClassification {
        switch category {
        case .workspaceMetadata,
             .nodeMetadata,
             .immutableRevision,
             .tombstone,
             .operationIdentity:
            .syncedFact
        case .securityScopedBookmark,
             .absoluteFilePath,
             .apiKey,
             .oauthToken,
             .deviceCredential,
             .jobLease,
             .localExecutionState:
            .localOnlyFact
        case .fullTextIndex,
             .embedding,
             .thumbnail,
             .previewArtifact:
            .rebuildableCache
        }
    }
}
