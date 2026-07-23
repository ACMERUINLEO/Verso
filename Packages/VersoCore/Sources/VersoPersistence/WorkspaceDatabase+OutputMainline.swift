import Foundation
import GRDB
import VersoApplication
import VersoDomain
import VersoSyncProtocol

private struct OutputMergedPayload: Codable {
    let outputID: OutputID
    let contributionID: ContributionID
    let changeSetID: ChangeSetID
    let mainBeforeRevisionID: OutputRevisionID
    let mainAfterRevisionID: OutputRevisionID
    let approvalID: ApprovalID
}

extension WorkspaceDatabase {
    func createOutput(
        _ command: CreateOutput,
        deviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> CreateOutput.Output {
        try pool.write { database in
            try Self.validateOutputMembers(database: database, members: command.members)
            guard command.structureSchemaVersion > 0,
                  !command.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OutputMainlineError.invalidOutputStructure
            }
            let fingerprint = Self.outputFingerprint(command.members, prefix: [
                command.workspaceID.rawValue.uuidString,
                command.title,
                command.purpose,
                command.audience,
                command.outputType,
                String(command.structureSchemaVersion),
                command.actorID.rawValue.uuidString
            ])
            if try Self.phase0Replay(
                database: database,
                operationID: command.operationID,
                sourceDeviceID: deviceID,
                commandName: CreateOutput.identifier,
                fingerprint: fingerprint
            ) {
                return CommandMutationResult(
                    value: try Self.fetchOutput(
                        database: database,
                        operationID: command.operationID
                    ),
                    operationID: command.operationID,
                    disposition: .replayed
                )
            }
            let now = Date()
            let outputID = OutputID()
            let revisionID = OutputRevisionID()
            let manifestHash = Self.outputManifestHash(command.members)
            try database.execute(
                sql: """
                    INSERT INTO outputs (
                        id, workspace_id, title, purpose, audience, output_type,
                        current_revision_id, structure_schema_version,
                        created_at, modified_at, deleted_at, revision, operation_id
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 1, ?)
                    """,
                arguments: [
                    outputID.rawValue.uuidString,
                    command.workspaceID.rawValue.uuidString,
                    command.title,
                    command.purpose,
                    command.audience,
                    command.outputType,
                    revisionID.rawValue.uuidString,
                    command.structureSchemaVersion,
                    now.timeIntervalSince1970,
                    now.timeIntervalSince1970,
                    command.operationID.rawValue.uuidString
                ]
            )
            try Self.insertOutputRevision(
                database: database,
                id: revisionID,
                outputID: outputID,
                parentRevisionID: nil,
                manifestHash: manifestHash,
                actorID: command.actorID,
                createdAt: now,
                snapshotKind: "main",
                operationID: command.operationID,
                members: command.members
            )
            try Self.phase0InsertAppliedOperation(
                database: database,
                operationID: command.operationID,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                commandName: CreateOutput.identifier,
                fingerprint: fingerprint,
                appliedAt: now
            )
            let output = VersoDomain.Output(
                outputID,
                workspaceID: command.workspaceID,
                title: command.title,
                purpose: command.purpose,
                audience: command.audience,
                outputType: command.outputType,
                currentRevisionID: revisionID,
                structureSchemaVersion: command.structureSchemaVersion,
                createdAt: now,
                modifiedAt: now,
                deletedAt: nil,
                revision: 1
            )
            try Self.phase0InsertSyncChange(
                database: database,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                operationID: command.operationID,
                recordKind: .output,
                recordID: outputID.rawValue,
                baseRevision: 0,
                revision: 1,
                payload: output,
                createdAt: now
            )
            if failBeforeCommit {
                throw ReliabilityError.injected(.databaseTransactionBeforeCommit)
            }
            return CommandMutationResult(
                value: output,
                operationID: command.operationID,
                disposition: .applied
            )
        }
    }

    func createContribution(
        _ command: CreateContribution,
        deviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> CreateContribution.Output {
        try pool.write { database in
            let fingerprint = Self.phase0Fingerprint([
                command.workspaceID.rawValue.uuidString,
                command.outputID.rawValue.uuidString,
                command.title,
                command.intent,
                command.actorID.rawValue.uuidString
            ])
            if try Self.phase0Replay(
                database: database,
                operationID: command.operationID,
                sourceDeviceID: deviceID,
                commandName: CreateContribution.identifier,
                fingerprint: fingerprint
            ) {
                return CommandMutationResult(
                    value: try Self.fetchContribution(
                        database: database,
                        operationID: command.operationID
                    ),
                    operationID: command.operationID,
                    disposition: .replayed
                )
            }
            guard let outputRow = try Row.fetchOne(
                database,
                sql: """
                    SELECT current_revision_id
                    FROM outputs
                    WHERE id = ? AND workspace_id = ? AND deleted_at IS NULL
                    """,
                arguments: [
                    command.outputID.rawValue.uuidString,
                    command.workspaceID.rawValue.uuidString
                ]
            ) else {
                throw OutputMainlineError.invalidOutputStructure
            }
            let baseID = OutputRevisionID(
                rawValue: try Self.phase0UUID(outputRow["current_revision_id"])
            )
            let now = Date()
            let contribution = Contribution(
                ContributionID(),
                outputID: command.outputID,
                baseOutputRevisionID: baseID,
                title: command.title,
                intent: command.intent,
                createdByActorID: command.actorID,
                status: .draft,
                revision: 1,
                createdAt: now,
                modifiedAt: now,
                closedAt: nil
            )
            try database.execute(
                sql: """
                    INSERT INTO contributions (
                        id, output_id, base_output_revision_id, title, intent,
                        created_by_actor_id, status, revision, created_at,
                        modified_at, closed_at, operation_id
                    ) VALUES (?, ?, ?, ?, ?, ?, 'draft', 1, ?, ?, NULL, ?)
                    """,
                arguments: [
                    contribution.id.rawValue.uuidString,
                    contribution.outputID.rawValue.uuidString,
                    contribution.baseOutputRevisionID.rawValue.uuidString,
                    contribution.title,
                    contribution.intent,
                    contribution.createdByActorID.rawValue.uuidString,
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
                commandName: CreateContribution.identifier,
                fingerprint: fingerprint,
                appliedAt: now
            )
            try Self.phase0InsertSyncChange(
                database: database,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                operationID: command.operationID,
                recordKind: .contribution,
                recordID: contribution.id.rawValue,
                baseRevision: 0,
                revision: 1,
                payload: contribution,
                createdAt: now
            )
            if failBeforeCommit {
                throw ReliabilityError.injected(.databaseTransactionBeforeCommit)
            }
            return CommandMutationResult(
                value: contribution,
                operationID: command.operationID,
                disposition: .applied
            )
        }
    }

    func submitChangeSet(
        _ command: SubmitChangeSet,
        deviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> SubmitChangeSet.Output {
        try pool.write { database in
            try Self.validateOutputMembers(database: database, members: command.proposedMembers)
            let fingerprint = Self.outputFingerprint(command.proposedMembers, prefix: [
                command.workspaceID.rawValue.uuidString,
                command.contributionID.rawValue.uuidString,
                String(command.expectedContributionRevision),
                command.actorID.rawValue.uuidString
            ])
            if try Self.phase0Replay(
                database: database,
                operationID: command.operationID,
                sourceDeviceID: deviceID,
                commandName: SubmitChangeSet.identifier,
                fingerprint: fingerprint
            ) {
                return CommandMutationResult(
                    value: try Self.fetchChangeSet(
                        database: database,
                        operationID: command.operationID
                    ),
                    operationID: command.operationID,
                    disposition: .replayed
                )
            }
            let contribution = try Self.fetchContribution(
                database: database,
                id: command.contributionID
            )
            guard contribution.revision == command.expectedContributionRevision else {
                throw PersistenceError.revisionConflict(
                    expected: command.expectedContributionRevision,
                    actual: contribution.revision
                )
            }
            guard contribution.status == .draft || contribution.status == .changesRequested else {
                throw OutputMainlineError.invalidStateTransition(
                    from: contribution.status,
                    to: .submitted
                )
            }
            let sequence = (try Int.fetchOne(
                database,
                sql: """
                    SELECT MAX(sequence)
                    FROM change_sets
                    WHERE contribution_id = ?
                    """,
                arguments: [command.contributionID.rawValue.uuidString]
            ) ?? 0) + 1
            let now = Date()
            let snapshotID = OutputRevisionID()
            try Self.insertOutputRevision(
                database: database,
                id: snapshotID,
                outputID: contribution.outputID,
                parentRevisionID: contribution.baseOutputRevisionID,
                manifestHash: Self.outputManifestHash(command.proposedMembers),
                actorID: command.actorID,
                createdAt: now,
                snapshotKind: "proposed",
                operationID: command.operationID,
                members: command.proposedMembers
            )
            let changeSet = ChangeSet(
                ChangeSetID(),
                contributionID: command.contributionID,
                sequence: sequence,
                baseOutputRevisionID: contribution.baseOutputRevisionID,
                proposedSnapshotID: snapshotID,
                submittedByActorID: command.actorID,
                submittedAt: now,
                status: "submitted"
            )
            try database.execute(
                sql: """
                    INSERT INTO change_sets (
                        id, contribution_id, sequence, base_output_revision_id,
                        proposed_snapshot_id, submitted_by_actor_id,
                        submitted_at, status, operation_id
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, 'submitted', ?)
                    """,
                arguments: [
                    changeSet.id.rawValue.uuidString,
                    changeSet.contributionID.rawValue.uuidString,
                    changeSet.sequence,
                    changeSet.baseOutputRevisionID.rawValue.uuidString,
                    changeSet.proposedSnapshotID.rawValue.uuidString,
                    changeSet.submittedByActorID.rawValue.uuidString,
                    now.timeIntervalSince1970,
                    command.operationID.rawValue.uuidString
                ]
            )
            try database.execute(
                sql: """
                    UPDATE approvals
                    SET invalidated_at = ?
                    WHERE invalidated_at IS NULL
                      AND change_set_id IN (
                        SELECT id FROM change_sets
                        WHERE contribution_id = ? AND id != ?
                      )
                    """,
                arguments: [
                    now.timeIntervalSince1970,
                    command.contributionID.rawValue.uuidString,
                    changeSet.id.rawValue.uuidString
                ]
            )
            if contribution.status == .changesRequested {
                try Self.updateContributionState(
                    database: database,
                    contribution: contribution,
                    target: .draft,
                    now: now
                )
                let draft = try Self.fetchContribution(
                    database: database,
                    id: contribution.id
                )
                try Self.updateContributionState(
                    database: database,
                    contribution: draft,
                    target: .submitted,
                    now: now
                )
            } else {
                try Self.updateContributionState(
                    database: database,
                    contribution: contribution,
                    target: .submitted,
                    now: now
                )
            }
            try Self.phase0InsertAppliedOperation(
                database: database,
                operationID: command.operationID,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                commandName: SubmitChangeSet.identifier,
                fingerprint: fingerprint,
                appliedAt: now
            )
            try Self.phase0InsertSyncChange(
                database: database,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                operationID: command.operationID,
                recordKind: .changeSet,
                recordID: changeSet.id.rawValue,
                baseRevision: 0,
                revision: Int64(sequence),
                payload: changeSet,
                createdAt: now
            )
            if failBeforeCommit {
                throw ReliabilityError.injected(.databaseTransactionBeforeCommit)
            }
            return CommandMutationResult(
                value: changeSet,
                operationID: command.operationID,
                disposition: .applied
            )
        }
    }

    func recordValidationRun(
        _ command: RecordValidationRun,
        deviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> RecordValidationRun.Output {
        try pool.write { database in
            let fingerprint = Self.phase0Fingerprint([
                command.workspaceID.rawValue.uuidString,
                command.changeSetID.rawValue.uuidString,
                String(command.policyVersion),
                command.actorID.rawValue.uuidString
            ])
            if try Self.phase0Replay(
                database: database,
                operationID: command.operationID,
                sourceDeviceID: deviceID,
                commandName: RecordValidationRun.identifier,
                fingerprint: fingerprint
            ) {
                return CommandMutationResult(
                    value: try Self.fetchValidationRun(
                        database: database,
                        operationID: command.operationID
                    ),
                    operationID: command.operationID,
                    disposition: .replayed
                )
            }
            let context = try Self.validationContext(
                database: database,
                changeSetID: command.changeSetID
            )
            let now = Date()
            let runID = ValidationRunID()
            let results = Self.validationResults(
                database: database,
                runID: runID,
                context: context
            )
            try database.execute(
                sql: """
                    INSERT INTO validation_runs (
                        id, change_set_id, policy_version, status, started_at,
                        completed_at, operation_id
                    ) VALUES (?, ?, ?, 'completed', ?, ?, ?)
                    """,
                arguments: [
                    runID.rawValue.uuidString,
                    command.changeSetID.rawValue.uuidString,
                    command.policyVersion,
                    now.timeIntervalSince1970,
                    now.timeIntervalSince1970,
                    command.operationID.rawValue.uuidString
                ]
            )
            for result in results {
                try database.execute(
                    sql: """
                        INSERT INTO validation_results (
                            id, run_id, rule_id, rule_version, severity, status,
                            target_id, anchor_json, message
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        result.id.rawValue.uuidString,
                        runID.rawValue.uuidString,
                        result.ruleID,
                        result.ruleVersion,
                        result.severity.rawValue,
                        result.status.rawValue,
                        result.targetID?.uuidString,
                        result.anchorJSON,
                        result.message
                    ]
                )
            }
            if context.contributionStatus == .submitted {
                try database.execute(
                    sql: """
                        UPDATE contributions
                        SET status = 'reviewing', revision = revision + 1,
                            modified_at = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        now.timeIntervalSince1970,
                        context.contributionID.rawValue.uuidString
                    ]
                )
            }
            try Self.phase0InsertAppliedOperation(
                database: database,
                operationID: command.operationID,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                commandName: RecordValidationRun.identifier,
                fingerprint: fingerprint,
                appliedAt: now
            )
            let run = ValidationRun(
                runID,
                changeSetID: command.changeSetID,
                policyVersion: command.policyVersion,
                status: .completed,
                startedAt: now,
                completedAt: now,
                results: results
            )
            try Self.phase0InsertSyncChange(
                database: database,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                operationID: command.operationID,
                recordKind: .validationRun,
                recordID: runID.rawValue,
                baseRevision: 0,
                revision: 1,
                payload: run,
                createdAt: now
            )
            if failBeforeCommit {
                throw ReliabilityError.injected(.databaseTransactionBeforeCommit)
            }
            return CommandMutationResult(
                value: run,
                operationID: command.operationID,
                disposition: .applied
            )
        }
    }

    func recordReview(
        _ command: RecordReview,
        deviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> RecordReview.Output {
        try pool.write { database in
            guard command.reviewerKind != .validator,
                  !(command.reviewerKind == .ai && command.decision == .approve) else {
                throw OutputMainlineError.actorCannotApprove
            }
            let findingFingerprint = command.findings.map {
                "\($0.severity.rawValue):\($0.targetID?.uuidString ?? ""):\($0.message)"
            }.joined(separator: ",")
            let fingerprint = Self.phase0Fingerprint([
                command.workspaceID.rawValue.uuidString,
                command.changeSetID.rawValue.uuidString,
                command.reviewerActorID.rawValue.uuidString,
                command.reviewerKind.rawValue,
                command.decision.rawValue,
                findingFingerprint
            ])
            if try Self.phase0Replay(
                database: database,
                operationID: command.operationID,
                sourceDeviceID: deviceID,
                commandName: RecordReview.identifier,
                fingerprint: fingerprint
            ) {
                return CommandMutationResult(
                    value: try Self.fetchReview(
                        database: database,
                        operationID: command.operationID
                    ),
                    operationID: command.operationID,
                    disposition: .replayed
                )
            }
            guard let changeSetRow = try Row.fetchOne(
                database,
                sql: """
                    SELECT cs.proposed_snapshot_id, c.id AS contribution_id,
                           c.status
                    FROM change_sets cs
                    JOIN contributions c ON c.id = cs.contribution_id
                    WHERE cs.id = ?
                    """,
                arguments: [command.changeSetID.rawValue.uuidString]
            ) else {
                throw OutputMainlineError.changeSetNotLatest
            }
            let contributionStatus = ContributionStatus(
                rawValue: changeSetRow["status"]
            ) ?? .draft
            guard contributionStatus == .reviewing || contributionStatus == .submitted else {
                throw OutputMainlineError.invalidStateTransition(
                    from: contributionStatus,
                    to: .reviewing
                )
            }
            let now = Date()
            let review = Review(
                ReviewID(),
                changeSetID: command.changeSetID,
                reviewerActorID: command.reviewerActorID,
                reviewerKind: command.reviewerKind,
                decision: command.decision,
                reviewedSnapshotID: OutputRevisionID(
                    rawValue: try Self.phase0UUID(changeSetRow["proposed_snapshot_id"])
                ),
                createdAt: now
            )
            try database.execute(
                sql: """
                    INSERT INTO reviews (
                        id, change_set_id, reviewer_actor_id, reviewer_kind,
                        decision, reviewed_snapshot_id, created_at, operation_id
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    review.id.rawValue.uuidString,
                    review.changeSetID.rawValue.uuidString,
                    review.reviewerActorID.rawValue.uuidString,
                    review.reviewerKind.rawValue,
                    review.decision.rawValue,
                    review.reviewedSnapshotID.rawValue.uuidString,
                    now.timeIntervalSince1970,
                    command.operationID.rawValue.uuidString
                ]
            )
            for finding in command.findings {
                try database.execute(
                    sql: """
                        INSERT INTO review_findings (
                            id, review_id, severity, target_id, anchor_json,
                            message, resolution_status
                        ) VALUES (?, ?, ?, ?, ?, ?, 'open')
                        """,
                    arguments: [
                        ReviewFindingID().rawValue.uuidString,
                        review.id.rawValue.uuidString,
                        finding.severity.rawValue,
                        finding.targetID?.uuidString,
                        finding.anchorJSON,
                        finding.message
                    ]
                )
            }
            if contributionStatus == .submitted {
                try database.execute(
                    sql: """
                        UPDATE contributions
                        SET status = 'reviewing', revision = revision + 1,
                            modified_at = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        now.timeIntervalSince1970,
                        changeSetRow["contribution_id"] as String
                    ]
                )
            }
            try Self.phase0InsertAppliedOperation(
                database: database,
                operationID: command.operationID,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                commandName: RecordReview.identifier,
                fingerprint: fingerprint,
                appliedAt: now
            )
            try Self.phase0InsertSyncChange(
                database: database,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                operationID: command.operationID,
                recordKind: .review,
                recordID: review.id.rawValue,
                baseRevision: 0,
                revision: 1,
                payload: review,
                createdAt: now
            )
            if failBeforeCommit {
                throw ReliabilityError.injected(.databaseTransactionBeforeCommit)
            }
            return CommandMutationResult(
                value: review,
                operationID: command.operationID,
                disposition: .applied
            )
        }
    }

    func requestChanges(
        _ command: RequestChanges,
        deviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> RequestChanges.Output {
        try transitionContribution(
            workspaceID: command.workspaceID,
            contributionID: command.contributionID,
            changeSetID: command.changeSetID,
            expectedRevision: command.expectedContributionRevision,
            target: .changesRequested,
            operationID: command.operationID,
            actorID: command.actorID,
            commandName: RequestChanges.identifier,
            deviceID: deviceID,
            failBeforeCommit: failBeforeCommit,
            requiredReviewID: command.reviewID
        )
    }

    func approveChangeSet(
        _ command: ApproveChangeSet,
        deviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> ApproveChangeSet.Output {
        try pool.write { database in
            let fingerprint = Self.phase0Fingerprint([
                command.workspaceID.rawValue.uuidString,
                command.contributionID.rawValue.uuidString,
                command.changeSetID.rawValue.uuidString,
                String(command.expectedContributionRevision),
                command.actorID.rawValue.uuidString
            ])
            if try Self.phase0Replay(
                database: database,
                operationID: command.operationID,
                sourceDeviceID: deviceID,
                commandName: ApproveChangeSet.identifier,
                fingerprint: fingerprint
            ) {
                return CommandMutationResult(
                    value: try Self.fetchApproval(
                        database: database,
                        operationID: command.operationID
                    ),
                    operationID: command.operationID,
                    disposition: .replayed
                )
            }
            let contribution = try Self.fetchContribution(
                database: database,
                id: command.contributionID
            )
            guard contribution.revision == command.expectedContributionRevision else {
                throw PersistenceError.revisionConflict(
                    expected: command.expectedContributionRevision,
                    actual: contribution.revision
                )
            }
            guard contribution.status == .reviewing else {
                throw OutputMainlineError.invalidStateTransition(
                    from: contribution.status,
                    to: .approved
                )
            }
            guard contribution.createdByActorID != command.actorID else {
                throw OutputMainlineError.selfApprovalForbidden
            }
            let actorKind: String? = try String.fetchOne(
                database,
                sql: "SELECT kind FROM actors WHERE id = ?",
                arguments: [command.actorID.rawValue.uuidString]
            )
            guard actorKind == ActorKind.person.rawValue else {
                throw OutputMainlineError.actorCannotApprove
            }
            let changeSet = try Self.latestChangeSet(
                database: database,
                contributionID: command.contributionID
            )
            guard changeSet.id == command.changeSetID else {
                throw OutputMainlineError.changeSetNotLatest
            }
            guard try !Self.hasBlockingValidation(
                database: database,
                changeSetID: command.changeSetID
            ) else {
                throw OutputMainlineError.blockingValidation
            }
            let hasCompletedRun = try Int.fetchOne(
                database,
                sql: """
                    SELECT COUNT(*) FROM validation_runs
                    WHERE change_set_id = ? AND status = 'completed'
                    """,
                arguments: [command.changeSetID.rawValue.uuidString]
            ) ?? 0
            guard hasCompletedRun > 0 else {
                throw OutputMainlineError.blockingValidation
            }
            let now = Date()
            let approval = Approval(
                ApprovalID(),
                changeSetID: command.changeSetID,
                snapshotID: changeSet.proposedSnapshotID,
                approvedByActorID: command.actorID,
                createdAt: now,
                invalidatedAt: nil
            )
            try database.execute(
                sql: """
                    INSERT INTO approvals (
                        id, change_set_id, snapshot_id, approved_by_actor_id,
                        created_at, invalidated_at, operation_id
                    ) VALUES (?, ?, ?, ?, ?, NULL, ?)
                    """,
                arguments: [
                    approval.id.rawValue.uuidString,
                    approval.changeSetID.rawValue.uuidString,
                    approval.snapshotID.rawValue.uuidString,
                    approval.approvedByActorID.rawValue.uuidString,
                    now.timeIntervalSince1970,
                    command.operationID.rawValue.uuidString
                ]
            )
            try Self.updateContributionState(
                database: database,
                contribution: contribution,
                target: .approved,
                now: now
            )
            try Self.phase0InsertAppliedOperation(
                database: database,
                operationID: command.operationID,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                commandName: ApproveChangeSet.identifier,
                fingerprint: fingerprint,
                appliedAt: now
            )
            try Self.phase0InsertSyncChange(
                database: database,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                operationID: command.operationID,
                recordKind: .approval,
                recordID: approval.id.rawValue,
                baseRevision: 0,
                revision: 1,
                payload: approval,
                createdAt: now
            )
            if failBeforeCommit {
                throw ReliabilityError.injected(.databaseTransactionBeforeCommit)
            }
            return CommandMutationResult(
                value: approval,
                operationID: command.operationID,
                disposition: .applied
            )
        }
    }

    func mergeContribution(
        _ command: MergeContribution,
        deviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> MergeContribution.Output {
        try pool.write { database in
            let fingerprint = Self.phase0Fingerprint([
                command.workspaceID.rawValue.uuidString,
                command.contributionID.rawValue.uuidString,
                command.changeSetID.rawValue.uuidString,
                command.approvalID.rawValue.uuidString,
                command.expectedMainRevisionID.rawValue.uuidString,
                String(command.expectedContributionRevision),
                command.actorID.rawValue.uuidString
            ])
            if try Self.phase0Replay(
                database: database,
                operationID: command.operationID,
                sourceDeviceID: deviceID,
                commandName: MergeContribution.identifier,
                fingerprint: fingerprint
            ) {
                return CommandMutationResult(
                    value: try Self.fetchMergeResult(
                        database: database,
                        operationID: command.operationID
                    ),
                    operationID: command.operationID,
                    disposition: .replayed
                )
            }
            let contribution = try Self.fetchContribution(
                database: database,
                id: command.contributionID
            )
            guard contribution.status == .approved else {
                if contribution.status == .merged || contribution.status == .closed {
                    throw OutputMainlineError.contributionAlreadyTerminal
                }
                throw OutputMainlineError.invalidStateTransition(
                    from: contribution.status,
                    to: .merged
                )
            }
            guard contribution.revision == command.expectedContributionRevision else {
                throw PersistenceError.revisionConflict(
                    expected: command.expectedContributionRevision,
                    actual: contribution.revision
                )
            }
            let changeSet = try Self.latestChangeSet(
                database: database,
                contributionID: command.contributionID
            )
            guard changeSet.id == command.changeSetID else {
                throw OutputMainlineError.changeSetNotLatest
            }
            let approval = try Self.fetchApproval(
                database: database,
                id: command.approvalID
            )
            guard approval.changeSetID == command.changeSetID,
                  approval.snapshotID == changeSet.proposedSnapshotID else {
                throw OutputMainlineError.approvalSnapshotMismatch
            }
            guard approval.invalidatedAt == nil else {
                throw OutputMainlineError.approvalInvalidated
            }
            guard try !Self.hasBlockingValidation(
                database: database,
                changeSetID: command.changeSetID
            ) else {
                throw OutputMainlineError.blockingValidation
            }
            guard let outputRow = try Row.fetchOne(
                database,
                sql: "SELECT * FROM outputs WHERE id = ?",
                arguments: [contribution.outputID.rawValue.uuidString]
            ) else {
                throw OutputMainlineError.invalidOutputStructure
            }
            let currentID = OutputRevisionID(
                rawValue: try Self.phase0UUID(outputRow["current_revision_id"])
            )
            guard currentID == command.expectedMainRevisionID else {
                throw OutputMainlineError.staleMainline(
                    expected: command.expectedMainRevisionID,
                    actual: currentID
                )
            }
            let proposed = try Self.fetchOutputRevision(
                database: database,
                id: changeSet.proposedSnapshotID
            )
            let now = Date()
            let mainAfterID = OutputRevisionID()
            let proposals = proposed.members.map {
                OutputMemberProposal(
                    targetKind: $0.targetKind,
                    targetID: $0.targetID,
                    targetRevisionID: $0.targetRevisionID,
                    role: $0.role,
                    rank: $0.rank
                )
            }
            try Self.insertOutputRevision(
                database: database,
                id: mainAfterID,
                outputID: contribution.outputID,
                parentRevisionID: currentID,
                manifestHash: proposed.manifestHash,
                actorID: command.actorID,
                createdAt: now,
                snapshotKind: "main",
                operationID: command.operationID,
                members: proposals
            )
            let outputRevision: Int64 = outputRow["revision"]
            try database.execute(
                sql: """
                    UPDATE outputs
                    SET current_revision_id = ?, revision = revision + 1,
                        modified_at = ?
                    WHERE id = ? AND current_revision_id = ?
                    """,
                arguments: [
                    mainAfterID.rawValue.uuidString,
                    now.timeIntervalSince1970,
                    contribution.outputID.rawValue.uuidString,
                    currentID.rawValue.uuidString
                ]
            )
            guard database.changesCount == 1 else {
                let actual: String = try String.fetchOne(
                    database,
                    sql: "SELECT current_revision_id FROM outputs WHERE id = ?",
                    arguments: [contribution.outputID.rawValue.uuidString]
                ) ?? currentID.rawValue.uuidString
                throw OutputMainlineError.staleMainline(
                    expected: currentID,
                    actual: OutputRevisionID(
                        rawValue: try Self.phase0UUID(actual)
                    )
                )
            }
            let mergeRecord = MergeRecord(
                MergeRecordID(),
                contributionID: contribution.id,
                changeSetID: changeSet.id,
                mainBeforeRevisionID: currentID,
                contributionHeadRevisionID: changeSet.proposedSnapshotID,
                mainAfterRevisionID: mainAfterID,
                approvalID: approval.id,
                approvedByActorID: approval.approvedByActorID,
                operationID: command.operationID,
                mergedAt: now
            )
            try Self.phase0InsertAppliedOperation(
                database: database,
                operationID: command.operationID,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                commandName: MergeContribution.identifier,
                fingerprint: fingerprint,
                appliedAt: now
            )
            try database.execute(
                sql: """
                    INSERT INTO merge_records (
                        id, contribution_id, change_set_id,
                        main_before_revision_id, contribution_head_revision_id,
                        main_after_revision_id, approval_id, approved_by_actor_id,
                        operation_id, merged_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    mergeRecord.id.rawValue.uuidString,
                    mergeRecord.contributionID.rawValue.uuidString,
                    mergeRecord.changeSetID.rawValue.uuidString,
                    mergeRecord.mainBeforeRevisionID.rawValue.uuidString,
                    mergeRecord.contributionHeadRevisionID.rawValue.uuidString,
                    mergeRecord.mainAfterRevisionID.rawValue.uuidString,
                    mergeRecord.approvalID.rawValue.uuidString,
                    mergeRecord.approvedByActorID.rawValue.uuidString,
                    command.operationID.rawValue.uuidString,
                    now.timeIntervalSince1970
                ]
            )
            try Self.updateContributionState(
                database: database,
                contribution: contribution,
                target: .merged,
                now: now
            )
            let mainRevision = try Self.fetchOutputRevision(
                database: database,
                id: mainAfterID
            )
            try Self.phase0InsertSyncChange(
                database: database,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                operationID: command.operationID,
                recordKind: .outputRevision,
                recordID: mainAfterID.rawValue,
                baseRevision: outputRevision,
                revision: outputRevision + 1,
                payload: mainRevision,
                createdAt: now
            )
            try Self.phase0InsertSyncChange(
                database: database,
                workspaceID: command.workspaceID,
                sourceDeviceID: deviceID,
                operationID: command.operationID,
                recordKind: .mergeRecord,
                recordID: mergeRecord.id.rawValue,
                baseRevision: 0,
                revision: 1,
                payload: mergeRecord,
                createdAt: now
            )
            try Self.phase0InsertIntegrationEvent(
                database: database,
                eventName: "OutputMerged",
                workspaceID: command.workspaceID,
                actorID: command.actorID,
                aggregateKind: "output",
                aggregateID: contribution.outputID.rawValue,
                operationID: command.operationID,
                occurredAt: now,
                payload: OutputMergedPayload(
                    outputID: contribution.outputID,
                    contributionID: contribution.id,
                    changeSetID: changeSet.id,
                    mainBeforeRevisionID: currentID,
                    mainAfterRevisionID: mainAfterID,
                    approvalID: approval.id
                )
            )
            if failBeforeCommit {
                throw ReliabilityError.injected(.databaseTransactionBeforeCommit)
            }
            return CommandMutationResult(
                value: try Self.fetchMergeResult(
                    database: database,
                    operationID: command.operationID
                ),
                operationID: command.operationID,
                disposition: .applied
            )
        }
    }

    func closeContribution(
        _ command: CloseContribution,
        deviceID: DeviceID,
        failBeforeCommit: Bool
    ) throws -> CloseContribution.Output {
        try transitionContribution(
            workspaceID: command.workspaceID,
            contributionID: command.contributionID,
            changeSetID: nil,
            expectedRevision: command.expectedContributionRevision,
            target: .closed,
            operationID: command.operationID,
            actorID: command.actorID,
            commandName: CloseContribution.identifier,
            deviceID: deviceID,
            failBeforeCommit: failBeforeCommit,
            requiredReviewID: nil
        )
    }

    func fetchOutput(id: OutputID) throws -> VersoDomain.Output {
        try pool.read { try Self.fetchOutput(database: $0, id: id) }
    }

    func fetchContribution(id: ContributionID) throws -> Contribution {
        try pool.read { try Self.fetchContribution(database: $0, id: id) }
    }

    func mergeRecordCount() throws -> Int {
        try pool.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM merge_records") ?? 0
        }
    }

    private func transitionContribution(
        workspaceID: WorkspaceID,
        contributionID: ContributionID,
        changeSetID: ChangeSetID?,
        expectedRevision: Int64,
        target: ContributionStatus,
        operationID: OperationID,
        actorID: ActorID,
        commandName: String,
        deviceID: DeviceID,
        failBeforeCommit: Bool,
        requiredReviewID: ReviewID?
    ) throws -> CommandMutationResult<Contribution> {
        try pool.write { database in
            let fingerprint = Self.phase0Fingerprint([
                workspaceID.rawValue.uuidString,
                contributionID.rawValue.uuidString,
                changeSetID?.rawValue.uuidString ?? "",
                String(expectedRevision),
                target.rawValue,
                requiredReviewID?.rawValue.uuidString ?? "",
                actorID.rawValue.uuidString
            ])
            if try Self.phase0Replay(
                database: database,
                operationID: operationID,
                sourceDeviceID: deviceID,
                commandName: commandName,
                fingerprint: fingerprint
            ) {
                return CommandMutationResult(
                    value: try Self.fetchContribution(
                        database: database,
                        id: contributionID
                    ),
                    operationID: operationID,
                    disposition: .replayed
                )
            }
            let contribution = try Self.fetchContribution(
                database: database,
                id: contributionID
            )
            guard contribution.revision == expectedRevision else {
                throw PersistenceError.revisionConflict(
                    expected: expectedRevision,
                    actual: contribution.revision
                )
            }
            guard contribution.status.canTransition(to: target) else {
                throw OutputMainlineError.invalidStateTransition(
                    from: contribution.status,
                    to: target
                )
            }
            if let changeSetID {
                let latest = try Self.latestChangeSet(
                    database: database,
                    contributionID: contributionID
                )
                guard latest.id == changeSetID else {
                    throw OutputMainlineError.changeSetNotLatest
                }
            }
            if let requiredReviewID {
                let decision: String? = try String.fetchOne(
                    database,
                    sql: """
                        SELECT decision FROM reviews
                        WHERE id = ? AND change_set_id = ?
                        """,
                    arguments: [
                        requiredReviewID.rawValue.uuidString,
                        changeSetID?.rawValue.uuidString
                    ]
                )
                guard decision == ReviewDecision.requestChanges.rawValue else {
                    throw OutputMainlineError.invalidStateTransition(
                        from: contribution.status,
                        to: target
                    )
                }
            }
            let now = Date()
            try Self.updateContributionState(
                database: database,
                contribution: contribution,
                target: target,
                now: now
            )
            try Self.phase0InsertAppliedOperation(
                database: database,
                operationID: operationID,
                workspaceID: workspaceID,
                sourceDeviceID: deviceID,
                commandName: commandName,
                fingerprint: fingerprint,
                appliedAt: now
            )
            let updated = try Self.fetchContribution(
                database: database,
                id: contributionID
            )
            try Self.phase0InsertSyncChange(
                database: database,
                workspaceID: workspaceID,
                sourceDeviceID: deviceID,
                operationID: operationID,
                recordKind: .contribution,
                recordID: contributionID.rawValue,
                baseRevision: contribution.revision,
                revision: updated.revision,
                payload: updated,
                createdAt: now
            )
            if failBeforeCommit {
                throw ReliabilityError.injected(.databaseTransactionBeforeCommit)
            }
            return CommandMutationResult(
                value: updated,
                operationID: operationID,
                disposition: .applied
            )
        }
    }

    private struct ValidationContext {
        let changeSetID: ChangeSetID
        let contributionID: ContributionID
        let contributionStatus: ContributionStatus
        let outputID: OutputID
        let baseRevisionID: OutputRevisionID
        let proposedRevisionID: OutputRevisionID
        let mainRevisionID: OutputRevisionID
        let structureSchemaVersion: Int
        let memberRows: [Row]
    }

    private static func validationContext(
        database: Database,
        changeSetID: ChangeSetID
    ) throws -> ValidationContext {
        guard let row = try Row.fetchOne(
            database,
            sql: """
                SELECT cs.contribution_id, cs.base_output_revision_id,
                       cs.proposed_snapshot_id, c.status, c.output_id,
                       o.current_revision_id, o.structure_schema_version
                FROM change_sets cs
                JOIN contributions c ON c.id = cs.contribution_id
                JOIN outputs o ON o.id = c.output_id
                WHERE cs.id = ?
                """,
            arguments: [changeSetID.rawValue.uuidString]
        ) else {
            throw OutputMainlineError.changeSetNotLatest
        }
        let proposedID = OutputRevisionID(
            rawValue: try phase0UUID(row["proposed_snapshot_id"])
        )
        let members = try Row.fetchAll(
            database,
            sql: """
                SELECT * FROM output_revision_members
                WHERE output_revision_id = ?
                ORDER BY rank, id
                """,
            arguments: [proposedID.rawValue.uuidString]
        )
        return ValidationContext(
            changeSetID: changeSetID,
            contributionID: ContributionID(
                rawValue: try phase0UUID(row["contribution_id"])
            ),
            contributionStatus: ContributionStatus(rawValue: row["status"]) ?? .draft,
            outputID: OutputID(rawValue: try phase0UUID(row["output_id"])),
            baseRevisionID: OutputRevisionID(
                rawValue: try phase0UUID(row["base_output_revision_id"])
            ),
            proposedRevisionID: proposedID,
            mainRevisionID: OutputRevisionID(
                rawValue: try phase0UUID(row["current_revision_id"])
            ),
            structureSchemaVersion: row["structure_schema_version"],
            memberRows: members
        )
    }

    private static func validationResults(
        database: Database,
        runID: ValidationRunID,
        context: ValidationContext
    ) -> [ValidationResult] {
        func result(
            rule: String,
            passed: Bool,
            message: String,
            severity: ValidationSeverity = .blocking
        ) -> ValidationResult {
            ValidationResult(
                ValidationResultID(),
                runID: runID,
                ruleID: rule,
                ruleVersion: 1,
                severity: severity,
                status: passed ? .passed : .failed,
                targetID: context.outputID.rawValue,
                anchorJSON: nil,
                message: message
            )
        }
        let structureValid = context.structureSchemaVersion > 0
            && !context.memberRows.isEmpty
        let revisionsExist = context.memberRows.allSatisfy { row in
            let kind: String = row["target_kind"]
            let revisionID: String = row["target_revision_id"]
            let table: String
            switch kind {
            case OutputMemberTargetKind.document.rawValue:
                table = "document_revisions"
            case OutputMemberTargetKind.concept.rawValue:
                table = "knowledge_concept_revisions"
            default:
                return false
            }
            return (try? Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM \(table) WHERE id = ?",
                arguments: [revisionID]
            )) == 1
        }
        let provenance = context.memberRows.allSatisfy { row in
            guard row["target_kind"] as String
                == OutputMemberTargetKind.concept.rawValue else {
                return true
            }
            let targetID: String = row["target_id"]
            return (try? Int.fetchOne(
                database,
                sql: """
                    SELECT COUNT(*) FROM knowledge_references
                    WHERE source_kind = 'knowledgeConcept'
                      AND source_id = ? AND deleted_at IS NULL
                    """,
                arguments: [targetID]
            )) ?? 0 > 0
        }
        let safeLocalData = context.memberRows.allSatisfy { row in
            guard row["target_kind"] as String
                == OutputMemberTargetKind.document.rawValue else {
                return true
            }
            let revisionID: String = row["target_revision_id"]
            let path = try? String.fetchOne(
                database,
                sql: "SELECT content_relative_path FROM document_revisions WHERE id = ?",
                arguments: [revisionID]
            )
            guard let resolved = path ?? nil else {
                return false
            }
            return !resolved.hasPrefix("/")
                && !resolved.contains("..")
                && !resolved.lowercased().contains("apikey")
                && !resolved.lowercased().contains("oauth")
                && !resolved.lowercased().contains("credential")
        }
        let publishable = context.memberRows.allSatisfy { row in
            guard row["target_kind"] as String
                == OutputMemberTargetKind.concept.rawValue else {
                return true
            }
            let targetID: String = row["target_id"]
            let policy = try? Row.fetchOne(
                database,
                sql: """
                    SELECT p.visibility, p.sensitivity, p.ownership_basis
                    FROM knowledge_concepts c
                    JOIN publication_policies p ON p.id = c.publication_policy_id
                    WHERE c.id = ?
                    """,
                arguments: [targetID]
            )
            guard let policy else {
                return false
            }
            return policy["visibility"] as String != PublicationVisibility.private.rawValue
                && policy["sensitivity"] as String
                    != PublicationSensitivity.confidential.rawValue
                && policy["ownership_basis"] as String
                    != OwnershipBasis.unknown.rawValue
        }
        return [
            result(
                rule: "output.structure.parseable",
                passed: structureValid,
                message: structureValid
                    ? "Output structure is parseable."
                    : "Output structure is missing or empty."
            ),
            result(
                rule: "members.revisions.exist",
                passed: revisionsExist,
                message: revisionsExist
                    ? "All member revisions exist."
                    : "A member revision is missing."
            ),
            result(
                rule: "references.internal.valid",
                passed: revisionsExist,
                message: revisionsExist
                    ? "Internal member references are valid."
                    : "An internal member reference is invalid."
            ),
            result(
                rule: "provenance.traceable",
                passed: provenance,
                message: provenance
                    ? "Member provenance is traceable."
                    : "A concept has no source provenance."
            ),
            result(
                rule: "payload.local-data.safe",
                passed: safeLocalData,
                message: safeLocalData
                    ? "No absolute path or credential marker is present."
                    : "Local path or credential-like data was detected."
            ),
            result(
                rule: "publication.explicit",
                passed: publishable,
                message: publishable
                    ? "Members have an explicit distributable policy."
                    : "Private, confidential, or unknown-ownership content is present."
            ),
            result(
                rule: "mainline.expected",
                passed: context.mainRevisionID == context.baseRevisionID,
                message: context.mainRevisionID == context.baseRevisionID
                    ? "Mainline matches the contribution base."
                    : "Mainline changed after the contribution was created."
            )
        ]
    }

    private static func validateOutputMembers(
        database: Database,
        members: [OutputMemberProposal]
    ) throws {
        var identities: Set<String> = []
        for member in members {
            let identity = "\(member.targetKind.rawValue):\(member.targetID.uuidString)"
            guard identities.insert(identity).inserted else {
                throw OutputMainlineError.invalidOutputStructure
            }
            let table: String
            let ownerColumn: String
            switch member.targetKind {
            case .document:
                table = "document_revisions"
                ownerColumn = "document_id"
            case .concept:
                table = "knowledge_concept_revisions"
                ownerColumn = "concept_id"
            case .asset:
                throw OutputMainlineError.invalidOutputStructure
            }
            guard try Int.fetchOne(
                database,
                sql: """
                    SELECT COUNT(*) FROM \(table)
                    WHERE id = ? AND \(ownerColumn) = ?
                    """,
                arguments: [
                    member.targetRevisionID.uuidString,
                    member.targetID.uuidString
                ]
            ) == 1 else {
                throw OutputMainlineError.invalidOutputStructure
            }
        }
    }

    private static func outputFingerprint(
        _ members: [OutputMemberProposal],
        prefix: [String]
    ) -> String {
        phase0Fingerprint(prefix + members.sorted {
            if $0.rank == $1.rank {
                return $0.targetID.uuidString < $1.targetID.uuidString
            }
            return $0.rank < $1.rank
        }.map {
            [
                $0.targetKind.rawValue,
                $0.targetID.uuidString,
                $0.targetRevisionID.uuidString,
                $0.role,
                String($0.rank)
            ].joined(separator: ":")
        })
    }

    private static func outputManifestHash(_ members: [OutputMemberProposal]) -> String {
        outputFingerprint(members, prefix: ["output-manifest-v1"])
    }

    private static func insertOutputRevision(
        database: Database,
        id: OutputRevisionID,
        outputID: OutputID,
        parentRevisionID: OutputRevisionID?,
        manifestHash: String,
        actorID: ActorID,
        createdAt: Date,
        snapshotKind: String,
        operationID: OperationID,
        members: [OutputMemberProposal]
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO output_revisions (
                    id, output_id, parent_revision_id, manifest_hash,
                    created_by_actor_id, created_at, snapshot_kind, operation_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id.rawValue.uuidString,
                outputID.rawValue.uuidString,
                parentRevisionID?.rawValue.uuidString,
                manifestHash,
                actorID.rawValue.uuidString,
                createdAt.timeIntervalSince1970,
                snapshotKind,
                operationID.rawValue.uuidString
            ]
        )
        for member in members {
            try database.execute(
                sql: """
                    INSERT INTO output_revision_members (
                        id, output_revision_id, target_kind, target_id,
                        target_revision_id, role, rank
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    OutputRevisionMemberID().rawValue.uuidString,
                    id.rawValue.uuidString,
                    member.targetKind.rawValue,
                    member.targetID.uuidString,
                    member.targetRevisionID.uuidString,
                    member.role,
                    member.rank
                ]
            )
        }
    }

    private static func updateContributionState(
        database: Database,
        contribution: Contribution,
        target: ContributionStatus,
        now: Date
    ) throws {
        guard contribution.status.canTransition(to: target) else {
            throw OutputMainlineError.invalidStateTransition(
                from: contribution.status,
                to: target
            )
        }
        try database.execute(
            sql: """
                UPDATE contributions
                SET status = ?, revision = revision + 1, modified_at = ?,
                    closed_at = CASE WHEN ? = 'closed' THEN ? ELSE closed_at END
                WHERE id = ? AND revision = ?
                """,
            arguments: [
                target.rawValue,
                now.timeIntervalSince1970,
                target.rawValue,
                now.timeIntervalSince1970,
                contribution.id.rawValue.uuidString,
                contribution.revision
            ]
        )
        guard database.changesCount == 1 else {
            throw PersistenceError.revisionConflict(
                expected: contribution.revision,
                actual: contribution.revision + 1
            )
        }
    }

    private static func latestChangeSet(
        database: Database,
        contributionID: ContributionID
    ) throws -> ChangeSet {
        guard let row = try Row.fetchOne(
            database,
            sql: """
                SELECT * FROM change_sets
                WHERE contribution_id = ?
                ORDER BY sequence DESC
                LIMIT 1
                """,
            arguments: [contributionID.rawValue.uuidString]
        ) else {
            throw OutputMainlineError.changeSetNotLatest
        }
        return try decodeChangeSet(row)
    }

    private static func hasBlockingValidation(
        database: Database,
        changeSetID: ChangeSetID
    ) throws -> Bool {
        let latestRunID: String? = try String.fetchOne(
            database,
            sql: """
                SELECT id FROM validation_runs
                WHERE change_set_id = ? AND status = 'completed'
                ORDER BY completed_at DESC, id DESC
                LIMIT 1
                """,
            arguments: [changeSetID.rawValue.uuidString]
        )
        guard let latestRunID else {
            return true
        }
        let blockingResults = try Int.fetchOne(
            database,
            sql: """
                SELECT COUNT(*) FROM validation_results
                WHERE run_id = ? AND severity = 'blocking' AND status = 'failed'
                """,
            arguments: [latestRunID]
        ) ?? 0
        let blockingFindings = try Int.fetchOne(
            database,
            sql: """
                SELECT COUNT(*)
                FROM review_findings rf
                JOIN reviews r ON r.id = rf.review_id
                WHERE r.change_set_id = ?
                  AND rf.severity = 'blocking'
                  AND rf.resolution_status = 'open'
                """,
            arguments: [changeSetID.rawValue.uuidString]
        ) ?? 0
        return blockingResults > 0 || blockingFindings > 0
    }

    private static func fetchOutput(
        database: Database,
        operationID: OperationID
    ) throws -> VersoDomain.Output {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM outputs WHERE operation_id = ?",
            arguments: [operationID.rawValue.uuidString]
        ) else {
            throw OutputMainlineError.invalidOutputStructure
        }
        return try decodeOutput(row)
    }

    private static func fetchOutput(
        database: Database,
        id: OutputID
    ) throws -> VersoDomain.Output {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM outputs WHERE id = ?",
            arguments: [id.rawValue.uuidString]
        ) else {
            throw OutputMainlineError.invalidOutputStructure
        }
        return try decodeOutput(row)
    }

    private static func decodeOutput(_ row: Row) throws -> VersoDomain.Output {
        VersoDomain.Output(
            OutputID(rawValue: try phase0UUID(row["id"])),
            workspaceID: WorkspaceID(rawValue: try phase0UUID(row["workspace_id"])),
            title: row["title"],
            purpose: row["purpose"],
            audience: row["audience"],
            outputType: row["output_type"],
            currentRevisionID: OutputRevisionID(
                rawValue: try phase0UUID(row["current_revision_id"])
            ),
            structureSchemaVersion: row["structure_schema_version"],
            createdAt: phase0Date(row, "created_at"),
            modifiedAt: phase0Date(row, "modified_at"),
            deletedAt: phase0OptionalDate(row, "deleted_at"),
            revision: row["revision"]
        )
    }

    private static func fetchContribution(
        database: Database,
        operationID: OperationID
    ) throws -> Contribution {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM contributions WHERE operation_id = ?",
            arguments: [operationID.rawValue.uuidString]
        ) else {
            throw OutputMainlineError.invalidOutputStructure
        }
        return try decodeContribution(row)
    }

    private static func fetchContribution(
        database: Database,
        id: ContributionID
    ) throws -> Contribution {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM contributions WHERE id = ?",
            arguments: [id.rawValue.uuidString]
        ) else {
            throw OutputMainlineError.invalidOutputStructure
        }
        return try decodeContribution(row)
    }

    private static func decodeContribution(_ row: Row) throws -> Contribution {
        Contribution(
            ContributionID(rawValue: try phase0UUID(row["id"])),
            outputID: OutputID(rawValue: try phase0UUID(row["output_id"])),
            baseOutputRevisionID: OutputRevisionID(
                rawValue: try phase0UUID(row["base_output_revision_id"])
            ),
            title: row["title"],
            intent: row["intent"],
            createdByActorID: ActorID(
                rawValue: try phase0UUID(row["created_by_actor_id"])
            ),
            status: ContributionStatus(rawValue: row["status"]) ?? .draft,
            revision: row["revision"],
            createdAt: phase0Date(row, "created_at"),
            modifiedAt: phase0Date(row, "modified_at"),
            closedAt: phase0OptionalDate(row, "closed_at")
        )
    }

    private static func fetchChangeSet(
        database: Database,
        operationID: OperationID
    ) throws -> ChangeSet {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM change_sets WHERE operation_id = ?",
            arguments: [operationID.rawValue.uuidString]
        ) else {
            throw OutputMainlineError.changeSetNotLatest
        }
        return try decodeChangeSet(row)
    }

    private static func decodeChangeSet(_ row: Row) throws -> ChangeSet {
        ChangeSet(
            ChangeSetID(rawValue: try phase0UUID(row["id"])),
            contributionID: ContributionID(
                rawValue: try phase0UUID(row["contribution_id"])
            ),
            sequence: row["sequence"],
            baseOutputRevisionID: OutputRevisionID(
                rawValue: try phase0UUID(row["base_output_revision_id"])
            ),
            proposedSnapshotID: OutputRevisionID(
                rawValue: try phase0UUID(row["proposed_snapshot_id"])
            ),
            submittedByActorID: ActorID(
                rawValue: try phase0UUID(row["submitted_by_actor_id"])
            ),
            submittedAt: phase0Date(row, "submitted_at"),
            status: row["status"]
        )
    }

    private static func fetchOutputRevision(
        database: Database,
        id: OutputRevisionID
    ) throws -> OutputRevision {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM output_revisions WHERE id = ?",
            arguments: [id.rawValue.uuidString]
        ) else {
            throw OutputMainlineError.invalidOutputStructure
        }
        let members = try Row.fetchAll(
            database,
            sql: """
                SELECT * FROM output_revision_members
                WHERE output_revision_id = ?
                ORDER BY rank, id
                """,
            arguments: [id.rawValue.uuidString]
        ).map { member in
            OutputRevisionMember(
                OutputRevisionMemberID(
                    rawValue: try phase0UUID(member["id"])
                ),
                outputRevisionID: id,
                targetKind: OutputMemberTargetKind(
                    rawValue: member["target_kind"]
                ) ?? .document,
                targetID: try phase0UUID(member["target_id"]),
                targetRevisionID: try phase0UUID(member["target_revision_id"]),
                role: member["role"],
                rank: member["rank"]
            )
        }
        return OutputRevision(
            id,
            outputID: OutputID(rawValue: try phase0UUID(row["output_id"])),
            parentRevisionID: (row["parent_revision_id"] as String?)
                .flatMap(UUID.init(uuidString:))
                .map(OutputRevisionID.init(rawValue:)),
            manifestHash: row["manifest_hash"],
            createdByActorID: ActorID(
                rawValue: try phase0UUID(row["created_by_actor_id"])
            ),
            createdAt: phase0Date(row, "created_at"),
            members: members
        )
    }

    private static func fetchValidationRun(
        database: Database,
        operationID: OperationID
    ) throws -> ValidationRun {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM validation_runs WHERE operation_id = ?",
            arguments: [operationID.rawValue.uuidString]
        ) else {
            throw OutputMainlineError.blockingValidation
        }
        let runID = ValidationRunID(rawValue: try phase0UUID(row["id"]))
        let results = try Row.fetchAll(
            database,
            sql: "SELECT * FROM validation_results WHERE run_id = ? ORDER BY rule_id",
            arguments: [runID.rawValue.uuidString]
        ).map { result in
            ValidationResult(
                ValidationResultID(rawValue: try phase0UUID(result["id"])),
                runID: runID,
                ruleID: result["rule_id"],
                ruleVersion: result["rule_version"],
                severity: ValidationSeverity(rawValue: result["severity"]) ?? .blocking,
                status: ValidationResultStatus(rawValue: result["status"]) ?? .failed,
                targetID: (result["target_id"] as String?).flatMap(UUID.init(uuidString:)),
                anchorJSON: result["anchor_json"],
                message: result["message"]
            )
        }
        return ValidationRun(
            runID,
            changeSetID: ChangeSetID(
                rawValue: try phase0UUID(row["change_set_id"])
            ),
            policyVersion: row["policy_version"],
            status: ValidationRunStatus(rawValue: row["status"]) ?? .failed,
            startedAt: phase0Date(row, "started_at"),
            completedAt: phase0OptionalDate(row, "completed_at"),
            results: results
        )
    }

    private static func fetchReview(
        database: Database,
        operationID: OperationID
    ) throws -> Review {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM reviews WHERE operation_id = ?",
            arguments: [operationID.rawValue.uuidString]
        ) else {
            throw OutputMainlineError.changeSetNotLatest
        }
        return Review(
            ReviewID(rawValue: try phase0UUID(row["id"])),
            changeSetID: ChangeSetID(
                rawValue: try phase0UUID(row["change_set_id"])
            ),
            reviewerActorID: ActorID(
                rawValue: try phase0UUID(row["reviewer_actor_id"])
            ),
            reviewerKind: ReviewerKind(rawValue: row["reviewer_kind"]) ?? .human,
            decision: ReviewDecision(rawValue: row["decision"]) ?? .comment,
            reviewedSnapshotID: OutputRevisionID(
                rawValue: try phase0UUID(row["reviewed_snapshot_id"])
            ),
            createdAt: phase0Date(row, "created_at")
        )
    }

    private static func fetchApproval(
        database: Database,
        operationID: OperationID
    ) throws -> Approval {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM approvals WHERE operation_id = ?",
            arguments: [operationID.rawValue.uuidString]
        ) else {
            throw OutputMainlineError.approvalInvalidated
        }
        return try decodeApproval(row)
    }

    private static func fetchApproval(
        database: Database,
        id: ApprovalID
    ) throws -> Approval {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM approvals WHERE id = ?",
            arguments: [id.rawValue.uuidString]
        ) else {
            throw OutputMainlineError.approvalInvalidated
        }
        return try decodeApproval(row)
    }

    private static func decodeApproval(_ row: Row) throws -> Approval {
        Approval(
            ApprovalID(rawValue: try phase0UUID(row["id"])),
            changeSetID: ChangeSetID(
                rawValue: try phase0UUID(row["change_set_id"])
            ),
            snapshotID: OutputRevisionID(
                rawValue: try phase0UUID(row["snapshot_id"])
            ),
            approvedByActorID: ActorID(
                rawValue: try phase0UUID(row["approved_by_actor_id"])
            ),
            createdAt: phase0Date(row, "created_at"),
            invalidatedAt: phase0OptionalDate(row, "invalidated_at")
        )
    }

    private static func fetchMergeResult(
        database: Database,
        operationID: OperationID
    ) throws -> MergeContributionResult {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM merge_records WHERE operation_id = ?",
            arguments: [operationID.rawValue.uuidString]
        ) else {
            throw OutputMainlineError.changeSetNotLatest
        }
        let record = MergeRecord(
            MergeRecordID(rawValue: try phase0UUID(row["id"])),
            contributionID: ContributionID(
                rawValue: try phase0UUID(row["contribution_id"])
            ),
            changeSetID: ChangeSetID(
                rawValue: try phase0UUID(row["change_set_id"])
            ),
            mainBeforeRevisionID: OutputRevisionID(
                rawValue: try phase0UUID(row["main_before_revision_id"])
            ),
            contributionHeadRevisionID: OutputRevisionID(
                rawValue: try phase0UUID(row["contribution_head_revision_id"])
            ),
            mainAfterRevisionID: OutputRevisionID(
                rawValue: try phase0UUID(row["main_after_revision_id"])
            ),
            approvalID: ApprovalID(
                rawValue: try phase0UUID(row["approval_id"])
            ),
            approvedByActorID: ActorID(
                rawValue: try phase0UUID(row["approved_by_actor_id"])
            ),
            operationID: operationID,
            mergedAt: phase0Date(row, "merged_at")
        )
        return MergeContributionResult(
            try fetchOutputRevision(
                database: database,
                id: record.mainAfterRevisionID
            ),
            mergeRecord: record
        )
    }
}
