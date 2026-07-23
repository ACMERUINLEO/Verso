import Foundation
import VersoDomain

public enum OutputDiffEngine {
    public static func diff(
        baseMembers: [OutputRevisionMember],
        proposedMembers: [OutputRevisionMember],
        baseReferenceIDs: Set<ReferenceID> = [],
        proposedReferenceIDs: Set<ReferenceID> = [],
        baseProvenance: [UUID: Set<SourceRecordID>] = [:],
        proposedProvenance: [UUID: Set<SourceRecordID>] = [:],
        baseMarkdown: [UUID: String] = [:],
        proposedMarkdown: [UUID: String] = [:]
    ) -> OutputRevisionDiff {
        let base = Dictionary(uniqueKeysWithValues: baseMembers.map {
            (identity($0), $0)
        })
        let proposed = Dictionary(uniqueKeysWithValues: proposedMembers.map {
            (identity($0), $0)
        })
        var memberChanges: [OutputMemberChange] = []
        for key in Set(base.keys).union(proposed.keys).sorted() {
            switch (base[key], proposed[key]) {
            case let (before?, nil):
                memberChanges.append(
                    change(.removed, before: before, after: nil)
                )
            case let (nil, after?):
                memberChanges.append(
                    change(.added, before: nil, after: after)
                )
            case let (before?, after?):
                if before.targetRevisionID != after.targetRevisionID {
                    memberChanges.append(
                        change(.revisionChanged, before: before, after: after)
                    )
                }
                if before.rank != after.rank {
                    memberChanges.append(
                        change(.moved, before: before, after: after)
                    )
                }
            case (nil, nil):
                break
            }
        }

        let provenanceKeys = Set(baseProvenance.keys)
            .union(proposedProvenance.keys)
            .filter { baseProvenance[$0, default: []] != proposedProvenance[$0, default: []] }
            .sorted { $0.uuidString < $1.uuidString }
        let markdownKeys = Set(baseMarkdown.keys).union(proposedMarkdown.keys)
        let markdownChanges = markdownKeys.compactMap { targetID -> MarkdownLineChange? in
            let before = normalizedLines(baseMarkdown[targetID] ?? "")
            let after = normalizedLines(proposedMarkdown[targetID] ?? "")
            guard before != after else {
                return nil
            }
            return MarkdownLineChange(
                targetID: targetID,
                removedLines: before.filter { !after.contains($0) },
                addedLines: after.filter { !before.contains($0) }
            )
        }.sorted { $0.targetID.uuidString < $1.targetID.uuidString }

        return OutputRevisionDiff(
            memberChanges: memberChanges,
            addedReferenceIDs: proposedReferenceIDs
                .subtracting(baseReferenceIDs)
                .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString },
            removedReferenceIDs: baseReferenceIDs
                .subtracting(proposedReferenceIDs)
                .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString },
            provenanceChangedTargetIDs: provenanceKeys,
            markdownChanges: markdownChanges
        )
    }

    private static func identity(_ member: OutputRevisionMember) -> String {
        "\(member.targetKind.rawValue):\(member.targetID.uuidString)"
    }

    private static func change(
        _ kind: OutputMemberChangeKind,
        before: OutputRevisionMember?,
        after: OutputRevisionMember?
    ) -> OutputMemberChange {
        let member = before ?? after!
        return OutputMemberChange(
            kind: kind,
            targetKind: member.targetKind,
            targetID: member.targetID,
            beforeRevisionID: before?.targetRevisionID,
            afterRevisionID: after?.targetRevisionID,
            beforeRank: before?.rank,
            afterRank: after?.rank
        )
    }

    private static func normalizedLines(_ markdown: String) -> [String] {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
}
