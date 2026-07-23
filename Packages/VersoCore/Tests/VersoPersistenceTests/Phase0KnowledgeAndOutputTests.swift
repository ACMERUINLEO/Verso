import CryptoKit
import Foundation
import Testing
import VersoApplication
import VersoBundleFormat
import VersoDomain
@testable import VersoPersistence

@Suite("Phase 0 knowledge and output vertical slices", .serialized)
struct Phase0KnowledgeAndOutputTests {
    @Test("Source to concept to frozen bundle round-trips through OKF")
    func knowledgeBundleRoundTrip() async throws {
        let root = phase0TemporaryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceLifecycleService()
        let fixture = try await makeKnowledgeFixture(service: service, root: root)
        let draft = try await service.createBundleDraft(
            CreateBundleDraft(
                workspaceID: fixture.workspace.id,
                title: "Phase 0 Bundle",
                creatorActorID: fixture.author.id,
                members: [
                    BundleDraftMember(
                        .concept,
                        targetID: fixture.concept.id.rawValue,
                        targetRevisionID: fixture.concept.currentRevisionID.rawValue,
                        exportPath: "concepts/foundation.md",
                        role: "primary",
                        rank: 0,
                        publicationPolicyID: fixture.policy.id
                    )
                ]
            )
        )
        let operationID = OperationID()
        let frozen = try await service.freezeBundleVersion(
            FreezeBundleVersion(
                workspaceID: fixture.workspace.id,
                draftID: draft.value.id,
                expectedDraftRevision: draft.value.revision,
                semanticVersion: "1.0.0",
                actorID: fixture.author.id,
                operationID: operationID
            )
        )
        let replay = try await service.freezeBundleVersion(
            FreezeBundleVersion(
                workspaceID: fixture.workspace.id,
                draftID: draft.value.id,
                expectedDraftRevision: draft.value.revision,
                semanticVersion: "1.0.0",
                actorID: fixture.author.id,
                operationID: operationID
            )
        )

        #expect(frozen.disposition == .applied)
        #expect(replay.disposition == .replayed)
        #expect(replay.value == frozen.value)
        #expect(frozen.value.members.count == 1)
        #expect(try await service.pendingIntegrationEventCount(
            for: fixture.workspace.id
        ) == 1)

        let artifact = try await service.bundleArtifact(
            workspaceID: fixture.workspace.id,
            versionID: frozen.value.version.id
        )
        #expect(artifact.manifest.contentDigest == frozen.value.version.contentDigest)
        #expect(OKFBundleFormat.validate(files: artifact.files).isValid)
        let imported = try OKFBundleFormat.importArtifact(files: artifact.files)
        let concepts = try OKFBundleFormat.concepts(from: imported)
        #expect(concepts.count == 1)
        #expect(concepts[0].conceptID == fixture.concept.id)
        #expect(concepts[0].revisionID == fixture.concept.currentRevisionID)
        #expect(concepts[0].sourceRecordIDs == [fixture.source.id])
        #expect(concepts[0].referenceIDs.count == 1)
        #expect(concepts[0].markdownBody.contains("Phase 0 body"))
        #expect(artifact.files["assets/manifest.json"] != nil)
        #expect(artifact.files["reports/validation.json"] != nil)
        #expect(artifact.files["reports/benchmark.json"] != nil)
        let serializedArtifact = artifact.files.values
            .map { String(decoding: $0, as: UTF8.self) }
            .joined()
            .lowercased()
        #expect(!serializedArtifact.contains(root.path.lowercased()))
        #expect(!serializedArtifact.contains("bookmark"))
        #expect(!serializedArtifact.contains("credential"))
        #expect(!serializedArtifact.contains("oauth"))
        #expect(!serializedArtifact.contains("api-key"))

        try Data("# Foundation\n\nLater edit must not change version 1.\n".utf8)
            .write(to: root.appending(path: "notes/foundation.md"))
        let afterEdit = try await service.bundleArtifact(
            workspaceID: fixture.workspace.id,
            versionID: frozen.value.version.id
        )
        #expect(afterEdit == artifact)

        let records = try await service.syncOutboxRecords(
            for: fixture.workspace.id
        )
        let serializedPayloads = records
            .map { String(decoding: $0.change.payload, as: UTF8.self) }
            .joined()
            .lowercased()
        #expect(!serializedPayloads.contains(root.path.lowercased()))
        #expect(!serializedPayloads.contains("phase 0 body"))
        #expect(!serializedPayloads.contains("bookmark"))
        #expect(!serializedPayloads.contains("credential"))
        let integrationPayloads = try await service.integrationEventPayloads(
            for: fixture.workspace.id
        )
        let serializedEvents = integrationPayloads
            .map { String(decoding: $0, as: UTF8.self) }
            .joined()
            .lowercased()
        #expect(!serializedEvents.contains(root.path.lowercased()))
        #expect(!serializedEvents.contains("phase 0 body"))
        #expect(!serializedEvents.contains("bookmark"))
        #expect(!serializedEvents.contains("token"))
        #expect(!serializedEvents.contains("credential"))

        _ = try await service.closeWorkspace(id: fixture.workspace.id)
        guard case .ready = await service.openWorkspace(
            at: WorkspaceLocation(rawValue: root.path)
        ) else {
            Issue.record("Expected frozen bundle workspace to reopen")
            return
        }
        let rebuilt = try await service.bundleArtifact(
            workspaceID: fixture.workspace.id,
            versionID: frozen.value.version.id
        )
        #expect(rebuilt.manifest.contentDigest == artifact.manifest.contentDigest)
    }

    @Test("Private publication policy blocks BundleVersion before artifact persistence")
    func privatePolicyBlocksFreeze() async throws {
        let root = phase0TemporaryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceLifecycleService()
        let fixture = try await makeKnowledgeFixture(service: service, root: root)
        let privatePolicy = PublicationPolicy(
            PublicationPolicyID(),
            workspaceID: fixture.workspace.id,
            visibility: .private,
            ownershipBasis: .original,
            commercialUse: .unknown,
            attributionRequired: false,
            attributionText: nil,
            verificationStatus: .reviewed,
            sensitivity: .normal,
            revision: 1
        )
        let privateConcept = try await service.createKnowledgeConcept(
            CreateKnowledgeConcept(
                workspaceID: fixture.workspace.id,
                documentID: fixture.document.documentID,
                documentRevisionID: fixture.document.revisionID,
                type: "concept",
                title: "Private concept",
                description: "Must not enter an artifact.",
                metadataJSON: "{}",
                sourceRecordIDs: [fixture.source.id],
                creatorActorID: fixture.author.id,
                publicationPolicy: privatePolicy
            )
        ).value
        let draft = try await service.createBundleDraft(
            CreateBundleDraft(
                workspaceID: fixture.workspace.id,
                title: "Private Bundle",
                creatorActorID: fixture.author.id,
                members: [
                    BundleDraftMember(
                        .concept,
                        targetID: privateConcept.id.rawValue,
                        targetRevisionID: privateConcept.currentRevisionID.rawValue,
                        exportPath: "concepts/private.md",
                        role: "primary",
                        rank: 0,
                        publicationPolicyID: privatePolicy.id
                    )
                ]
            )
        ).value

        await #expect(throws: KnowledgeAssetError.privateContent) {
            _ = try await service.freezeBundleVersion(
                FreezeBundleVersion(
                    workspaceID: fixture.workspace.id,
                    draftID: draft.id,
                    expectedDraftRevision: draft.revision,
                    semanticVersion: "1.0.0",
                    actorID: fixture.author.id
                )
            )
        }
        #expect(try await service.pendingIntegrationEventCount(
            for: fixture.workspace.id
        ) == 0)
    }

    @Test("Output contribution validates, reviews, approves, and merges atomically")
    func outputHappyPathAndReplay() async throws {
        let root = phase0TemporaryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceLifecycleService()
        let fixture = try await makeKnowledgeFixture(service: service, root: root)
        let output = try await makeOutput(service: service, fixture: fixture)
        let approved = try await makeApprovedContribution(
            service: service,
            fixture: fixture,
            output: output.value,
            title: "Contribution A"
        )
        let operationID = OperationID()
        let mergeCommand = MergeContribution(
            workspaceID: fixture.workspace.id,
            contributionID: approved.contribution.id,
            changeSetID: approved.changeSet.id,
            approvalID: approved.approval.id,
            expectedMainRevisionID: output.value.currentRevisionID,
            expectedContributionRevision: approved.contribution.revision,
            actorID: fixture.reviewer.id,
            operationID: operationID
        )
        let merged = try await service.mergeContribution(mergeCommand)
        let replay = try await service.mergeContribution(mergeCommand)

        #expect(merged.disposition == .applied)
        #expect(replay.disposition == .replayed)
        #expect(replay.value == merged.value)
        #expect(
            merged.value.mergeRecord.mainBeforeRevisionID
                == output.value.currentRevisionID
        )
        #expect(
            merged.value.outputRevision.id
                == merged.value.mergeRecord.mainAfterRevisionID
        )
        #expect(try await service.mergeRecordCount(
            for: fixture.workspace.id
        ) == 1)
        #expect(try await service.pendingIntegrationEventCount(
            for: fixture.workspace.id
        ) == 1)
        let currentOutput = try await service.output(
            workspaceID: fixture.workspace.id,
            id: output.value.id
        )
        #expect(currentOutput.currentRevisionID == merged.value.outputRevision.id)
        #expect(currentOutput.revision == 2)

        _ = try await service.closeWorkspace(id: fixture.workspace.id)
        guard case .ready = await service.openWorkspace(
            at: WorkspaceLocation(rawValue: root.path)
        ) else {
            Issue.record("Expected merged output workspace to reopen")
            return
        }
        let reopenedOutput = try await service.output(
            workspaceID: fixture.workspace.id,
            id: output.value.id
        )
        #expect(reopenedOutput.currentRevisionID == merged.value.outputRevision.id)

        await #expect(throws: PersistenceError.operationIDConflict(operationID)) {
            try await service.mergeContribution(
                MergeContribution(
                    workspaceID: fixture.workspace.id,
                    contributionID: approved.contribution.id,
                    changeSetID: approved.changeSet.id,
                    approvalID: ApprovalID(),
                    expectedMainRevisionID: output.value.currentRevisionID,
                    expectedContributionRevision: approved.contribution.revision,
                    actorID: fixture.reviewer.id,
                    operationID: operationID
                )
            )
        }
    }

    @Test("AI approval and unresolved blocking findings fail closed")
    func approvalGates() async throws {
        let root = phase0TemporaryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceLifecycleService()
        let fixture = try await makeKnowledgeFixture(service: service, root: root)
        let output = try await makeOutput(service: service, fixture: fixture)
        let contribution = try await service.createContribution(
            CreateContribution(
                workspaceID: fixture.workspace.id,
                outputID: output.value.id,
                title: "Gated",
                intent: "Verify approval gates",
                actorID: fixture.author.id
            )
        )
        let changeSet = try await service.submitChangeSet(
            SubmitChangeSet(
                workspaceID: fixture.workspace.id,
                contributionID: contribution.value.id,
                expectedContributionRevision: 1,
                proposedMembers: [fixture.outputMember],
                actorID: fixture.author.id
            )
        )
        _ = try await service.recordValidationRun(
            RecordValidationRun(
                workspaceID: fixture.workspace.id,
                changeSetID: changeSet.value.id,
                actorID: fixture.reviewer.id
            )
        )
        await #expect(throws: OutputMainlineError.actorCannotApprove) {
            try await service.recordReview(
                RecordReview(
                    workspaceID: fixture.workspace.id,
                    changeSetID: changeSet.value.id,
                    reviewerActorID: fixture.reviewer.id,
                    reviewerKind: .ai,
                    decision: .approve
                )
            )
        }
        _ = try await service.recordReview(
            RecordReview(
                workspaceID: fixture.workspace.id,
                changeSetID: changeSet.value.id,
                reviewerActorID: fixture.reviewer.id,
                reviewerKind: .human,
                decision: .comment,
                findings: [
                    ReviewFindingDraft(
                        severity: .blocking,
                        message: "Blocking review finding."
                    )
                ]
            )
        )
        let reviewing = try await service.contribution(
            workspaceID: fixture.workspace.id,
            id: contribution.value.id
        )
        await #expect(throws: OutputMainlineError.blockingValidation) {
            try await service.approveChangeSet(
                ApproveChangeSet(
                    workspaceID: fixture.workspace.id,
                    contributionID: contribution.value.id,
                    changeSetID: changeSet.value.id,
                    expectedContributionRevision: reviewing.revision,
                    actorID: fixture.reviewer.id
                )
            )
        }
    }

    @Test("A stale contribution cannot change mainline or append partial outbox facts")
    func staleMainlineConflict() async throws {
        let root = phase0TemporaryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceLifecycleService()
        let fixture = try await makeKnowledgeFixture(service: service, root: root)
        let output = try await makeOutput(service: service, fixture: fixture)
        let first = try await makeApprovedContribution(
            service: service,
            fixture: fixture,
            output: output.value,
            title: "First"
        )
        let second = try await makeApprovedContribution(
            service: service,
            fixture: fixture,
            output: output.value,
            title: "Second"
        )
        _ = try await service.mergeContribution(
            MergeContribution(
                workspaceID: fixture.workspace.id,
                contributionID: first.contribution.id,
                changeSetID: first.changeSet.id,
                approvalID: first.approval.id,
                expectedMainRevisionID: output.value.currentRevisionID,
                expectedContributionRevision: first.contribution.revision,
                actorID: fixture.reviewer.id
            )
        )
        let syncCount = try await service.pendingSyncChangeCount(
            for: fixture.workspace.id
        )
        let integrationCount = try await service.pendingIntegrationEventCount(
            for: fixture.workspace.id
        )

        await #expect(throws: OutputMainlineError.self) {
            try await service.mergeContribution(
                MergeContribution(
                    workspaceID: fixture.workspace.id,
                    contributionID: second.contribution.id,
                    changeSetID: second.changeSet.id,
                    approvalID: second.approval.id,
                    expectedMainRevisionID: output.value.currentRevisionID,
                    expectedContributionRevision: second.contribution.revision,
                    actorID: fixture.reviewer.id
                )
            )
        }
        #expect(try await service.mergeRecordCount(
            for: fixture.workspace.id
        ) == 1)
        #expect(try await service.pendingSyncChangeCount(
            for: fixture.workspace.id
        ) == syncCount)
        #expect(try await service.pendingIntegrationEventCount(
            for: fixture.workspace.id
        ) == integrationCount)
    }

    @Test("Injected merge failure rolls back facts and both outboxes, then retry succeeds")
    func mergeRollbackAndRetry() async throws {
        let root = phase0TemporaryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let deviceID = DeviceID()
        let preparation = WorkspaceLifecycleService(deviceID: deviceID)
        let fixture = try await makeKnowledgeFixture(service: preparation, root: root)
        let output = try await makeOutput(service: preparation, fixture: fixture)
        let approved = try await makeApprovedContribution(
            service: preparation,
            fixture: fixture,
            output: output.value,
            title: "Rollback"
        )
        _ = try await preparation.closeWorkspace(id: fixture.workspace.id)

        let service = WorkspaceLifecycleService(
            deviceID: deviceID,
            failureInjector: OneShotFailureInjector(
                points: [.databaseTransactionBeforeCommit]
            )
        )
        guard case .ready = await service.openWorkspace(
            at: WorkspaceLocation(rawValue: root.path)
        ) else {
            Issue.record("Expected workspace to reopen")
            return
        }
        let syncBefore = try await service.pendingSyncChangeCount(
            for: fixture.workspace.id
        )
        let integrationBefore = try await service.pendingIntegrationEventCount(
            for: fixture.workspace.id
        )
        let operationID = OperationID()
        let command = MergeContribution(
            workspaceID: fixture.workspace.id,
            contributionID: approved.contribution.id,
            changeSetID: approved.changeSet.id,
            approvalID: approved.approval.id,
            expectedMainRevisionID: output.value.currentRevisionID,
            expectedContributionRevision: approved.contribution.revision,
            actorID: fixture.reviewer.id,
            operationID: operationID
        )

        await #expect(
            throws: ReliabilityError.injected(.databaseTransactionBeforeCommit)
        ) {
            try await service.mergeContribution(command)
        }
        #expect(try await service.mergeRecordCount(
            for: fixture.workspace.id
        ) == 0)
        #expect(try await service.pendingSyncChangeCount(
            for: fixture.workspace.id
        ) == syncBefore)
        #expect(try await service.pendingIntegrationEventCount(
            for: fixture.workspace.id
        ) == integrationBefore)
        let unchanged = try await service.output(
            workspaceID: fixture.workspace.id,
            id: output.value.id
        )
        #expect(unchanged.currentRevisionID == output.value.currentRevisionID)

        let retry = try await service.mergeContribution(command)
        #expect(retry.disposition == .applied)
        #expect(try await service.mergeRecordCount(
            for: fixture.workspace.id
        ) == 1)
    }

    @Test("Requested changes produce a new immutable change-set sequence")
    func requestChangesAndResubmit() async throws {
        let root = phase0TemporaryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceLifecycleService()
        let fixture = try await makeKnowledgeFixture(service: service, root: root)
        let output = try await makeOutput(service: service, fixture: fixture)
        let contribution = try await service.createContribution(
            CreateContribution(
                workspaceID: fixture.workspace.id,
                outputID: output.value.id,
                title: "Revise",
                intent: "Exercise the state machine",
                actorID: fixture.author.id
            )
        )
        let first = try await service.submitChangeSet(
            SubmitChangeSet(
                workspaceID: fixture.workspace.id,
                contributionID: contribution.value.id,
                expectedContributionRevision: 1,
                proposedMembers: [fixture.outputMember],
                actorID: fixture.author.id
            )
        )
        _ = try await service.recordValidationRun(
            RecordValidationRun(
                workspaceID: fixture.workspace.id,
                changeSetID: first.value.id,
                actorID: fixture.reviewer.id
            )
        )
        let review = try await service.recordReview(
            RecordReview(
                workspaceID: fixture.workspace.id,
                changeSetID: first.value.id,
                reviewerActorID: fixture.reviewer.id,
                reviewerKind: .human,
                decision: .requestChanges,
                findings: [
                    ReviewFindingDraft(
                        severity: .warning,
                        message: "Clarify the structure."
                    )
                ]
            )
        )
        let reviewing = try await service.contribution(
            workspaceID: fixture.workspace.id,
            id: contribution.value.id
        )
        let requested = try await service.requestChanges(
            RequestChanges(
                workspaceID: fixture.workspace.id,
                contributionID: contribution.value.id,
                changeSetID: first.value.id,
                reviewID: review.value.id,
                expectedContributionRevision: reviewing.revision,
                actorID: fixture.reviewer.id
            )
        )
        #expect(requested.value.status == .changesRequested)
        let second = try await service.submitChangeSet(
            SubmitChangeSet(
                workspaceID: fixture.workspace.id,
                contributionID: contribution.value.id,
                expectedContributionRevision: requested.value.revision,
                proposedMembers: [fixture.outputMember],
                actorID: fixture.author.id
            )
        )
        #expect(second.value.sequence == 2)
        #expect(second.value.id != first.value.id)
        #expect(second.value.proposedSnapshotID != first.value.proposedSnapshotID)
    }
}

private struct Phase0Fixture {
    let workspace: Workspace
    let author: Actor
    let reviewer: Actor
    let document: DocumentRevisionSnapshot
    let source: SourceRecord
    let concept: KnowledgeConcept
    let policy: PublicationPolicy
    let outputMember: OutputMemberProposal
}

private struct ApprovedContributionFixture {
    let contribution: Contribution
    let changeSet: ChangeSet
    let approval: Approval
}

private func makeKnowledgeFixture(
    service: WorkspaceLifecycleService,
    root: URL
) async throws -> Phase0Fixture {
    let workspace = try await service.createWorkspace(
        name: "Phase 0",
        at: WorkspaceLocation(rawValue: root.path)
    )
    let author = try await service.createActor(
        CreateActor(
            workspaceID: workspace.id,
            kind: .person,
            displayName: "Author"
        )
    ).value
    let reviewer = try await service.createActor(
        CreateActor(
            workspaceID: workspace.id,
            kind: .person,
            displayName: "Reviewer"
        )
    ).value
    let relativePath = "notes/foundation.md"
    let contentURL = root.appending(path: relativePath)
    try FileManager.default.createDirectory(
        at: contentURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let content = Data("# Foundation\n\nPhase 0 body with traceable knowledge.\n".utf8)
    try content.write(to: contentURL)
    let contentHash = SHA256.hash(data: content)
        .map { String(format: "%02x", $0) }
        .joined()
    let document = try await service.registerDocumentRevision(
        RegisterDocumentRevision(
            workspaceID: workspace.id,
            title: "Foundation",
            contentRelativePath: relativePath,
            contentHash: contentHash,
            authorActorID: author.id
        )
    ).value
    let source = try await service.captureSource(
        CaptureSource(
            workspaceID: workspace.id,
            kind: .original,
            title: "Original notes",
            contentHash: contentHash,
            snapshotRevisionID: document.revisionID,
            createdByActorID: author.id
        )
    ).value
    let policy = PublicationPolicy(
        PublicationPolicyID(),
        workspaceID: workspace.id,
        visibility: .included,
        ownershipBasis: .original,
        commercialUse: .allowed,
        attributionRequired: false,
        attributionText: nil,
        verificationStatus: .reviewed,
        sensitivity: .normal,
        revision: 1
    )
    let concept = try await service.createKnowledgeConcept(
        CreateKnowledgeConcept(
            workspaceID: workspace.id,
            documentID: document.documentID,
            documentRevisionID: document.revisionID,
            type: "concept",
            title: "Foundation",
            description: "A traceable Phase 0 concept.",
            metadataJSON: #"{"tags":["phase0"],"extension-key":"preserved"}"#,
            sourceRecordIDs: [source.id],
            creatorActorID: author.id,
            publicationPolicy: policy
        )
    ).value
    return Phase0Fixture(
        workspace: workspace,
        author: author,
        reviewer: reviewer,
        document: document,
        source: source,
        concept: concept,
        policy: policy,
        outputMember: OutputMemberProposal(
            targetKind: .concept,
            targetID: concept.id.rawValue,
            targetRevisionID: concept.currentRevisionID.rawValue,
            role: "primary",
            rank: 0
        )
    )
}

private func makeOutput(
    service: WorkspaceLifecycleService,
    fixture: Phase0Fixture
) async throws -> CreateOutput.Output {
    try await service.createOutput(
        CreateOutput(
            workspaceID: fixture.workspace.id,
            title: "Mainline",
            purpose: "Verify Phase 0",
            audience: "Reviewers",
            outputType: "document",
            members: [fixture.outputMember],
            actorID: fixture.author.id
        )
    )
}

private func makeApprovedContribution(
    service: WorkspaceLifecycleService,
    fixture: Phase0Fixture,
    output: VersoDomain.Output,
    title: String
) async throws -> ApprovedContributionFixture {
    let created = try await service.createContribution(
        CreateContribution(
            workspaceID: fixture.workspace.id,
            outputID: output.id,
            title: title,
            intent: "Improve mainline",
            actorID: fixture.author.id
        )
    )
    let changeSet = try await service.submitChangeSet(
        SubmitChangeSet(
            workspaceID: fixture.workspace.id,
            contributionID: created.value.id,
            expectedContributionRevision: created.value.revision,
            proposedMembers: [fixture.outputMember],
            actorID: fixture.author.id
        )
    )
    let validation = try await service.recordValidationRun(
        RecordValidationRun(
            workspaceID: fixture.workspace.id,
            changeSetID: changeSet.value.id,
            actorID: fixture.reviewer.id
        )
    )
    #expect(validation.value.results.allSatisfy { $0.status == .passed })
    _ = try await service.recordReview(
        RecordReview(
            workspaceID: fixture.workspace.id,
            changeSetID: changeSet.value.id,
            reviewerActorID: fixture.reviewer.id,
            reviewerKind: .human,
            decision: .comment
        )
    )
    let reviewing = try await service.contribution(
        workspaceID: fixture.workspace.id,
        id: created.value.id
    )
    let approval = try await service.approveChangeSet(
        ApproveChangeSet(
            workspaceID: fixture.workspace.id,
            contributionID: created.value.id,
            changeSetID: changeSet.value.id,
            expectedContributionRevision: reviewing.revision,
            actorID: fixture.reviewer.id
        )
    )
    let approved = try await service.contribution(
        workspaceID: fixture.workspace.id,
        id: created.value.id
    )
    return ApprovedContributionFixture(
        contribution: approved,
        changeSet: changeSet.value,
        approval: approval.value
    )
}

private func phase0TemporaryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "verso-phase0-\(UUID().uuidString)")
}
