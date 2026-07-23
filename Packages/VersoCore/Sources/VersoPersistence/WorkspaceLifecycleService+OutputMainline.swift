import VersoApplication
import VersoDomain

extension WorkspaceLifecycleService: OutputMainlineServicing {
    public func createOutput(_ command: CreateOutput) async throws -> CreateOutput.Output {
        try outputDatabase(for: command.workspaceID).createOutput(
            command,
            deviceID: deviceID,
            failBeforeCommit: await outputShouldFail()
        )
    }

    public func createContribution(
        _ command: CreateContribution
    ) async throws -> CreateContribution.Output {
        try outputDatabase(for: command.workspaceID).createContribution(
            command,
            deviceID: deviceID,
            failBeforeCommit: await outputShouldFail()
        )
    }

    public func submitChangeSet(
        _ command: SubmitChangeSet
    ) async throws -> SubmitChangeSet.Output {
        try outputDatabase(for: command.workspaceID).submitChangeSet(
            command,
            deviceID: deviceID,
            failBeforeCommit: await outputShouldFail()
        )
    }

    public func recordValidationRun(
        _ command: RecordValidationRun
    ) async throws -> RecordValidationRun.Output {
        let trace = await diagnostics.begin(.outputValidation)
        do {
            let result = try outputDatabase(
                for: command.workspaceID
            ).recordValidationRun(
                command,
                deviceID: deviceID,
                failBeforeCommit: await outputShouldFail()
            )
            await diagnostics.end(trace, outcome: .success)
            return result
        } catch {
            await recordOutputFailure(error, trace: trace)
            throw error
        }
    }

    public func recordReview(
        _ command: RecordReview
    ) async throws -> RecordReview.Output {
        try outputDatabase(for: command.workspaceID).recordReview(
            command,
            deviceID: deviceID,
            failBeforeCommit: await outputShouldFail()
        )
    }

    public func requestChanges(
        _ command: RequestChanges
    ) async throws -> RequestChanges.Output {
        try outputDatabase(for: command.workspaceID).requestChanges(
            command,
            deviceID: deviceID,
            failBeforeCommit: await outputShouldFail()
        )
    }

    public func approveChangeSet(
        _ command: ApproveChangeSet
    ) async throws -> ApproveChangeSet.Output {
        try outputDatabase(for: command.workspaceID).approveChangeSet(
            command,
            deviceID: deviceID,
            failBeforeCommit: await outputShouldFail()
        )
    }

    public func mergeContribution(
        _ command: MergeContribution
    ) async throws -> MergeContribution.Output {
        let trace = await diagnostics.begin(.outputMerge)
        do {
            let result = try outputDatabase(
                for: command.workspaceID
            ).mergeContribution(
                command,
                deviceID: deviceID,
                failBeforeCommit: await outputShouldFail()
            )
            await diagnostics.end(trace, outcome: .success)
            return result
        } catch {
            await recordOutputFailure(error, trace: trace)
            throw error
        }
    }

    public func closeContribution(
        _ command: CloseContribution
    ) async throws -> CloseContribution.Output {
        try outputDatabase(for: command.workspaceID).closeContribution(
            command,
            deviceID: deviceID,
            failBeforeCommit: await outputShouldFail()
        )
    }

    public func output(
        workspaceID: WorkspaceID,
        id: OutputID
    ) throws -> VersoDomain.Output {
        try outputDatabase(for: workspaceID).fetchOutput(id: id)
    }

    public func contribution(
        workspaceID: WorkspaceID,
        id: ContributionID
    ) throws -> Contribution {
        try outputDatabase(for: workspaceID).fetchContribution(id: id)
    }

    public func mergeRecordCount(for workspaceID: WorkspaceID) throws -> Int {
        try outputDatabase(for: workspaceID).mergeRecordCount()
    }

    private func outputDatabase(
        for workspaceID: WorkspaceID
    ) throws -> WorkspaceDatabase {
        guard let database = sessions[workspaceID] else {
            throw PersistenceError.workspaceNotOpen
        }
        return database
    }

    private func outputShouldFail() async -> Bool {
        await failureInjector.shouldFail(at: .databaseTransactionBeforeCommit)
    }

    private func recordOutputFailure(
        _ error: Error,
        trace: DiagnosticTrace
    ) async {
        await diagnostics.record(
            ClassifiedError(
                category: error is OutputMainlineError
                    ? .validation
                    : .persistence,
                operation: trace.operation.rawValue,
                technicalCode: String(describing: error),
                traceID: trace.id
            )
        )
        await diagnostics.end(trace, outcome: .failure)
    }
}
