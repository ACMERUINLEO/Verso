import Foundation
import VersoDomain

public struct ReviewFindingDraft: Codable, Equatable, Sendable {
    public let severity: ValidationSeverity
    public let targetID: UUID?
    public let anchorJSON: String?
    public let message: String

    public init(
        severity: ValidationSeverity,
        targetID: UUID? = nil,
        anchorJSON: String? = nil,
        message: String
    ) {
        self.severity = severity
        self.targetID = targetID
        self.anchorJSON = anchorJSON
        self.message = message
    }
}

public struct CreateOutput: ApplicationCommand {
    public static let identifier = "output.create.v1"
    public typealias Output = CommandMutationResult<VersoDomain.Output>

    public let workspaceID: WorkspaceID
    public let title: String
    public let purpose: String
    public let audience: String
    public let outputType: String
    public let structureSchemaVersion: Int
    public let members: [OutputMemberProposal]
    public let actorID: ActorID
    public let operationID: OperationID

    public init(
        workspaceID: WorkspaceID,
        title: String,
        purpose: String,
        audience: String,
        outputType: String,
        structureSchemaVersion: Int = 1,
        members: [OutputMemberProposal],
        actorID: ActorID,
        operationID: OperationID = OperationID()
    ) {
        self.workspaceID = workspaceID
        self.title = title
        self.purpose = purpose
        self.audience = audience
        self.outputType = outputType
        self.structureSchemaVersion = structureSchemaVersion
        self.members = members
        self.actorID = actorID
        self.operationID = operationID
    }
}

public struct CreateContribution: ApplicationCommand {
    public static let identifier = "contribution.create.v1"
    public typealias Output = CommandMutationResult<Contribution>

    public let workspaceID: WorkspaceID
    public let outputID: OutputID
    public let title: String
    public let intent: String
    public let actorID: ActorID
    public let operationID: OperationID

    public init(
        workspaceID: WorkspaceID,
        outputID: OutputID,
        title: String,
        intent: String,
        actorID: ActorID,
        operationID: OperationID = OperationID()
    ) {
        self.workspaceID = workspaceID
        self.outputID = outputID
        self.title = title
        self.intent = intent
        self.actorID = actorID
        self.operationID = operationID
    }
}

public struct SubmitChangeSet: ApplicationCommand {
    public static let identifier = "changeset.submit.v1"
    public typealias Output = CommandMutationResult<ChangeSet>

    public let workspaceID: WorkspaceID
    public let contributionID: ContributionID
    public let expectedContributionRevision: Int64
    public let proposedMembers: [OutputMemberProposal]
    public let actorID: ActorID
    public let operationID: OperationID

    public init(
        workspaceID: WorkspaceID,
        contributionID: ContributionID,
        expectedContributionRevision: Int64,
        proposedMembers: [OutputMemberProposal],
        actorID: ActorID,
        operationID: OperationID = OperationID()
    ) {
        self.workspaceID = workspaceID
        self.contributionID = contributionID
        self.expectedContributionRevision = expectedContributionRevision
        self.proposedMembers = proposedMembers
        self.actorID = actorID
        self.operationID = operationID
    }
}

public struct RecordValidationRun: ApplicationCommand {
    public static let identifier = "validation.record.v1"
    public typealias Output = CommandMutationResult<ValidationRun>

    public let workspaceID: WorkspaceID
    public let changeSetID: ChangeSetID
    public let policyVersion: Int
    public let actorID: ActorID
    public let operationID: OperationID

    public init(
        workspaceID: WorkspaceID,
        changeSetID: ChangeSetID,
        policyVersion: Int = 1,
        actorID: ActorID,
        operationID: OperationID = OperationID()
    ) {
        self.workspaceID = workspaceID
        self.changeSetID = changeSetID
        self.policyVersion = policyVersion
        self.actorID = actorID
        self.operationID = operationID
    }
}

public struct RecordReview: ApplicationCommand {
    public static let identifier = "review.record.v1"
    public typealias Output = CommandMutationResult<Review>

    public let workspaceID: WorkspaceID
    public let changeSetID: ChangeSetID
    public let reviewerActorID: ActorID
    public let reviewerKind: ReviewerKind
    public let decision: ReviewDecision
    public let findings: [ReviewFindingDraft]
    public let operationID: OperationID

    public init(
        workspaceID: WorkspaceID,
        changeSetID: ChangeSetID,
        reviewerActorID: ActorID,
        reviewerKind: ReviewerKind,
        decision: ReviewDecision,
        findings: [ReviewFindingDraft] = [],
        operationID: OperationID = OperationID()
    ) {
        self.workspaceID = workspaceID
        self.changeSetID = changeSetID
        self.reviewerActorID = reviewerActorID
        self.reviewerKind = reviewerKind
        self.decision = decision
        self.findings = findings
        self.operationID = operationID
    }
}

public struct RequestChanges: ApplicationCommand {
    public static let identifier = "changeset.request-changes.v1"
    public typealias Output = CommandMutationResult<Contribution>

    public let workspaceID: WorkspaceID
    public let contributionID: ContributionID
    public let changeSetID: ChangeSetID
    public let reviewID: ReviewID
    public let expectedContributionRevision: Int64
    public let actorID: ActorID
    public let operationID: OperationID

    public init(
        workspaceID: WorkspaceID,
        contributionID: ContributionID,
        changeSetID: ChangeSetID,
        reviewID: ReviewID,
        expectedContributionRevision: Int64,
        actorID: ActorID,
        operationID: OperationID = OperationID()
    ) {
        self.workspaceID = workspaceID
        self.contributionID = contributionID
        self.changeSetID = changeSetID
        self.reviewID = reviewID
        self.expectedContributionRevision = expectedContributionRevision
        self.actorID = actorID
        self.operationID = operationID
    }
}

public struct ApproveChangeSet: ApplicationCommand {
    public static let identifier = "changeset.approve.v1"
    public typealias Output = CommandMutationResult<Approval>

    public let workspaceID: WorkspaceID
    public let contributionID: ContributionID
    public let changeSetID: ChangeSetID
    public let expectedContributionRevision: Int64
    public let actorID: ActorID
    public let operationID: OperationID

    public init(
        workspaceID: WorkspaceID,
        contributionID: ContributionID,
        changeSetID: ChangeSetID,
        expectedContributionRevision: Int64,
        actorID: ActorID,
        operationID: OperationID = OperationID()
    ) {
        self.workspaceID = workspaceID
        self.contributionID = contributionID
        self.changeSetID = changeSetID
        self.expectedContributionRevision = expectedContributionRevision
        self.actorID = actorID
        self.operationID = operationID
    }
}

public struct MergeContribution: ApplicationCommand {
    public static let identifier = "contribution.merge.v1"
    public typealias Output = CommandMutationResult<MergeContributionResult>

    public let workspaceID: WorkspaceID
    public let contributionID: ContributionID
    public let changeSetID: ChangeSetID
    public let approvalID: ApprovalID
    public let expectedMainRevisionID: OutputRevisionID
    public let expectedContributionRevision: Int64
    public let actorID: ActorID
    public let operationID: OperationID

    public init(
        workspaceID: WorkspaceID,
        contributionID: ContributionID,
        changeSetID: ChangeSetID,
        approvalID: ApprovalID,
        expectedMainRevisionID: OutputRevisionID,
        expectedContributionRevision: Int64,
        actorID: ActorID,
        operationID: OperationID = OperationID()
    ) {
        self.workspaceID = workspaceID
        self.contributionID = contributionID
        self.changeSetID = changeSetID
        self.approvalID = approvalID
        self.expectedMainRevisionID = expectedMainRevisionID
        self.expectedContributionRevision = expectedContributionRevision
        self.actorID = actorID
        self.operationID = operationID
    }
}

public struct CloseContribution: ApplicationCommand {
    public static let identifier = "contribution.close.v1"
    public typealias Output = CommandMutationResult<Contribution>

    public let workspaceID: WorkspaceID
    public let contributionID: ContributionID
    public let expectedContributionRevision: Int64
    public let actorID: ActorID
    public let operationID: OperationID

    public init(
        workspaceID: WorkspaceID,
        contributionID: ContributionID,
        expectedContributionRevision: Int64,
        actorID: ActorID,
        operationID: OperationID = OperationID()
    ) {
        self.workspaceID = workspaceID
        self.contributionID = contributionID
        self.expectedContributionRevision = expectedContributionRevision
        self.actorID = actorID
        self.operationID = operationID
    }
}

public protocol OutputMainlineServicing: Sendable {
    func createOutput(_ command: CreateOutput) async throws -> CreateOutput.Output
    func createContribution(
        _ command: CreateContribution
    ) async throws -> CreateContribution.Output
    func submitChangeSet(
        _ command: SubmitChangeSet
    ) async throws -> SubmitChangeSet.Output
    func recordValidationRun(
        _ command: RecordValidationRun
    ) async throws -> RecordValidationRun.Output
    func recordReview(_ command: RecordReview) async throws -> RecordReview.Output
    func requestChanges(
        _ command: RequestChanges
    ) async throws -> RequestChanges.Output
    func approveChangeSet(
        _ command: ApproveChangeSet
    ) async throws -> ApproveChangeSet.Output
    func mergeContribution(
        _ command: MergeContribution
    ) async throws -> MergeContribution.Output
    func closeContribution(
        _ command: CloseContribution
    ) async throws -> CloseContribution.Output
}

public enum OutputMainlineCommandRegistration {
    public static func install<Service: OutputMainlineServicing>(
        on bus: CommandBus,
        service: Service
    ) async throws {
        try await bus.register(CreateOutput.self) {
            try await service.createOutput($0)
        }
        try await bus.register(CreateContribution.self) {
            try await service.createContribution($0)
        }
        try await bus.register(SubmitChangeSet.self) {
            try await service.submitChangeSet($0)
        }
        try await bus.register(RecordValidationRun.self) {
            try await service.recordValidationRun($0)
        }
        try await bus.register(RecordReview.self) {
            try await service.recordReview($0)
        }
        try await bus.register(RequestChanges.self) {
            try await service.requestChanges($0)
        }
        try await bus.register(ApproveChangeSet.self) {
            try await service.approveChangeSet($0)
        }
        try await bus.register(MergeContribution.self) {
            try await service.mergeContribution($0)
        }
        try await bus.register(CloseContribution.self) {
            try await service.closeContribution($0)
        }
    }
}
