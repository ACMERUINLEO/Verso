import Foundation

public enum ActorKind: String, Codable, CaseIterable, Sendable {
    case person
    case agent
    case organization
    case importer
    case recovery
}

public struct Actor: Codable, Equatable, Sendable {
    public let id: ActorID
    public let workspaceID: WorkspaceID
    public let kind: ActorKind
    public let displayName: String
    public let createdAt: Date
    public let modifiedAt: Date
    public let revision: Int64
}

public struct CreatorProfile: Codable, Equatable, Sendable {
    public let id: CreatorProfileID
    public let actorID: ActorID
    public let biography: String
    public let websiteURL: String?
    public let revision: Int64
}

public enum SourceKind: String, Codable, CaseIterable, Sendable {
    case web
    case book
    case video
    case file
    case interview
    case original
}

public struct SourceRecord: Codable, Equatable, Sendable {
    public let id: SourceRecordID
    public let workspaceID: WorkspaceID
    public let kind: SourceKind
    public let canonicalURL: String?
    public let title: String
    public let originalCreator: String?
    public let capturedAt: Date
    public let contentHash: String?
    public let sourceAssetID: AssetID?
    public let snapshotRevisionID: DocumentRevisionID?
    public let licenseHint: String?
    public let createdByActorID: ActorID
    public let revision: Int64
    public let deletedAt: Date?
}

public struct DocumentRevisionSnapshot: Codable, Equatable, Sendable {
    public let documentID: DocumentID
    public let revisionID: DocumentRevisionID
    public let workspaceID: WorkspaceID
    public let title: String
    public let contentRelativePath: String
    public let contentHash: String
    public let parentRevisionID: DocumentRevisionID?
    public let authorActorID: ActorID
    public let createdAt: Date
}

public enum KnowledgeConceptLifecycleState: String, Codable, Sendable {
    case draft
    case active
    case deprecated
    case archived
}

public struct KnowledgeConcept: Codable, Equatable, Sendable {
    public let id: KnowledgeConceptID
    public let workspaceID: WorkspaceID
    public let documentID: DocumentID
    public let type: String
    public let title: String
    public let description: String
    public let resourceURI: String?
    public let creatorActorID: ActorID
    public let lifecycleState: KnowledgeConceptLifecycleState
    public let currentRevisionID: KnowledgeConceptRevisionID
    public let createdAt: Date
    public let modifiedAt: Date
    public let deletedAt: Date?
    public let revision: Int64
}

public struct KnowledgeConceptRevision: Codable, Equatable, Sendable {
    public let id: KnowledgeConceptRevisionID
    public let conceptID: KnowledgeConceptID
    public let documentRevisionID: DocumentRevisionID
    public let metadataJSON: String
    public let parentRevisionID: KnowledgeConceptRevisionID?
    public let authorActorID: ActorID
    public let contentHash: String
    public let createdAt: Date
}

public enum ReferenceRelation: String, Codable, CaseIterable, Sendable {
    case cites
    case quotes
    case supports
    case contradicts
    case derivedFrom
    case summarizes
    case includedIn
}

public enum ReferenceTargetKind: String, Codable, CaseIterable, Sendable {
    case sourceRecord
    case document
    case knowledgeConcept
    case output
    case bundleMember
}

public struct KnowledgeReference: Codable, Equatable, Sendable {
    public let id: ReferenceID
    public let workspaceID: WorkspaceID
    public let sourceKind: ReferenceTargetKind
    public let sourceID: UUID
    public let sourceRevisionID: UUID?
    public let targetKind: ReferenceTargetKind
    public let targetID: UUID
    public let targetRevisionID: UUID?
    public let relation: ReferenceRelation
    public let anchorJSON: String?
    public let createdAt: Date
    public let deletedAt: Date?
}

public enum PublicationVisibility: String, Codable, Sendable {
    case `private`
    case candidate
    case included
}

public enum OwnershipBasis: String, Codable, Sendable {
    case original
    case licensed
    case quoted
    case unknown
}

public enum CommercialUse: String, Codable, Sendable {
    case allowed
    case prohibited
    case unknown
}

public enum VerificationStatus: String, Codable, Sendable {
    case selfDeclared
    case reviewed
    case verified
}

public enum PublicationSensitivity: String, Codable, Sendable {
    case normal
    case personal
    case confidential
}

public struct PublicationPolicy: Codable, Equatable, Sendable {
    public let id: PublicationPolicyID
    public let workspaceID: WorkspaceID
    public let visibility: PublicationVisibility
    public let ownershipBasis: OwnershipBasis
    public let commercialUse: CommercialUse
    public let attributionRequired: Bool
    public let attributionText: String?
    public let verificationStatus: VerificationStatus
    public let sensitivity: PublicationSensitivity
    public let revision: Int64
}

public enum BundleLifecycleState: String, Codable, Sendable {
    case draft
    case active
    case deprecated
    case revoked
}

public struct Bundle: Codable, Equatable, Sendable {
    public let id: BundleID
    public let workspaceID: WorkspaceID
    public let creatorActorID: ActorID
    public let title: String
    public let lifecycleState: BundleLifecycleState
    public let createdAt: Date
    public let modifiedAt: Date
    public let revision: Int64
}

public struct BundleDraft: Codable, Equatable, Sendable {
    public let id: BundleDraftID
    public let bundleID: BundleID
    public let revision: Int64
    public let createdAt: Date
    public let modifiedAt: Date
}

public enum BundleMemberTargetKind: String, Codable, Sendable {
    case concept
    case output
    case document
    case asset
}

public struct BundleDraftMember: Codable, Equatable, Sendable {
    public let targetKind: BundleMemberTargetKind
    public let targetID: UUID
    public let targetRevisionID: UUID
    public let exportPath: String
    public let role: String
    public let rank: Int
    public let publicationPolicyID: PublicationPolicyID
}

public enum BundleVersionStatus: String, Codable, Sendable {
    case frozen
    case exported
    case published
    case deprecated
    case revoked
}

public struct BundleVersion: Codable, Equatable, Sendable {
    public let id: BundleVersionID
    public let bundleID: BundleID
    public let semanticVersion: String
    public let manifestVersion: Int
    public let okfVersion: String
    public let contentDigest: String
    public let status: BundleVersionStatus
    public let createdByActorID: ActorID
    public let createdAt: Date
}

public struct BundleMember: Codable, Equatable, Sendable {
    public let id: BundleMemberID
    public let bundleVersionID: BundleVersionID
    public let targetKind: BundleMemberTargetKind
    public let targetID: UUID
    public let targetRevisionID: UUID
    public let exportPath: String
    public let role: String
    public let rank: Int
}

public struct BundleVersionSnapshot: Codable, Equatable, Sendable {
    public let version: BundleVersion
    public let members: [BundleMember]
}

public struct IntegrationEventEnvelope: Codable, Equatable, Sendable {
    public let eventID: IntegrationEventID
    public let eventName: String
    public let schemaVersion: Int
    public let workspaceID: WorkspaceID
    public let actorID: ActorID
    public let aggregateKind: String
    public let aggregateID: UUID
    public let operationID: OperationID
    public let occurredAt: Date
    public let payload: Data
}

public enum KnowledgeAssetError: Error, Equatable, Sendable {
    case invalidDisplayName
    case invalidConceptType
    case invalidExportPath
    case invalidSemanticVersion
    case missingDocumentRevision
    case missingConceptRevision
    case publicationNotAllowed
    case privateContent
    case sensitiveContent
    case contentHashMismatch
}

public extension Actor {
    init(
        _ id: ActorID,
        workspaceID: WorkspaceID,
        kind: ActorKind,
        displayName: String,
        createdAt: Date,
        modifiedAt: Date,
        revision: Int64
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.kind = kind
        self.displayName = displayName
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.revision = revision
    }
}

public extension CreatorProfile {
    init(
        _ id: CreatorProfileID,
        actorID: ActorID,
        biography: String,
        websiteURL: String?,
        revision: Int64
    ) {
        self.id = id
        self.actorID = actorID
        self.biography = biography
        self.websiteURL = websiteURL
        self.revision = revision
    }
}

public extension SourceRecord {
    init(
        _ id: SourceRecordID,
        workspaceID: WorkspaceID,
        kind: SourceKind,
        canonicalURL: String?,
        title: String,
        originalCreator: String?,
        capturedAt: Date,
        contentHash: String?,
        sourceAssetID: AssetID?,
        snapshotRevisionID: DocumentRevisionID?,
        licenseHint: String?,
        createdByActorID: ActorID,
        revision: Int64,
        deletedAt: Date?
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.kind = kind
        self.canonicalURL = canonicalURL
        self.title = title
        self.originalCreator = originalCreator
        self.capturedAt = capturedAt
        self.contentHash = contentHash
        self.sourceAssetID = sourceAssetID
        self.snapshotRevisionID = snapshotRevisionID
        self.licenseHint = licenseHint
        self.createdByActorID = createdByActorID
        self.revision = revision
        self.deletedAt = deletedAt
    }
}

public extension DocumentRevisionSnapshot {
    init(
        _ documentID: DocumentID,
        revisionID: DocumentRevisionID,
        workspaceID: WorkspaceID,
        title: String,
        contentRelativePath: String,
        contentHash: String,
        parentRevisionID: DocumentRevisionID?,
        authorActorID: ActorID,
        createdAt: Date
    ) {
        self.documentID = documentID
        self.revisionID = revisionID
        self.workspaceID = workspaceID
        self.title = title
        self.contentRelativePath = contentRelativePath
        self.contentHash = contentHash
        self.parentRevisionID = parentRevisionID
        self.authorActorID = authorActorID
        self.createdAt = createdAt
    }
}

public extension KnowledgeConcept {
    init(
        _ id: KnowledgeConceptID,
        workspaceID: WorkspaceID,
        documentID: DocumentID,
        type: String,
        title: String,
        description: String,
        resourceURI: String?,
        creatorActorID: ActorID,
        lifecycleState: KnowledgeConceptLifecycleState,
        currentRevisionID: KnowledgeConceptRevisionID,
        createdAt: Date,
        modifiedAt: Date,
        deletedAt: Date?,
        revision: Int64
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.documentID = documentID
        self.type = type
        self.title = title
        self.description = description
        self.resourceURI = resourceURI
        self.creatorActorID = creatorActorID
        self.lifecycleState = lifecycleState
        self.currentRevisionID = currentRevisionID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
        self.revision = revision
    }
}

public extension KnowledgeConceptRevision {
    init(
        _ id: KnowledgeConceptRevisionID,
        conceptID: KnowledgeConceptID,
        documentRevisionID: DocumentRevisionID,
        metadataJSON: String,
        parentRevisionID: KnowledgeConceptRevisionID?,
        authorActorID: ActorID,
        contentHash: String,
        createdAt: Date
    ) {
        self.id = id
        self.conceptID = conceptID
        self.documentRevisionID = documentRevisionID
        self.metadataJSON = metadataJSON
        self.parentRevisionID = parentRevisionID
        self.authorActorID = authorActorID
        self.contentHash = contentHash
        self.createdAt = createdAt
    }
}

public extension KnowledgeReference {
    init(
        _ id: ReferenceID,
        workspaceID: WorkspaceID,
        sourceKind: ReferenceTargetKind,
        sourceID: UUID,
        sourceRevisionID: UUID?,
        targetKind: ReferenceTargetKind,
        targetID: UUID,
        targetRevisionID: UUID?,
        relation: ReferenceRelation,
        anchorJSON: String?,
        createdAt: Date,
        deletedAt: Date?
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.sourceRevisionID = sourceRevisionID
        self.targetKind = targetKind
        self.targetID = targetID
        self.targetRevisionID = targetRevisionID
        self.relation = relation
        self.anchorJSON = anchorJSON
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}

public extension PublicationPolicy {
    init(
        _ id: PublicationPolicyID,
        workspaceID: WorkspaceID,
        visibility: PublicationVisibility,
        ownershipBasis: OwnershipBasis,
        commercialUse: CommercialUse,
        attributionRequired: Bool,
        attributionText: String?,
        verificationStatus: VerificationStatus,
        sensitivity: PublicationSensitivity,
        revision: Int64
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.visibility = visibility
        self.ownershipBasis = ownershipBasis
        self.commercialUse = commercialUse
        self.attributionRequired = attributionRequired
        self.attributionText = attributionText
        self.verificationStatus = verificationStatus
        self.sensitivity = sensitivity
        self.revision = revision
    }
}

public extension Bundle {
    init(
        _ id: BundleID,
        workspaceID: WorkspaceID,
        creatorActorID: ActorID,
        title: String,
        lifecycleState: BundleLifecycleState,
        createdAt: Date,
        modifiedAt: Date,
        revision: Int64
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.creatorActorID = creatorActorID
        self.title = title
        self.lifecycleState = lifecycleState
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.revision = revision
    }
}

public extension BundleDraft {
    init(
        _ id: BundleDraftID,
        bundleID: BundleID,
        revision: Int64,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.bundleID = bundleID
        self.revision = revision
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public extension BundleDraftMember {
    init(
        _ targetKind: BundleMemberTargetKind,
        targetID: UUID,
        targetRevisionID: UUID,
        exportPath: String,
        role: String,
        rank: Int,
        publicationPolicyID: PublicationPolicyID
    ) {
        self.targetKind = targetKind
        self.targetID = targetID
        self.targetRevisionID = targetRevisionID
        self.exportPath = exportPath
        self.role = role
        self.rank = rank
        self.publicationPolicyID = publicationPolicyID
    }
}

public extension BundleVersion {
    init(
        _ id: BundleVersionID,
        bundleID: BundleID,
        semanticVersion: String,
        manifestVersion: Int,
        okfVersion: String,
        contentDigest: String,
        status: BundleVersionStatus,
        createdByActorID: ActorID,
        createdAt: Date
    ) {
        self.id = id
        self.bundleID = bundleID
        self.semanticVersion = semanticVersion
        self.manifestVersion = manifestVersion
        self.okfVersion = okfVersion
        self.contentDigest = contentDigest
        self.status = status
        self.createdByActorID = createdByActorID
        self.createdAt = createdAt
    }
}

public extension BundleMember {
    init(
        _ id: BundleMemberID,
        bundleVersionID: BundleVersionID,
        targetKind: BundleMemberTargetKind,
        targetID: UUID,
        targetRevisionID: UUID,
        exportPath: String,
        role: String,
        rank: Int
    ) {
        self.id = id
        self.bundleVersionID = bundleVersionID
        self.targetKind = targetKind
        self.targetID = targetID
        self.targetRevisionID = targetRevisionID
        self.exportPath = exportPath
        self.role = role
        self.rank = rank
    }
}

public extension BundleVersionSnapshot {
    init(_ version: BundleVersion, members: [BundleMember]) {
        self.version = version
        self.members = members
    }
}

public extension IntegrationEventEnvelope {
    init(
        _ eventID: IntegrationEventID,
        eventName: String,
        schemaVersion: Int,
        workspaceID: WorkspaceID,
        actorID: ActorID,
        aggregateKind: String,
        aggregateID: UUID,
        operationID: OperationID,
        occurredAt: Date,
        payload: Data
    ) {
        self.eventID = eventID
        self.eventName = eventName
        self.schemaVersion = schemaVersion
        self.workspaceID = workspaceID
        self.actorID = actorID
        self.aggregateKind = aggregateKind
        self.aggregateID = aggregateID
        self.operationID = operationID
        self.occurredAt = occurredAt
        self.payload = payload
    }
}
