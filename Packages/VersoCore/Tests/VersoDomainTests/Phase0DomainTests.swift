import Foundation
import Testing
@testable import VersoDomain

@Suite("Phase 0 domain contracts")
struct Phase0DomainTests {
    @Test("Strong identifiers are Codable and Hashable")
    func identifierContracts() throws {
        let values: Set<ActorID> = [ActorID(), ActorID()]
        let encoded = try JSONEncoder().encode(values)
        let decoded = try JSONDecoder().decode(Set<ActorID>.self, from: encoded)
        #expect(decoded == values)
    }

    @Test("Contribution state machine accepts only documented transitions")
    func contributionStateMachine() {
        #expect(ContributionStatus.draft.canTransition(to: .submitted))
        #expect(ContributionStatus.submitted.canTransition(to: .reviewing))
        #expect(ContributionStatus.reviewing.canTransition(to: .changesRequested))
        #expect(ContributionStatus.changesRequested.canTransition(to: .draft))
        #expect(ContributionStatus.reviewing.canTransition(to: .approved))
        #expect(ContributionStatus.approved.canTransition(to: .merged))
        #expect(ContributionStatus.merged.canTransition(to: .closed))
        #expect(!ContributionStatus.draft.canTransition(to: .merged))
        #expect(!ContributionStatus.closed.canTransition(to: .draft))
    }

    @Test("Approval is bound to an exact change set and snapshot")
    func approvalBinding() {
        let changeSetID = ChangeSetID()
        let snapshotID = OutputRevisionID()
        let approval = Approval(
            ApprovalID(),
            changeSetID: changeSetID,
            snapshotID: snapshotID,
            approvedByActorID: ActorID(),
            createdAt: .now,
            invalidatedAt: nil
        )
        #expect(approval.isValid(for: changeSetID, snapshotID: snapshotID))
        #expect(!approval.isValid(for: ChangeSetID(), snapshotID: snapshotID))
        #expect(!approval.isValid(for: changeSetID, snapshotID: OutputRevisionID()))

        let invalidated = Approval(
            ApprovalID(),
            changeSetID: changeSetID,
            snapshotID: snapshotID,
            approvedByActorID: ActorID(),
            createdAt: .now,
            invalidatedAt: .now
        )
        #expect(!invalidated.isValid(for: changeSetID, snapshotID: snapshotID))
    }

    @Test("Frozen bundle and output snapshots retain exact member revisions")
    func immutableSnapshots() {
        let targetID = UUID()
        let firstRevision = UUID()
        let bundleVersionID = BundleVersionID()
        let bundle = BundleVersionSnapshot(
            BundleVersion(
                bundleVersionID,
                bundleID: BundleID(),
                semanticVersion: "1.0.0",
                manifestVersion: 1,
                okfVersion: "0.1",
                contentDigest: "digest",
                status: .frozen,
                createdByActorID: ActorID(),
                createdAt: .now
            ),
            members: [
                BundleMember(
                    BundleMemberID(),
                    bundleVersionID: bundleVersionID,
                    targetKind: .concept,
                    targetID: targetID,
                    targetRevisionID: firstRevision,
                    exportPath: "concepts/example.md",
                    role: "primary",
                    rank: 0
                )
            ]
        )
        let outputRevisionID = OutputRevisionID()
        let output = OutputRevision(
            outputRevisionID,
            outputID: OutputID(),
            parentRevisionID: nil,
            manifestHash: "hash",
            createdByActorID: ActorID(),
            createdAt: .now,
            members: [
                OutputRevisionMember(
                    OutputRevisionMemberID(),
                    outputRevisionID: outputRevisionID,
                    targetKind: .concept,
                    targetID: targetID,
                    targetRevisionID: firstRevision,
                    role: "primary",
                    rank: 0
                )
            ]
        )

        #expect(bundle.members[0].targetRevisionID == firstRevision)
        #expect(output.members[0].targetRevisionID == firstRevision)
    }
}
