import Foundation
import Testing
import VersoDomain
@testable import VersoApplication

@Suite("Output diff engine")
struct OutputDiffEngineTests {
    @Test("Member, reference, provenance, and Markdown changes are deterministic")
    func derivedDiff() {
        let outputID = OutputRevisionID()
        let targetID = UUID()
        let before = OutputRevisionMember(
            OutputRevisionMemberID(),
            outputRevisionID: outputID,
            targetKind: .concept,
            targetID: targetID,
            targetRevisionID: UUID(),
            role: "primary",
            rank: 0
        )
        let after = OutputRevisionMember(
            OutputRevisionMemberID(),
            outputRevisionID: OutputRevisionID(),
            targetKind: .concept,
            targetID: targetID,
            targetRevisionID: UUID(),
            role: "primary",
            rank: 2
        )
        let oldReference = ReferenceID()
        let newReference = ReferenceID()
        let oldSource = SourceRecordID()
        let newSource = SourceRecordID()

        let diff = OutputDiffEngine.diff(
            baseMembers: [before],
            proposedMembers: [after],
            baseReferenceIDs: [oldReference],
            proposedReferenceIDs: [newReference],
            baseProvenance: [targetID: [oldSource]],
            proposedProvenance: [targetID: [newSource]],
            baseMarkdown: [targetID: "old\nshared"],
            proposedMarkdown: [targetID: "new\nshared"]
        )

        #expect(diff.memberChanges.map(\.kind) == [.revisionChanged, .moved])
        #expect(diff.addedReferenceIDs == [newReference])
        #expect(diff.removedReferenceIDs == [oldReference])
        #expect(diff.provenanceChangedTargetIDs == [targetID])
        #expect(diff.markdownChanges.first?.removedLines == ["old"])
        #expect(diff.markdownChanges.first?.addedLines == ["new"])
    }
}
