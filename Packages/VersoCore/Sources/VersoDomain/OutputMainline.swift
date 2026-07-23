import Foundation

public enum OutputMemberTargetKind: String, Codable, CaseIterable, Sendable {
    case document
    case concept
    case asset
}

public struct OutputRevisionMember: Codable, Equatable, Sendable {
    public let id: OutputRevisionMemberID
    public let outputRevisionID: OutputRevisionID
    public let targetKind: OutputMemberTargetKind
    public let targetID: UUID
    public let targetRevisionID: UUID
    public let role: String
    public let rank: Int
}

public struct OutputMemberProposal: Codable, Equatable, Sendable {
    public let targetKind: OutputMemberTargetKind
    public let targetID: UUID
    public let targetRevisionID: UUID
    public let role: String
    public let rank: Int

    public init(
        targetKind: OutputMemberTargetKind,
        targetID: UUID,
        targetRevisionID: UUID,
        role: String,
        rank: Int
    ) {
        self.targetKind = targetKind
        self.targetID = targetID
        self.targetRevisionID = targetRevisionID
        self.role = role
        self.rank = rank
    }
}

public struct OutputRevision: Codable, Equatable, Sendable {
    public let id: OutputRevisionID
    public let outputID: OutputID
    public let parentRevisionID: OutputRevisionID?
    public let manifestHash: String
    public let createdByActorID: ActorID
    public let createdAt: Date
    public let members: [OutputRevisionMember]
}

public struct Output: Codable, Equatable, Sendable {
    public let id: OutputID
    public let workspaceID: WorkspaceID
    public let title: String
    public let purpose: String
    public let audience: String
    public let outputType: String
    public let currentRevisionID: OutputRevisionID
    public let structureSchemaVersion: Int
    public let createdAt: Date
    public let modifiedAt: Date
    public let deletedAt: Date?
    public let revision: Int64
}

public enum ContributionStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case submitted
    case reviewing
    case changesRequested
    case approved
    case merged
    case closed

    public func canTransition(to target: ContributionStatus) -> Bool {
        switch (self, target) {
        case (.draft, .submitted),
             (.draft, .closed),
             (.submitted, .reviewing),
             (.submitted, .closed),
             (.reviewing, .changesRequested),
             (.reviewing, .approved),
             (.reviewing, .closed),
             (.changesRequested, .draft),
             (.changesRequested, .closed),
             (.approved, .merged),
             (.approved, .closed),
             (.merged, .closed):
            true
        default:
            false
        }
    }
}

public struct Contribution: Codable, Equatable, Sendable {
    public let id: ContributionID
    public let outputID: OutputID
    public let baseOutputRevisionID: OutputRevisionID
    public let title: String
    public let intent: String
    public let createdByActorID: ActorID
    public let status: ContributionStatus
    public let revision: Int64
    public let createdAt: Date
    public let modifiedAt: Date
    public let closedAt: Date?
}

public struct ChangeSet: Codable, Equatable, Sendable {
    public let id: ChangeSetID
    public let contributionID: ContributionID
    public let sequence: Int
    public let baseOutputRevisionID: OutputRevisionID
    public let proposedSnapshotID: OutputRevisionID
    public let submittedByActorID: ActorID
    public let submittedAt: Date
    public let status: String
}

public enum ValidationSeverity: String, Codable, CaseIterable, Sendable {
    case info
    case warning
    case blocking
}

public enum ValidationResultStatus: String, Codable, Sendable {
    case passed
    case failed
    case skipped
}

public struct ValidationRule: Codable, Equatable, Sendable {
    public let ruleID: String
    public let ruleVersion: Int
    public let category: String
    public let defaultSeverity: ValidationSeverity
}

public enum ValidationRunStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
}

public struct ValidationResult: Codable, Equatable, Sendable {
    public let id: ValidationResultID
    public let runID: ValidationRunID
    public let ruleID: String
    public let ruleVersion: Int
    public let severity: ValidationSeverity
    public let status: ValidationResultStatus
    public let targetID: UUID?
    public let anchorJSON: String?
    public let message: String
}

public struct ValidationRun: Codable, Equatable, Sendable {
    public let id: ValidationRunID
    public let changeSetID: ChangeSetID
    public let policyVersion: Int
    public let status: ValidationRunStatus
    public let startedAt: Date
    public let completedAt: Date?
    public let results: [ValidationResult]
}

public enum ReviewerKind: String, Codable, CaseIterable, Sendable {
    case human
    case ai
    case validator
}

public enum ReviewDecision: String, Codable, Sendable {
    case comment
    case requestChanges
    case approve
}

public struct Review: Codable, Equatable, Sendable {
    public let id: ReviewID
    public let changeSetID: ChangeSetID
    public let reviewerActorID: ActorID
    public let reviewerKind: ReviewerKind
    public let decision: ReviewDecision
    public let reviewedSnapshotID: OutputRevisionID
    public let createdAt: Date
}

public enum FindingResolutionStatus: String, Codable, Sendable {
    case open
    case resolved
    case dismissed
}

public struct ReviewFinding: Codable, Equatable, Sendable {
    public let id: ReviewFindingID
    public let reviewID: ReviewID
    public let severity: ValidationSeverity
    public let targetID: UUID?
    public let anchorJSON: String?
    public let message: String
    public let resolutionStatus: FindingResolutionStatus
}

public struct Approval: Codable, Equatable, Sendable {
    public let id: ApprovalID
    public let changeSetID: ChangeSetID
    public let snapshotID: OutputRevisionID
    public let approvedByActorID: ActorID
    public let createdAt: Date
    public let invalidatedAt: Date?

    public func isValid(
        for changeSetID: ChangeSetID,
        snapshotID: OutputRevisionID
    ) -> Bool {
        self.changeSetID == changeSetID
            && self.snapshotID == snapshotID
            && invalidatedAt == nil
    }
}

public struct MergeRecord: Codable, Equatable, Sendable {
    public let id: MergeRecordID
    public let contributionID: ContributionID
    public let changeSetID: ChangeSetID
    public let mainBeforeRevisionID: OutputRevisionID
    public let contributionHeadRevisionID: OutputRevisionID
    public let mainAfterRevisionID: OutputRevisionID
    public let approvalID: ApprovalID
    public let approvedByActorID: ActorID
    public let operationID: OperationID
    public let mergedAt: Date
}

public struct MergeContributionResult: Codable, Equatable, Sendable {
    public let outputRevision: OutputRevision
    public let mergeRecord: MergeRecord
}

public enum OutputMemberChangeKind: String, Codable, Sendable {
    case added
    case removed
    case moved
    case revisionChanged
}

public struct OutputMemberChange: Codable, Equatable, Sendable {
    public let kind: OutputMemberChangeKind
    public let targetKind: OutputMemberTargetKind
    public let targetID: UUID
    public let beforeRevisionID: UUID?
    public let afterRevisionID: UUID?
    public let beforeRank: Int?
    public let afterRank: Int?

    public init(
        kind: OutputMemberChangeKind,
        targetKind: OutputMemberTargetKind,
        targetID: UUID,
        beforeRevisionID: UUID?,
        afterRevisionID: UUID?,
        beforeRank: Int?,
        afterRank: Int?
    ) {
        self.kind = kind
        self.targetKind = targetKind
        self.targetID = targetID
        self.beforeRevisionID = beforeRevisionID
        self.afterRevisionID = afterRevisionID
        self.beforeRank = beforeRank
        self.afterRank = afterRank
    }
}

public struct MarkdownLineChange: Codable, Equatable, Sendable {
    public let targetID: UUID
    public let removedLines: [String]
    public let addedLines: [String]

    public init(
        targetID: UUID,
        removedLines: [String],
        addedLines: [String]
    ) {
        self.targetID = targetID
        self.removedLines = removedLines
        self.addedLines = addedLines
    }
}

public struct OutputRevisionDiff: Codable, Equatable, Sendable {
    public let memberChanges: [OutputMemberChange]
    public let addedReferenceIDs: [ReferenceID]
    public let removedReferenceIDs: [ReferenceID]
    public let provenanceChangedTargetIDs: [UUID]
    public let markdownChanges: [MarkdownLineChange]

    public init(
        memberChanges: [OutputMemberChange],
        addedReferenceIDs: [ReferenceID],
        removedReferenceIDs: [ReferenceID],
        provenanceChangedTargetIDs: [UUID],
        markdownChanges: [MarkdownLineChange]
    ) {
        self.memberChanges = memberChanges
        self.addedReferenceIDs = addedReferenceIDs
        self.removedReferenceIDs = removedReferenceIDs
        self.provenanceChangedTargetIDs = provenanceChangedTargetIDs
        self.markdownChanges = markdownChanges
    }
}

public enum OutputMainlineError: Error, Equatable, Sendable {
    case invalidStateTransition(
        from: ContributionStatus,
        to: ContributionStatus
    )
    case invalidOutputStructure
    case actorCannotApprove
    case selfApprovalForbidden
    case approvalSnapshotMismatch
    case approvalInvalidated
    case blockingValidation
    case staleMainline(
        expected: OutputRevisionID,
        actual: OutputRevisionID
    )
    case changeSetNotLatest
    case contributionAlreadyTerminal
}

public extension OutputRevisionMember {
    init(
        _ id: OutputRevisionMemberID,
        outputRevisionID: OutputRevisionID,
        targetKind: OutputMemberTargetKind,
        targetID: UUID,
        targetRevisionID: UUID,
        role: String,
        rank: Int
    ) {
        self.id = id
        self.outputRevisionID = outputRevisionID
        self.targetKind = targetKind
        self.targetID = targetID
        self.targetRevisionID = targetRevisionID
        self.role = role
        self.rank = rank
    }
}

public extension OutputRevision {
    init(
        _ id: OutputRevisionID,
        outputID: OutputID,
        parentRevisionID: OutputRevisionID?,
        manifestHash: String,
        createdByActorID: ActorID,
        createdAt: Date,
        members: [OutputRevisionMember]
    ) {
        self.id = id
        self.outputID = outputID
        self.parentRevisionID = parentRevisionID
        self.manifestHash = manifestHash
        self.createdByActorID = createdByActorID
        self.createdAt = createdAt
        self.members = members
    }
}

public extension Output {
    init(
        _ id: OutputID,
        workspaceID: WorkspaceID,
        title: String,
        purpose: String,
        audience: String,
        outputType: String,
        currentRevisionID: OutputRevisionID,
        structureSchemaVersion: Int,
        createdAt: Date,
        modifiedAt: Date,
        deletedAt: Date?,
        revision: Int64
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.title = title
        self.purpose = purpose
        self.audience = audience
        self.outputType = outputType
        self.currentRevisionID = currentRevisionID
        self.structureSchemaVersion = structureSchemaVersion
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
        self.revision = revision
    }
}

public extension Contribution {
    init(
        _ id: ContributionID,
        outputID: OutputID,
        baseOutputRevisionID: OutputRevisionID,
        title: String,
        intent: String,
        createdByActorID: ActorID,
        status: ContributionStatus,
        revision: Int64,
        createdAt: Date,
        modifiedAt: Date,
        closedAt: Date?
    ) {
        self.id = id
        self.outputID = outputID
        self.baseOutputRevisionID = baseOutputRevisionID
        self.title = title
        self.intent = intent
        self.createdByActorID = createdByActorID
        self.status = status
        self.revision = revision
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.closedAt = closedAt
    }
}

public extension ChangeSet {
    init(
        _ id: ChangeSetID,
        contributionID: ContributionID,
        sequence: Int,
        baseOutputRevisionID: OutputRevisionID,
        proposedSnapshotID: OutputRevisionID,
        submittedByActorID: ActorID,
        submittedAt: Date,
        status: String
    ) {
        self.id = id
        self.contributionID = contributionID
        self.sequence = sequence
        self.baseOutputRevisionID = baseOutputRevisionID
        self.proposedSnapshotID = proposedSnapshotID
        self.submittedByActorID = submittedByActorID
        self.submittedAt = submittedAt
        self.status = status
    }
}

public extension ValidationRule {
    init(
        _ ruleID: String,
        ruleVersion: Int,
        category: String,
        defaultSeverity: ValidationSeverity
    ) {
        self.ruleID = ruleID
        self.ruleVersion = ruleVersion
        self.category = category
        self.defaultSeverity = defaultSeverity
    }
}

public extension ValidationResult {
    init(
        _ id: ValidationResultID,
        runID: ValidationRunID,
        ruleID: String,
        ruleVersion: Int,
        severity: ValidationSeverity,
        status: ValidationResultStatus,
        targetID: UUID?,
        anchorJSON: String?,
        message: String
    ) {
        self.id = id
        self.runID = runID
        self.ruleID = ruleID
        self.ruleVersion = ruleVersion
        self.severity = severity
        self.status = status
        self.targetID = targetID
        self.anchorJSON = anchorJSON
        self.message = message
    }
}

public extension ValidationRun {
    init(
        _ id: ValidationRunID,
        changeSetID: ChangeSetID,
        policyVersion: Int,
        status: ValidationRunStatus,
        startedAt: Date,
        completedAt: Date?,
        results: [ValidationResult]
    ) {
        self.id = id
        self.changeSetID = changeSetID
        self.policyVersion = policyVersion
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.results = results
    }
}

public extension Review {
    init(
        _ id: ReviewID,
        changeSetID: ChangeSetID,
        reviewerActorID: ActorID,
        reviewerKind: ReviewerKind,
        decision: ReviewDecision,
        reviewedSnapshotID: OutputRevisionID,
        createdAt: Date
    ) {
        self.id = id
        self.changeSetID = changeSetID
        self.reviewerActorID = reviewerActorID
        self.reviewerKind = reviewerKind
        self.decision = decision
        self.reviewedSnapshotID = reviewedSnapshotID
        self.createdAt = createdAt
    }
}

public extension ReviewFinding {
    init(
        _ id: ReviewFindingID,
        reviewID: ReviewID,
        severity: ValidationSeverity,
        targetID: UUID?,
        anchorJSON: String?,
        message: String,
        resolutionStatus: FindingResolutionStatus
    ) {
        self.id = id
        self.reviewID = reviewID
        self.severity = severity
        self.targetID = targetID
        self.anchorJSON = anchorJSON
        self.message = message
        self.resolutionStatus = resolutionStatus
    }
}

public extension Approval {
    init(
        _ id: ApprovalID,
        changeSetID: ChangeSetID,
        snapshotID: OutputRevisionID,
        approvedByActorID: ActorID,
        createdAt: Date,
        invalidatedAt: Date?
    ) {
        self.id = id
        self.changeSetID = changeSetID
        self.snapshotID = snapshotID
        self.approvedByActorID = approvedByActorID
        self.createdAt = createdAt
        self.invalidatedAt = invalidatedAt
    }
}

public extension MergeRecord {
    init(
        _ id: MergeRecordID,
        contributionID: ContributionID,
        changeSetID: ChangeSetID,
        mainBeforeRevisionID: OutputRevisionID,
        contributionHeadRevisionID: OutputRevisionID,
        mainAfterRevisionID: OutputRevisionID,
        approvalID: ApprovalID,
        approvedByActorID: ActorID,
        operationID: OperationID,
        mergedAt: Date
    ) {
        self.id = id
        self.contributionID = contributionID
        self.changeSetID = changeSetID
        self.mainBeforeRevisionID = mainBeforeRevisionID
        self.contributionHeadRevisionID = contributionHeadRevisionID
        self.mainAfterRevisionID = mainAfterRevisionID
        self.approvalID = approvalID
        self.approvedByActorID = approvedByActorID
        self.operationID = operationID
        self.mergedAt = mergedAt
    }
}

public extension MergeContributionResult {
    init(_ outputRevision: OutputRevision, mergeRecord: MergeRecord) {
        self.outputRevision = outputRevision
        self.mergeRecord = mergeRecord
    }
}
