import Foundation
import GRDB
import VersoApplication
import VersoBundleFormat
import VersoDomain
import VersoSyncProtocol

private struct DocumentRevisionSyncPayload: Codable {
    let documentID: DocumentID
    let revisionID: DocumentRevisionID
    let contentHash: String
    let parentRevisionID: DocumentRevisionID?
    let authorActorID: ActorID
}

private struct BundleBuiltPayload: Codable {
    let bundleID: BundleID
    let bundleVersionID: BundleVersionID
    let semanticVersion: String
    let manifestVersion: Int
    let okfVersion: String
    let contentDigest: String
    let memberCount: Int
}

extension WorkspaceDatabase {
    func createActor(
        _ command: CreateActor,
        deviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> CreateActor.Output {
        try pool.write { database in
            let name = command.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw KnowledgeAssetError.invalidDisplayName
            }
            let fingerprint = Self.phase0Fingerprint([
                command.workspaceID.rawValue.uuidString,
                command.kind.rawValue,
                name
            ])
            if try Self.phase0Replay(
                database: database,
                operationID: command.operationID,
                sourceDeviceID: deviceID,
                commandName: CreateActor.identifier,
                fingerprint: fingerprint
            ) {
                return CommandMutationResult(
                    value: try Self.fetchActor(
                        database: database,
                        operationID: command.operationID
                    ),
                    operationID: command.operationID,
                    disposition: .replayed
                )
            }

            let now = Date()
            let actor = Actor(
                ActorID(),
                workspaceID: command.workspaceID,
                kind: command.kind,
                displayName: name,
                createdAt: now,
                modifiedAt: now,
                revision: 1
            )
            try database.execute(
                sql: """
                    INSERT INTO actors (
                        id, workspace_id, kind, display_name, created_at,
                        modified_at, revision, operation_id
                    ) VALUES (?, ?, ?, ?, ?, ?, 1, ?)
                    """,
                arguments: [
                    actor.id.rawValue.uuidString,
                    actor.workspaceID.rawValue.uuidString,
                    actor.kind.rawValue,
                    actor.displayName,
                    now.timeIntervalSince1970,
                    now.timeIntervalSince1970,
                    command.operationID.rawValue.uuidString
                ]
            )
            try Self.phase0InsertAppliedOperation(
                database: database,
                operationID: command.operationID,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                commandName: CreateActor.identifier,
                fingerprint: fingerprint,
                appliedAt: now
            )
            try Self.phase0InsertSyncChange(
                database: database,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                operationID: command.operationID,
                recordKind: .actor,
                recordID: actor.id.rawValue,
                baseRevision: 0,
                revision: 1,
                payload: actor,
                createdAt: now
            )
            if failBeforeCommit {
                throw ReliabilityError.injected(.databaseTransactionBeforeCommit)
            }
            return CommandMutationResult(
                value: actor,
                operationID: command.operationID,
                disposition: .applied
            )
        }
    }

    func registerDocumentRevision(
        _ command: RegisterDocumentRevision,
        deviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> RegisterDocumentRevision.Output {
        try pool.write { database in
            let relativePath = try Self.validatedRelativePath(command.contentRelativePath)
            let fingerprint = Self.phase0Fingerprint([
                command.workspaceID.rawValue.uuidString,
                command.documentID.rawValue.uuidString,
                command.revisionID.rawValue.uuidString,
                command.title,
                relativePath,
                command.contentHash,
                command.parentRevisionID?.rawValue.uuidString ?? "",
                command.authorActorID.rawValue.uuidString
            ])
            if try Self.phase0Replay(
                database: database,
                operationID: command.operationID,
                sourceDeviceID: deviceID,
                commandName: RegisterDocumentRevision.identifier,
                fingerprint: fingerprint
            ) {
                return CommandMutationResult(
                    value: try Self.fetchDocumentRevision(
                        database: database,
                        operationID: command.operationID
                    ),
                    operationID: command.operationID,
                    disposition: .replayed
                )
            }

            let now = Date()
            let existing = try Row.fetchOne(
                database,
                sql: "SELECT revision FROM documents WHERE id = ?",
                arguments: [command.documentID.rawValue.uuidString]
            )
            let documentRevision: Int64
            if let existing {
                let currentRevision: Int64 = existing["revision"]
                documentRevision = currentRevision + 1
                try database.execute(
                    sql: """
                        UPDATE documents
                        SET title = ?, current_revision_id = ?, modified_at = ?,
                            revision = ?
                        WHERE id = ? AND workspace_id = ?
                        """,
                    arguments: [
                        command.title,
                        command.revisionID.rawValue.uuidString,
                        now.timeIntervalSince1970,
                        documentRevision,
                        command.documentID.rawValue.uuidString,
                        command.workspaceID.rawValue.uuidString
                    ]
                )
                guard database.changesCount == 1 else {
                    throw PersistenceError.workspaceMetadataMissing
                }
            } else {
                documentRevision = 1
                try database.execute(
                    sql: """
                        INSERT INTO documents (
                            id, workspace_id, title, current_revision_id,
                            created_at, modified_at, revision, deleted_at,
                            operation_id
                        ) VALUES (?, ?, ?, ?, ?, ?, 1, NULL, ?)
                        """,
                    arguments: [
                        command.documentID.rawValue.uuidString,
                        command.workspaceID.rawValue.uuidString,
                        command.title,
                        command.revisionID.rawValue.uuidString,
                        now.timeIntervalSince1970,
                        now.timeIntervalSince1970,
                        command.operationID.rawValue.uuidString
                    ]
                )
            }
            try database.execute(
                sql: """
                    INSERT INTO document_revisions (
                        id, document_id, parent_revision_id, content_hash,
                        content_relative_path, author_actor_id, created_at,
                        operation_id
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    command.revisionID.rawValue.uuidString,
                    command.documentID.rawValue.uuidString,
                    command.parentRevisionID?.rawValue.uuidString,
                    command.contentHash,
                    relativePath,
                    command.authorActorID.rawValue.uuidString,
                    now.timeIntervalSince1970,
                    command.operationID.rawValue.uuidString
                ]
            )
            try Self.phase0InsertAppliedOperation(
                database: database,
                operationID: command.operationID,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                commandName: RegisterDocumentRevision.identifier,
                fingerprint: fingerprint,
                appliedAt: now
            )
            let payload = DocumentRevisionSyncPayload(
                documentID: command.documentID,
                revisionID: command.revisionID,
                contentHash: command.contentHash,
                parentRevisionID: command.parentRevisionID,
                authorActorID: command.authorActorID
            )
            try Self.phase0InsertSyncChange(
                database: database,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                operationID: command.operationID,
                recordKind: .document,
                recordID: command.documentID.rawValue,
                baseRevision: documentRevision - 1,
                revision: documentRevision,
                payload: payload,
                createdAt: now
            )
            if failBeforeCommit {
                throw ReliabilityError.injected(.databaseTransactionBeforeCommit)
            }
            let snapshot = DocumentRevisionSnapshot(
                command.documentID,
                revisionID: command.revisionID,
                workspaceID: command.workspaceID,
                title: command.title,
                contentRelativePath: relativePath,
                contentHash: command.contentHash,
                parentRevisionID: command.parentRevisionID,
                authorActorID: command.authorActorID,
                createdAt: now
            )
            return CommandMutationResult(
                value: snapshot,
                operationID: command.operationID,
                disposition: .applied
            )
        }
    }

    func captureSource(
        _ command: CaptureSource,
        deviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> CaptureSource.Output {
        try pool.write { database in
            let title = command.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw KnowledgeAssetError.invalidDisplayName
            }
            let fingerprint = Self.phase0Fingerprint([
                command.workspaceID.rawValue.uuidString,
                command.kind.rawValue,
                command.canonicalURL ?? "",
                title,
                command.originalCreator ?? "",
                String(command.capturedAt.timeIntervalSince1970),
                command.contentHash ?? "",
                command.snapshotRevisionID?.rawValue.uuidString ?? "",
                command.createdByActorID.rawValue.uuidString
            ])
            if try Self.phase0Replay(
                database: database,
                operationID: command.operationID,
                sourceDeviceID: deviceID,
                commandName: CaptureSource.identifier,
                fingerprint: fingerprint
            ) {
                return CommandMutationResult(
                    value: try Self.fetchSource(
                        database: database,
                        operationID: command.operationID
                    ),
                    operationID: command.operationID,
                    disposition: .replayed
                )
            }

            let source = SourceRecord(
                SourceRecordID(),
                workspaceID: command.workspaceID,
                kind: command.kind,
                canonicalURL: command.canonicalURL,
                title: title,
                originalCreator: command.originalCreator,
                capturedAt: command.capturedAt,
                contentHash: command.contentHash,
                sourceAssetID: command.sourceAssetID,
                snapshotRevisionID: command.snapshotRevisionID,
                licenseHint: command.licenseHint,
                createdByActorID: command.createdByActorID,
                revision: 1,
                deletedAt: nil
            )
            try database.execute(
                sql: """
                    INSERT INTO source_records (
                        id, workspace_id, kind, canonical_url, title,
                        original_creator, captured_at, content_hash,
                        source_asset_id, snapshot_revision_id, license_hint,
                        created_by_actor_id, revision, deleted_at, operation_id
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, NULL, ?)
                    """,
                arguments: [
                    source.id.rawValue.uuidString,
                    source.workspaceID.rawValue.uuidString,
                    source.kind.rawValue,
                    source.canonicalURL,
                    source.title,
                    source.originalCreator,
                    source.capturedAt.timeIntervalSince1970,
                    source.contentHash,
                    source.sourceAssetID?.rawValue.uuidString,
                    source.snapshotRevisionID?.rawValue.uuidString,
                    source.licenseHint,
                    source.createdByActorID.rawValue.uuidString,
                    command.operationID.rawValue.uuidString
                ]
            )
            try Self.phase0InsertAppliedOperation(
                database: database,
                operationID: command.operationID,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                commandName: CaptureSource.identifier,
                fingerprint: fingerprint,
                appliedAt: command.capturedAt
            )
            try Self.phase0InsertSyncChange(
                database: database,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                operationID: command.operationID,
                recordKind: .sourceRecord,
                recordID: source.id.rawValue,
                baseRevision: 0,
                revision: 1,
                payload: source,
                createdAt: command.capturedAt
            )
            if failBeforeCommit {
                throw ReliabilityError.injected(.databaseTransactionBeforeCommit)
            }
            return CommandMutationResult(
                value: source,
                operationID: command.operationID,
                disposition: .applied
            )
        }
    }

    func createKnowledgeConcept(
        _ command: CreateKnowledgeConcept,
        deviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> CreateKnowledgeConcept.Output {
        try pool.write { database in
            let type = command.type.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !type.isEmpty else {
                throw KnowledgeAssetError.invalidConceptType
            }
            let sortedSources = command.sourceRecordIDs
                .map(\.rawValue.uuidString)
                .sorted()
                .joined(separator: ",")
            let fingerprint = Self.phase0Fingerprint([
                command.workspaceID.rawValue.uuidString,
                command.documentID.rawValue.uuidString,
                command.documentRevisionID.rawValue.uuidString,
                type,
                command.title,
                command.description,
                command.resourceURI ?? "",
                command.metadataJSON,
                sortedSources,
                command.creatorActorID.rawValue.uuidString,
                command.publicationPolicy.id.rawValue.uuidString
            ])
            if try Self.phase0Replay(
                database: database,
                operationID: command.operationID,
                sourceDeviceID: deviceID,
                commandName: CreateKnowledgeConcept.identifier,
                fingerprint: fingerprint
            ) {
                return CommandMutationResult(
                    value: try Self.fetchConcept(
                        database: database,
                        operationID: command.operationID
                    ),
                    operationID: command.operationID,
                    disposition: .replayed
                )
            }
            guard try Int.fetchOne(
                database,
                sql: """
                    SELECT COUNT(*)
                    FROM document_revisions
                    WHERE id = ? AND document_id = ?
                    """,
                arguments: [
                    command.documentRevisionID.rawValue.uuidString,
                    command.documentID.rawValue.uuidString
                ]
            ) == 1 else {
                throw KnowledgeAssetError.missingDocumentRevision
            }
            guard command.publicationPolicy.workspaceID == command.workspaceID else {
                throw KnowledgeAssetError.publicationNotAllowed
            }

            let now = Date()
            let policyExists = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM publication_policies WHERE id = ?",
                arguments: [command.publicationPolicy.id.rawValue.uuidString]
            ) == 1
            if !policyExists {
                try Self.insertPublicationPolicy(
                    database: database,
                    policy: command.publicationPolicy,
                    operationID: command.operationID
                )
            }
            let documentHash: String = try String.fetchOne(
                database,
                sql: "SELECT content_hash FROM document_revisions WHERE id = ?",
                arguments: [command.documentRevisionID.rawValue.uuidString]
            ) ?? ""
            let conceptID = KnowledgeConceptID()
            let revisionID = KnowledgeConceptRevisionID()
            let concept = KnowledgeConcept(
                conceptID,
                workspaceID: command.workspaceID,
                documentID: command.documentID,
                type: type,
                title: command.title,
                description: command.description,
                resourceURI: command.resourceURI,
                creatorActorID: command.creatorActorID,
                lifecycleState: .active,
                currentRevisionID: revisionID,
                createdAt: now,
                modifiedAt: now,
                deletedAt: nil,
                revision: 1
            )
            try database.execute(
                sql: """
                    INSERT INTO knowledge_concepts (
                        id, workspace_id, document_id, type, title, description,
                        resource_uri, creator_actor_id, lifecycle_state,
                        current_revision_id, publication_policy_id, created_at,
                        modified_at, deleted_at, revision, operation_id
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, NULL, 1, ?)
                    """,
                arguments: [
                    concept.id.rawValue.uuidString,
                    concept.workspaceID.rawValue.uuidString,
                    concept.documentID.rawValue.uuidString,
                    concept.type,
                    concept.title,
                    concept.description,
                    concept.resourceURI,
                    concept.creatorActorID.rawValue.uuidString,
                    revisionID.rawValue.uuidString,
                    command.publicationPolicy.id.rawValue.uuidString,
                    now.timeIntervalSince1970,
                    now.timeIntervalSince1970,
                    command.operationID.rawValue.uuidString
                ]
            )
            try database.execute(
                sql: """
                    INSERT INTO knowledge_concept_revisions (
                        id, concept_id, document_revision_id, metadata_json,
                        parent_revision_id, author_actor_id, content_hash,
                        created_at, operation_id
                    ) VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?)
                    """,
                arguments: [
                    revisionID.rawValue.uuidString,
                    concept.id.rawValue.uuidString,
                    command.documentRevisionID.rawValue.uuidString,
                    command.metadataJSON,
                    command.creatorActorID.rawValue.uuidString,
                    documentHash,
                    now.timeIntervalSince1970,
                    command.operationID.rawValue.uuidString
                ]
            )
            for sourceID in command.sourceRecordIDs {
                try database.execute(
                    sql: """
                        INSERT INTO knowledge_references (
                            id, workspace_id, source_kind, source_id,
                            source_revision_id, target_kind, target_id,
                            target_revision_id, relation, anchor_json,
                            created_at, deleted_at, operation_id
                        ) VALUES (?, ?, 'knowledgeConcept', ?, ?, 'sourceRecord', ?,
                                  NULL, 'cites', NULL, ?, NULL, ?)
                        """,
                    arguments: [
                        ReferenceID().rawValue.uuidString,
                        command.workspaceID.rawValue.uuidString,
                        concept.id.rawValue.uuidString,
                        revisionID.rawValue.uuidString,
                        sourceID.rawValue.uuidString,
                        now.timeIntervalSince1970,
                        command.operationID.rawValue.uuidString
                    ]
                )
            }
            try Self.phase0InsertAppliedOperation(
                database: database,
                operationID: command.operationID,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                commandName: CreateKnowledgeConcept.identifier,
                fingerprint: fingerprint,
                appliedAt: now
            )
            if !policyExists {
                try Self.phase0InsertSyncChange(
                    database: database,
                    workspaceID: command.workspaceID,
                    sourceDeviceID: deviceID,
                    operationID: command.operationID,
                    recordKind: .publicationPolicy,
                    recordID: command.publicationPolicy.id.rawValue,
                    baseRevision: 0,
                    revision: command.publicationPolicy.revision,
                    payload: command.publicationPolicy,
                    createdAt: now
                )
            }
            let syncConcept = KnowledgeConcept(
                concept.id,
                workspaceID: concept.workspaceID,
                documentID: concept.documentID,
                type: concept.type,
                title: concept.title,
                description: "",
                resourceURI: concept.resourceURI,
                creatorActorID: concept.creatorActorID,
                lifecycleState: concept.lifecycleState,
                currentRevisionID: concept.currentRevisionID,
                createdAt: concept.createdAt,
                modifiedAt: concept.modifiedAt,
                deletedAt: concept.deletedAt,
                revision: concept.revision
            )
            try Self.phase0InsertSyncChange(
                database: database,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                operationID: command.operationID,
                recordKind: .knowledgeConcept,
                recordID: concept.id.rawValue,
                baseRevision: 0,
                revision: 1,
                payload: syncConcept,
                createdAt: now
            )
            if failBeforeCommit {
                throw ReliabilityError.injected(.databaseTransactionBeforeCommit)
            }
            return CommandMutationResult(
                value: concept,
                operationID: command.operationID,
                disposition: .applied
            )
        }
    }

    func createBundleDraft(
        _ command: CreateBundleDraft,
        deviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> CreateBundleDraft.Output {
        try pool.write { database in
            let memberFingerprint = command.members.sorted { $0.rank < $1.rank }.map {
                [
                    $0.targetKind.rawValue,
                    $0.targetID.uuidString,
                    $0.targetRevisionID.uuidString,
                    $0.exportPath,
                    $0.role,
                    String($0.rank),
                    $0.publicationPolicyID.rawValue.uuidString
                ].joined(separator: ":")
            }.joined(separator: ",")
            let fingerprint = Self.phase0Fingerprint([
                command.workspaceID.rawValue.uuidString,
                command.title,
                command.creatorActorID.rawValue.uuidString,
                memberFingerprint
            ])
            if try Self.phase0Replay(
                database: database,
                operationID: command.operationID,
                sourceDeviceID: deviceID,
                commandName: CreateBundleDraft.identifier,
                fingerprint: fingerprint
            ) {
                return CommandMutationResult(
                    value: try Self.fetchBundleDraft(
                        database: database,
                        operationID: command.operationID
                    ),
                    operationID: command.operationID,
                    disposition: .replayed
                )
            }
            for member in command.members {
                _ = try Self.validatedRelativePath(member.exportPath)
                guard member.targetKind == .concept else {
                    throw KnowledgeAssetError.missingConceptRevision
                }
                guard try Int.fetchOne(
                    database,
                    sql: """
                        SELECT COUNT(*)
                        FROM knowledge_concept_revisions
                        WHERE id = ? AND concept_id = ?
                        """,
                    arguments: [
                        member.targetRevisionID.uuidString,
                        member.targetID.uuidString
                    ]
                ) == 1 else {
                    throw KnowledgeAssetError.missingConceptRevision
                }
            }
            let now = Date()
            let bundleID = BundleID()
            let draftID = BundleDraftID()
            try database.execute(
                sql: """
                    INSERT INTO bundles (
                        id, workspace_id, creator_actor_id, title,
                        lifecycle_state, created_at, modified_at, revision,
                        operation_id
                    ) VALUES (?, ?, ?, ?, 'draft', ?, ?, 1, ?)
                    """,
                arguments: [
                    bundleID.rawValue.uuidString,
                    command.workspaceID.rawValue.uuidString,
                    command.creatorActorID.rawValue.uuidString,
                    command.title,
                    now.timeIntervalSince1970,
                    now.timeIntervalSince1970,
                    command.operationID.rawValue.uuidString
                ]
            )
            try database.execute(
                sql: """
                    INSERT INTO bundle_drafts (
                        id, bundle_id, revision, created_at, modified_at,
                        operation_id
                    ) VALUES (?, ?, 1, ?, ?, ?)
                    """,
                arguments: [
                    draftID.rawValue.uuidString,
                    bundleID.rawValue.uuidString,
                    now.timeIntervalSince1970,
                    now.timeIntervalSince1970,
                    command.operationID.rawValue.uuidString
                ]
            )
            for member in command.members {
                try database.execute(
                    sql: """
                        INSERT INTO bundle_draft_members (
                            draft_id, target_kind, target_id, target_revision_id,
                            export_path, role, rank, publication_policy_id
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        draftID.rawValue.uuidString,
                        member.targetKind.rawValue,
                        member.targetID.uuidString,
                        member.targetRevisionID.uuidString,
                        member.exportPath,
                        member.role,
                        member.rank,
                        member.publicationPolicyID.rawValue.uuidString
                    ]
                )
            }
            try Self.phase0InsertAppliedOperation(
                database: database,
                operationID: command.operationID,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                commandName: CreateBundleDraft.identifier,
                fingerprint: fingerprint,
                appliedAt: now
            )
            let draft = BundleDraft(
                draftID,
                bundleID: bundleID,
                revision: 1,
                createdAt: now,
                modifiedAt: now
            )
            try Self.phase0InsertSyncChange(
                database: database,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                operationID: command.operationID,
                recordKind: .bundle,
                recordID: bundleID.rawValue,
                baseRevision: 0,
                revision: 1,
                payload: draft,
                createdAt: now
            )
            if failBeforeCommit {
                throw ReliabilityError.injected(.databaseTransactionBeforeCommit)
            }
            return CommandMutationResult(
                value: draft,
                operationID: command.operationID,
                disposition: .applied
            )
        }
    }

    func freezeBundleVersion(
        _ command: FreezeBundleVersion,
        deviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> FreezeBundleVersion.Output {
        try pool.write { database in
            let fingerprint = Self.phase0Fingerprint([
                command.workspaceID.rawValue.uuidString,
                command.draftID.rawValue.uuidString,
                String(command.expectedDraftRevision),
                command.semanticVersion,
                String(command.manifestVersion),
                command.okfVersion,
                command.actorID.rawValue.uuidString
            ])
            if try Self.phase0Replay(
                database: database,
                operationID: command.operationID,
                sourceDeviceID: deviceID,
                commandName: FreezeBundleVersion.identifier,
                fingerprint: fingerprint
            ) {
                return CommandMutationResult(
                    value: try Self.fetchBundleVersionSnapshot(
                        database: database,
                        operationID: command.operationID
                    ),
                    operationID: command.operationID,
                    disposition: .replayed
                )
            }
            guard Self.isSemanticVersion(command.semanticVersion) else {
                throw KnowledgeAssetError.invalidSemanticVersion
            }
            guard let draftRow = try Row.fetchOne(
                database,
                sql: """
                    SELECT d.bundle_id, d.revision, b.title
                    FROM bundle_drafts d
                    JOIN bundles b ON b.id = d.bundle_id
                    WHERE d.id = ? AND b.workspace_id = ?
                    """,
                arguments: [
                    command.draftID.rawValue.uuidString,
                    command.workspaceID.rawValue.uuidString
                ]
            ) else {
                throw KnowledgeAssetError.missingConceptRevision
            }
            let draftRevision: Int64 = draftRow["revision"]
            guard draftRevision == command.expectedDraftRevision else {
                throw PersistenceError.revisionConflict(
                    expected: command.expectedDraftRevision,
                    actual: draftRevision
                )
            }
            let bundleID = BundleID(
                rawValue: try Self.phase0UUID(draftRow["bundle_id"])
            )
            let versionID = BundleVersionID()
            let now = Date()
            let build = try Self.buildBundleArtifact(
                database: database,
                layout: layout,
                draftID: command.draftID,
                bundleID: bundleID,
                bundleVersionID: versionID,
                semanticVersion: command.semanticVersion,
                manifestVersion: command.manifestVersion,
                okfVersion: command.okfVersion,
                title: draftRow["title"],
                createdAt: now
            )
            let version = BundleVersion(
                versionID,
                bundleID: bundleID,
                semanticVersion: command.semanticVersion,
                manifestVersion: command.manifestVersion,
                okfVersion: command.okfVersion,
                contentDigest: build.artifact.manifest.contentDigest,
                status: .frozen,
                createdByActorID: command.actorID,
                createdAt: now
            )
            try database.execute(
                sql: """
                    INSERT INTO bundle_versions (
                        id, bundle_id, semantic_version, manifest_version,
                        okf_version, content_digest, status,
                        created_by_actor_id, created_at, operation_id
                    ) VALUES (?, ?, ?, ?, ?, ?, 'frozen', ?, ?, ?)
                    """,
                arguments: [
                    version.id.rawValue.uuidString,
                    version.bundleID.rawValue.uuidString,
                    version.semanticVersion,
                    version.manifestVersion,
                    version.okfVersion,
                    version.contentDigest,
                    version.createdByActorID.rawValue.uuidString,
                    now.timeIntervalSince1970,
                    command.operationID.rawValue.uuidString
                ]
            )
            var members: [BundleMember] = []
            for source in build.members {
                let member = BundleMember(
                    BundleMemberID(),
                    bundleVersionID: versionID,
                    targetKind: source.targetKind,
                    targetID: source.targetID,
                    targetRevisionID: source.targetRevisionID,
                    exportPath: source.exportPath,
                    role: source.role,
                    rank: source.rank
                )
                members.append(member)
                try database.execute(
                    sql: """
                        INSERT INTO bundle_members (
                            id, bundle_version_id, target_kind, target_id,
                            target_revision_id, export_path, role, rank
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        member.id.rawValue.uuidString,
                        versionID.rawValue.uuidString,
                        member.targetKind.rawValue,
                        member.targetID.uuidString,
                        member.targetRevisionID.uuidString,
                        member.exportPath,
                        member.role,
                        member.rank
                    ]
                )
            }
            for path in build.artifact.files.keys.sorted() {
                let payload = build.artifact.files[path] ?? Data()
                try database.execute(
                    sql: """
                        INSERT INTO bundle_artifact_files (
                            bundle_version_id, path, payload, content_hash
                        ) VALUES (?, ?, ?, ?)
                        """,
                    arguments: [
                        versionID.rawValue.uuidString,
                        path,
                        payload,
                        Self.phase0SHA256(payload)
                    ]
                )
            }
            try database.execute(
                sql: """
                    UPDATE bundles
                    SET lifecycle_state = 'active', modified_at = ?,
                        revision = revision + 1
                    WHERE id = ?
                    """,
                arguments: [
                    now.timeIntervalSince1970,
                    bundleID.rawValue.uuidString
                ]
            )
            try Self.phase0InsertAppliedOperation(
                database: database,
                operationID: command.operationID,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                commandName: FreezeBundleVersion.identifier,
                fingerprint: fingerprint,
                appliedAt: now
            )
            try Self.phase0InsertSyncChange(
                database: database,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                operationID: command.operationID,
                recordKind: .bundleVersion,
                recordID: version.id.rawValue,
                baseRevision: 0,
                revision: 1,
                payload: version,
                createdAt: now
            )
            try Self.phase0InsertIntegrationEvent(
                database: database,
                eventName: "BundleBuilt",
                workspaceID: command.workspaceID,
                actorID: command.actorID,
                aggregateKind: "bundleVersion",
                aggregateID: version.id.rawValue,
                operationID: command.operationID,
                occurredAt: now,
                payload: BundleBuiltPayload(
                    bundleID: bundleID,
                    bundleVersionID: versionID,
                    semanticVersion: command.semanticVersion,
                    manifestVersion: command.manifestVersion,
                    okfVersion: command.okfVersion,
                    contentDigest: version.contentDigest,
                    memberCount: members.count
                )
            )
            if failBeforeCommit {
                throw ReliabilityError.injected(.databaseTransactionBeforeCommit)
            }
            return CommandMutationResult(
                value: try Self.fetchBundleVersionSnapshot(
                    database: database,
                    operationID: command.operationID
                ),
                operationID: command.operationID,
                disposition: .applied
            )
        }
    }

    func bundleArtifact(versionID: BundleVersionID) throws -> OKFArtifact {
        try pool.read { database in
            let storedFiles = try Row.fetchAll(
                database,
                sql: """
                    SELECT path, payload, content_hash
                    FROM bundle_artifact_files
                    WHERE bundle_version_id = ?
                    ORDER BY path
                    """,
                arguments: [versionID.rawValue.uuidString]
            )
            if !storedFiles.isEmpty {
                var files: [String: Data] = [:]
                for file in storedFiles {
                    let path: String = file["path"]
                    let payload: Data = file["payload"]
                    let expectedHash: String = file["content_hash"]
                    guard Self.phase0SHA256(payload) == expectedHash else {
                        throw KnowledgeAssetError.contentHashMismatch
                    }
                    files[path] = payload
                }
                return try OKFBundleFormat.importArtifact(files: files)
            }
            guard let row = try Row.fetchOne(
                database,
                sql: """
                    SELECT v.bundle_id, v.semantic_version, v.manifest_version,
                           v.okf_version, v.created_at, b.title
                    FROM bundle_versions v
                    JOIN bundles b ON b.id = v.bundle_id
                    WHERE v.id = ?
                    """,
                arguments: [versionID.rawValue.uuidString]
            ) else {
                throw KnowledgeAssetError.missingConceptRevision
            }
            let bundleID = BundleID(
                rawValue: try Self.phase0UUID(row["bundle_id"])
            )
            let members = try Row.fetchAll(
                database,
                sql: """
                    SELECT target_kind, target_id, target_revision_id,
                           export_path, role, rank, NULL AS publication_policy_id
                    FROM bundle_members
                    WHERE bundle_version_id = ?
                    ORDER BY rank, id
                    """,
                arguments: [versionID.rawValue.uuidString]
            )
            let concepts = try members.map {
                try Self.bundleConceptDocument(
                    database: database,
                    layout: layout,
                    memberRow: $0
                )
            }
            return try OKFBundleFormat.export(
                bundleID: bundleID,
                bundleVersionID: versionID,
                semanticVersion: row["semantic_version"],
                manifestVersion: row["manifest_version"],
                okfVersion: row["okf_version"],
                title: row["title"],
                createdAt: Self.phase0Date(row, "created_at"),
                concepts: concepts
            )
        }
    }

    private struct BundleBuild {
        let artifact: OKFArtifact
        let members: [BundleDraftMember]
    }

    private static func buildBundleArtifact(
        database: Database,
        layout: WorkspaceLayout,
        draftID: BundleDraftID,
        bundleID: BundleID,
        bundleVersionID: BundleVersionID,
        semanticVersion: String,
        manifestVersion: Int,
        okfVersion: String,
        title: String,
        createdAt: Date
    ) throws -> BundleBuild {
        let rows = try Row.fetchAll(
            database,
            sql: """
                SELECT target_kind, target_id, target_revision_id,
                       export_path, role, rank, publication_policy_id
                FROM bundle_draft_members
                WHERE draft_id = ?
                ORDER BY rank, target_id
                """,
            arguments: [draftID.rawValue.uuidString]
        )
        let members = try rows.map(Self.decodeBundleDraftMember)
        let concepts = try rows.map {
            try bundleConceptDocument(
                database: database,
                layout: layout,
                memberRow: $0
            )
        }
        let artifact = try OKFBundleFormat.export(
            bundleID: bundleID,
            bundleVersionID: bundleVersionID,
            semanticVersion: semanticVersion,
            manifestVersion: manifestVersion,
            okfVersion: okfVersion,
            title: title,
            createdAt: createdAt,
            concepts: concepts
        )
        guard OKFBundleFormat.validate(files: artifact.files).isValid else {
            throw KnowledgeAssetError.contentHashMismatch
        }
        return BundleBuild(artifact: artifact, members: members)
    }

    private static func bundleConceptDocument(
        database: Database,
        layout: WorkspaceLayout,
        memberRow: Row
    ) throws -> OKFConceptDocument {
        guard memberRow["target_kind"] as String == BundleMemberTargetKind.concept.rawValue,
              let row = try Row.fetchOne(
                database,
                sql: """
                    SELECT c.id AS concept_id, c.type, c.title, c.description,
                           c.resource_uri, c.modified_at, cr.id AS revision_id,
                           cr.metadata_json, cr.content_hash,
                           dr.content_relative_path, p.visibility, p.sensitivity
                    FROM knowledge_concepts c
                    JOIN knowledge_concept_revisions cr
                      ON cr.id = ?
                     AND cr.concept_id = c.id
                    JOIN document_revisions dr ON dr.id = cr.document_revision_id
                    JOIN publication_policies p ON p.id = c.publication_policy_id
                    WHERE c.id = ?
                    """,
                arguments: [
                    memberRow["target_revision_id"] as String,
                    memberRow["target_id"] as String
                ]
              ) else {
            throw KnowledgeAssetError.missingConceptRevision
        }
        guard row["visibility"] as String != PublicationVisibility.private.rawValue else {
            throw KnowledgeAssetError.privateContent
        }
        guard row["sensitivity"] as String != PublicationSensitivity.confidential.rawValue else {
            throw KnowledgeAssetError.sensitiveContent
        }
        let relativePath: String = row["content_relative_path"]
        let contentURL = try contentURL(layout: layout, relativePath: relativePath)
        let data = try Data(contentsOf: contentURL)
        let expectedHash: String = row["content_hash"]
        guard phase0SHA256(data) == expectedHash else {
            throw KnowledgeAssetError.contentHashMismatch
        }
        guard let body = String(data: data, encoding: .utf8) else {
            throw OKFBundleFormatError.invalidUTF8(relativePath)
        }
        let metadataJSON: String = row["metadata_json"]
        let metadata = (try? JSONSerialization.jsonObject(
            with: Data(metadataJSON.utf8)
        )) as? [String: Any] ?? [:]
        let tags = metadata["tags"] as? [String] ?? []
        let unknown = metadata.compactMapValues { value -> String? in
            guard let string = value as? String else {
                return nil
            }
            return string
        }
        let conceptIDString: String = row["concept_id"]
        let referenceRows = try Row.fetchAll(
            database,
            sql: """
                SELECT id, target_id
                FROM knowledge_references
                WHERE source_kind = 'knowledgeConcept'
                  AND source_id = ?
                  AND target_kind = 'sourceRecord'
                  AND deleted_at IS NULL
                ORDER BY id
                """,
            arguments: [conceptIDString]
        )
        return OKFConceptDocument(
            conceptID: KnowledgeConceptID(
                rawValue: try phase0UUID(conceptIDString)
            ),
            revisionID: KnowledgeConceptRevisionID(
                rawValue: try phase0UUID(row["revision_id"])
            ),
            exportPath: memberRow["export_path"],
            type: row["type"],
            title: row["title"],
            description: row["description"],
            resourceURI: row["resource_uri"],
            tags: tags,
            modifiedAt: phase0Date(row, "modified_at"),
            sourceRecordIDs: try referenceRows.map {
                SourceRecordID(
                    rawValue: try phase0UUID($0["target_id"])
                )
            },
            referenceIDs: try referenceRows.map {
                ReferenceID(rawValue: try phase0UUID($0["id"]))
            },
            unknownFrontmatter: unknown,
            markdownBody: body
        )
    }

    private static func contentURL(
        layout: WorkspaceLayout,
        relativePath: String
    ) throws -> URL {
        let safePath = try validatedRelativePath(relativePath)
        let root = layout.root.standardizedFileURL
        let candidate = root.appending(path: safePath).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/"),
              !safePath.hasPrefix(".verso/") else {
            throw KnowledgeAssetError.invalidExportPath
        }
        return candidate
    }

    private static func validatedRelativePath(_ path: String) throws -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !normalized.contains("\0"),
              !normalized.split(separator: "/").contains("..") else {
            throw KnowledgeAssetError.invalidExportPath
        }
        return normalized
    }

    private static func isSemanticVersion(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy {
            !$0.isEmpty && $0.allSatisfy(\.isNumber)
        }
    }

    private static func insertPublicationPolicy(
        database: Database,
        policy: PublicationPolicy,
        operationID: OperationID
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO publication_policies (
                    id, workspace_id, visibility, ownership_basis,
                    commercial_use, attribution_required, attribution_text,
                    verification_status, sensitivity, revision, operation_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                policy.id.rawValue.uuidString,
                policy.workspaceID.rawValue.uuidString,
                policy.visibility.rawValue,
                policy.ownershipBasis.rawValue,
                policy.commercialUse.rawValue,
                policy.attributionRequired,
                policy.attributionText,
                policy.verificationStatus.rawValue,
                policy.sensitivity.rawValue,
                policy.revision,
                operationID.rawValue.uuidString
            ]
        )
    }

    private static func fetchActor(
        database: Database,
        operationID: OperationID
    ) throws -> Actor {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM actors WHERE operation_id = ?",
            arguments: [operationID.rawValue.uuidString]
        ) else {
            throw PersistenceError.invalidStoredIdentity
        }
        return Actor(
            ActorID(rawValue: try phase0UUID(row["id"])),
            workspaceID: WorkspaceID(rawValue: try phase0UUID(row["workspace_id"])),
            kind: ActorKind(rawValue: row["kind"]) ?? .person,
            displayName: row["display_name"],
            createdAt: phase0Date(row, "created_at"),
            modifiedAt: phase0Date(row, "modified_at"),
            revision: row["revision"]
        )
    }

    private static func fetchDocumentRevision(
        database: Database,
        operationID: OperationID
    ) throws -> DocumentRevisionSnapshot {
        guard let row = try Row.fetchOne(
            database,
            sql: """
                SELECT dr.*, d.workspace_id, d.title
                FROM document_revisions dr
                JOIN documents d ON d.id = dr.document_id
                WHERE dr.operation_id = ?
                """,
            arguments: [operationID.rawValue.uuidString]
        ) else {
            throw PersistenceError.invalidStoredIdentity
        }
        return DocumentRevisionSnapshot(
            DocumentID(rawValue: try phase0UUID(row["document_id"])),
            revisionID: DocumentRevisionID(rawValue: try phase0UUID(row["id"])),
            workspaceID: WorkspaceID(rawValue: try phase0UUID(row["workspace_id"])),
            title: row["title"],
            contentRelativePath: row["content_relative_path"],
            contentHash: row["content_hash"],
            parentRevisionID: (row["parent_revision_id"] as String?).map {
                DocumentRevisionID(rawValue: UUID(uuidString: $0)!)
            },
            authorActorID: ActorID(
                rawValue: try phase0UUID(row["author_actor_id"])
            ),
            createdAt: phase0Date(row, "created_at")
        )
    }

    private static func fetchSource(
        database: Database,
        operationID: OperationID
    ) throws -> SourceRecord {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM source_records WHERE operation_id = ?",
            arguments: [operationID.rawValue.uuidString]
        ) else {
            throw PersistenceError.invalidStoredIdentity
        }
        return SourceRecord(
            SourceRecordID(rawValue: try phase0UUID(row["id"])),
            workspaceID: WorkspaceID(rawValue: try phase0UUID(row["workspace_id"])),
            kind: SourceKind(rawValue: row["kind"]) ?? .original,
            canonicalURL: row["canonical_url"],
            title: row["title"],
            originalCreator: row["original_creator"],
            capturedAt: phase0Date(row, "captured_at"),
            contentHash: row["content_hash"],
            sourceAssetID: (row["source_asset_id"] as String?).flatMap(UUID.init(uuidString:)).map {
                AssetID(rawValue: $0)
            },
            snapshotRevisionID: (row["snapshot_revision_id"] as String?).flatMap(UUID.init(uuidString:)).map {
                DocumentRevisionID(rawValue: $0)
            },
            licenseHint: row["license_hint"],
            createdByActorID: ActorID(
                rawValue: try phase0UUID(row["created_by_actor_id"])
            ),
            revision: row["revision"],
            deletedAt: phase0OptionalDate(row, "deleted_at")
        )
    }

    private static func fetchConcept(
        database: Database,
        operationID: OperationID
    ) throws -> KnowledgeConcept {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM knowledge_concepts WHERE operation_id = ?",
            arguments: [operationID.rawValue.uuidString]
        ) else {
            throw PersistenceError.invalidStoredIdentity
        }
        return KnowledgeConcept(
            KnowledgeConceptID(rawValue: try phase0UUID(row["id"])),
            workspaceID: WorkspaceID(rawValue: try phase0UUID(row["workspace_id"])),
            documentID: DocumentID(rawValue: try phase0UUID(row["document_id"])),
            type: row["type"],
            title: row["title"],
            description: row["description"],
            resourceURI: row["resource_uri"],
            creatorActorID: ActorID(
                rawValue: try phase0UUID(row["creator_actor_id"])
            ),
            lifecycleState: KnowledgeConceptLifecycleState(
                rawValue: row["lifecycle_state"]
            ) ?? .draft,
            currentRevisionID: KnowledgeConceptRevisionID(
                rawValue: try phase0UUID(row["current_revision_id"])
            ),
            createdAt: phase0Date(row, "created_at"),
            modifiedAt: phase0Date(row, "modified_at"),
            deletedAt: phase0OptionalDate(row, "deleted_at"),
            revision: row["revision"]
        )
    }

    private static func fetchBundleDraft(
        database: Database,
        operationID: OperationID
    ) throws -> BundleDraft {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM bundle_drafts WHERE operation_id = ?",
            arguments: [operationID.rawValue.uuidString]
        ) else {
            throw PersistenceError.invalidStoredIdentity
        }
        return BundleDraft(
            BundleDraftID(rawValue: try phase0UUID(row["id"])),
            bundleID: BundleID(rawValue: try phase0UUID(row["bundle_id"])),
            revision: row["revision"],
            createdAt: phase0Date(row, "created_at"),
            modifiedAt: phase0Date(row, "modified_at")
        )
    }

    private static func fetchBundleVersionSnapshot(
        database: Database,
        operationID: OperationID
    ) throws -> BundleVersionSnapshot {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM bundle_versions WHERE operation_id = ?",
            arguments: [operationID.rawValue.uuidString]
        ) else {
            throw PersistenceError.invalidStoredIdentity
        }
        let versionID = BundleVersionID(rawValue: try phase0UUID(row["id"]))
        let version = BundleVersion(
            versionID,
            bundleID: BundleID(rawValue: try phase0UUID(row["bundle_id"])),
            semanticVersion: row["semantic_version"],
            manifestVersion: row["manifest_version"],
            okfVersion: row["okf_version"],
            contentDigest: row["content_digest"],
            status: BundleVersionStatus(rawValue: row["status"]) ?? .frozen,
            createdByActorID: ActorID(
                rawValue: try phase0UUID(row["created_by_actor_id"])
            ),
            createdAt: phase0Date(row, "created_at")
        )
        let members = try Row.fetchAll(
            database,
            sql: """
                SELECT *
                FROM bundle_members
                WHERE bundle_version_id = ?
                ORDER BY rank, id
                """,
            arguments: [versionID.rawValue.uuidString]
        ).map { member in
            BundleMember(
                BundleMemberID(rawValue: try phase0UUID(member["id"])),
                bundleVersionID: versionID,
                targetKind: BundleMemberTargetKind(
                    rawValue: member["target_kind"]
                ) ?? .concept,
                targetID: try phase0UUID(member["target_id"]),
                targetRevisionID: try phase0UUID(member["target_revision_id"]),
                exportPath: member["export_path"],
                role: member["role"],
                rank: member["rank"]
            )
        }
        return BundleVersionSnapshot(version, members: members)
    }

    private static func decodeBundleDraftMember(_ row: Row) throws -> BundleDraftMember {
        guard let kind = BundleMemberTargetKind(rawValue: row["target_kind"]) else {
            throw PersistenceError.invalidStoredIdentity
        }
        return BundleDraftMember(
            kind,
            targetID: try phase0UUID(row["target_id"]),
            targetRevisionID: try phase0UUID(row["target_revision_id"]),
            exportPath: row["export_path"],
            role: row["role"],
            rank: row["rank"],
            publicationPolicyID: PublicationPolicyID(
                rawValue: try phase0UUID(row["publication_policy_id"])
            )
        )
    }
}
