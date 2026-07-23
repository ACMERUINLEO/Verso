import Foundation
import VersoDomain

public struct CreateActor: ApplicationCommand {
    public static let identifier = "actor.create.v1"
    public typealias Output = CommandMutationResult<Actor>

    public let workspaceID: WorkspaceID
    public let kind: ActorKind
    public let displayName: String
    public let operationID: OperationID

    public init(
        workspaceID: WorkspaceID,
        kind: ActorKind,
        displayName: String,
        operationID: OperationID = OperationID()
    ) {
        self.workspaceID = workspaceID
        self.kind = kind
        self.displayName = displayName
        self.operationID = operationID
    }
}

public struct RegisterDocumentRevision: ApplicationCommand {
    public static let identifier = "document.revision.register.v1"
    public typealias Output = CommandMutationResult<DocumentRevisionSnapshot>

    public let workspaceID: WorkspaceID
    public let documentID: DocumentID
    public let revisionID: DocumentRevisionID
    public let title: String
    public let contentRelativePath: String
    public let contentHash: String
    public let parentRevisionID: DocumentRevisionID?
    public let authorActorID: ActorID
    public let operationID: OperationID

    public init(
        workspaceID: WorkspaceID,
        documentID: DocumentID = DocumentID(),
        revisionID: DocumentRevisionID = DocumentRevisionID(),
        title: String,
        contentRelativePath: String,
        contentHash: String,
        parentRevisionID: DocumentRevisionID? = nil,
        authorActorID: ActorID,
        operationID: OperationID = OperationID()
    ) {
        self.workspaceID = workspaceID
        self.documentID = documentID
        self.revisionID = revisionID
        self.title = title
        self.contentRelativePath = contentRelativePath
        self.contentHash = contentHash
        self.parentRevisionID = parentRevisionID
        self.authorActorID = authorActorID
        self.operationID = operationID
    }
}

public struct CaptureSource: ApplicationCommand {
    public static let identifier = "source.capture.v1"
    public typealias Output = CommandMutationResult<SourceRecord>

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
    public let operationID: OperationID

    public init(
        workspaceID: WorkspaceID,
        kind: SourceKind,
        canonicalURL: String? = nil,
        title: String,
        originalCreator: String? = nil,
        capturedAt: Date = .now,
        contentHash: String? = nil,
        sourceAssetID: AssetID? = nil,
        snapshotRevisionID: DocumentRevisionID? = nil,
        licenseHint: String? = nil,
        createdByActorID: ActorID,
        operationID: OperationID = OperationID()
    ) {
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
        self.operationID = operationID
    }
}

public struct CreateKnowledgeConcept: ApplicationCommand {
    public static let identifier = "knowledge-concept.create.v1"
    public typealias Output = CommandMutationResult<KnowledgeConcept>

    public let workspaceID: WorkspaceID
    public let documentID: DocumentID
    public let documentRevisionID: DocumentRevisionID
    public let type: String
    public let title: String
    public let description: String
    public let resourceURI: String?
    public let metadataJSON: String
    public let sourceRecordIDs: [SourceRecordID]
    public let creatorActorID: ActorID
    public let publicationPolicy: PublicationPolicy
    public let operationID: OperationID

    public init(
        workspaceID: WorkspaceID,
        documentID: DocumentID,
        documentRevisionID: DocumentRevisionID,
        type: String,
        title: String,
        description: String,
        resourceURI: String? = nil,
        metadataJSON: String = "{}",
        sourceRecordIDs: [SourceRecordID] = [],
        creatorActorID: ActorID,
        publicationPolicy: PublicationPolicy,
        operationID: OperationID = OperationID()
    ) {
        self.workspaceID = workspaceID
        self.documentID = documentID
        self.documentRevisionID = documentRevisionID
        self.type = type
        self.title = title
        self.description = description
        self.resourceURI = resourceURI
        self.metadataJSON = metadataJSON
        self.sourceRecordIDs = sourceRecordIDs
        self.creatorActorID = creatorActorID
        self.publicationPolicy = publicationPolicy
        self.operationID = operationID
    }
}

public struct CreateBundleDraft: ApplicationCommand {
    public static let identifier = "bundle-draft.create.v1"
    public typealias Output = CommandMutationResult<BundleDraft>

    public let workspaceID: WorkspaceID
    public let title: String
    public let creatorActorID: ActorID
    public let members: [BundleDraftMember]
    public let operationID: OperationID

    public init(
        workspaceID: WorkspaceID,
        title: String,
        creatorActorID: ActorID,
        members: [BundleDraftMember],
        operationID: OperationID = OperationID()
    ) {
        self.workspaceID = workspaceID
        self.title = title
        self.creatorActorID = creatorActorID
        self.members = members
        self.operationID = operationID
    }
}

public struct FreezeBundleVersion: ApplicationCommand {
    public static let identifier = "bundle-version.freeze.v1"
    public typealias Output = CommandMutationResult<BundleVersionSnapshot>

    public let workspaceID: WorkspaceID
    public let draftID: BundleDraftID
    public let expectedDraftRevision: Int64
    public let semanticVersion: String
    public let manifestVersion: Int
    public let okfVersion: String
    public let actorID: ActorID
    public let operationID: OperationID

    public init(
        workspaceID: WorkspaceID,
        draftID: BundleDraftID,
        expectedDraftRevision: Int64,
        semanticVersion: String,
        manifestVersion: Int = 1,
        okfVersion: String = "0.1",
        actorID: ActorID,
        operationID: OperationID = OperationID()
    ) {
        self.workspaceID = workspaceID
        self.draftID = draftID
        self.expectedDraftRevision = expectedDraftRevision
        self.semanticVersion = semanticVersion
        self.manifestVersion = manifestVersion
        self.okfVersion = okfVersion
        self.actorID = actorID
        self.operationID = operationID
    }
}

public protocol KnowledgeAssetServicing: Sendable {
    func createActor(_ command: CreateActor) async throws -> CreateActor.Output
    func registerDocumentRevision(
        _ command: RegisterDocumentRevision
    ) async throws -> RegisterDocumentRevision.Output
    func captureSource(_ command: CaptureSource) async throws -> CaptureSource.Output
    func createKnowledgeConcept(
        _ command: CreateKnowledgeConcept
    ) async throws -> CreateKnowledgeConcept.Output
    func createBundleDraft(
        _ command: CreateBundleDraft
    ) async throws -> CreateBundleDraft.Output
    func freezeBundleVersion(
        _ command: FreezeBundleVersion
    ) async throws -> FreezeBundleVersion.Output
}

public enum KnowledgeAssetCommandRegistration {
    public static func install<Service: KnowledgeAssetServicing>(
        on bus: CommandBus,
        service: Service
    ) async throws {
        try await bus.register(CreateActor.self) {
            try await service.createActor($0)
        }
        try await bus.register(RegisterDocumentRevision.self) {
            try await service.registerDocumentRevision($0)
        }
        try await bus.register(CaptureSource.self) {
            try await service.captureSource($0)
        }
        try await bus.register(CreateKnowledgeConcept.self) {
            try await service.createKnowledgeConcept($0)
        }
        try await bus.register(CreateBundleDraft.self) {
            try await service.createBundleDraft($0)
        }
        try await bus.register(FreezeBundleVersion.self) {
            try await service.freezeBundleVersion($0)
        }
    }
}
