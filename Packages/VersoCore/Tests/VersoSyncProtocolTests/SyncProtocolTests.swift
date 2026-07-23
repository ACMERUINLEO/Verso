import Foundation
import Testing
import VersoDomain
@testable import VersoSyncProtocol

@Suite("Sync protocol boundary")
struct SyncProtocolTests {
    @Test("Every sync data category has an explicit classification")
    func explicitDataClassification() {
        let synced: Set<SyncDataCategory> = [
            .workspaceMetadata,
            .nodeMetadata,
            .immutableRevision,
            .tombstone,
            .operationIdentity,
            .actorFact,
            .creatorProfileFact,
            .sourceRecordFact,
            .knowledgeConceptFact,
            .referenceFact,
            .bundleFact,
            .publicationPolicyFact,
            .outputFact,
            .contributionFact,
            .changeSetFact,
            .validationFact,
            .reviewFact,
            .approvalFact,
            .mergeRecordFact,
            .integrationEventFact
        ]
        let localOnly: Set<SyncDataCategory> = [
            .securityScopedBookmark,
            .absoluteFilePath,
            .apiKey,
            .oauthToken,
            .deviceCredential,
            .jobLease,
            .localExecutionState,
            .unsavedInput,
            .selectionState,
            .windowState,
            .temporaryAIStream
        ]
        let rebuildable: Set<SyncDataCategory> = [
            .fullTextIndex,
            .embedding,
            .thumbnail,
            .previewArtifact,
            .diffPreview,
            .renderCache,
            .unsavedAISuggestion
        ]

        #expect(Set(SyncDataCategory.allCases) == synced.union(localOnly).union(rebuildable))
        #expect(synced.allSatisfy {
            SyncDataPolicy.classification(of: $0) == .syncedFact
        })
        #expect(localOnly.allSatisfy {
            SyncDataPolicy.classification(of: $0) == .localOnlyFact
        })
        #expect(rebuildable.allSatisfy {
            SyncDataPolicy.classification(of: $0) == .rebuildableCache
        })
    }

    @Test("Transport contract round-trips provider-neutral batches")
    func providerNeutralTransport() async throws {
        let workspaceID = WorkspaceID()
        let deviceID = DeviceID()
        let change = SyncChange(
            operationID: OperationID(),
            recordKind: .workspace,
            recordID: workspaceID.rawValue,
            mutation: .upsert,
            baseRevision: 0,
            revision: 1,
            payload: Data("{}".utf8)
        )
        let batch = SyncChangeBatch(
            workspaceID: workspaceID,
            sourceDeviceID: deviceID,
            changes: [change]
        )
        let transport = InMemorySyncTransport()

        await transport.push(batch)
        let page = await transport.pull(
            workspaceID: workspaceID,
            after: nil,
            limit: 10
        )

        #expect(page.batches == [batch])
        #expect(!page.hasMore)
    }
}

private actor InMemorySyncTransport: SyncTransport {
    private var batches: [SyncChangeBatch] = []

    func push(_ batch: SyncChangeBatch) {
        batches.append(batch)
    }

    func pull(
        workspaceID: WorkspaceID,
        after cursor: SyncCursor?,
        limit: Int
    ) -> SyncPullPage {
        let matching = batches.filter { $0.workspaceID == workspaceID }
        return SyncPullPage(
            batches: Array(matching.prefix(limit)),
            nextCursor: nil,
            hasMore: matching.count > limit
        )
    }
}
