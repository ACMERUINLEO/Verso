import Foundation
import VersoApplication
import VersoBundleFormat
import VersoDomain

extension WorkspaceLifecycleService: KnowledgeAssetServicing {
    public func createActor(_ command: CreateActor) async throws -> CreateActor.Output {
        let database = try openDatabase(for: command.workspaceID)
        return try database.createActor(
            command,
            deviceID: deviceID,
            failBeforeCommit: await shouldFailBeforeCommit()
        )
    }

    public func registerDocumentRevision(
        _ command: RegisterDocumentRevision
    ) async throws -> RegisterDocumentRevision.Output {
        let database = try openDatabase(for: command.workspaceID)
        return try database.registerDocumentRevision(
            command,
            deviceID: deviceID,
            failBeforeCommit: await shouldFailBeforeCommit()
        )
    }

    public func captureSource(
        _ command: CaptureSource
    ) async throws -> CaptureSource.Output {
        let database = try openDatabase(for: command.workspaceID)
        return try database.captureSource(
            command,
            deviceID: deviceID,
            failBeforeCommit: await shouldFailBeforeCommit()
        )
    }

    public func createKnowledgeConcept(
        _ command: CreateKnowledgeConcept
    ) async throws -> CreateKnowledgeConcept.Output {
        let database = try openDatabase(for: command.workspaceID)
        return try database.createKnowledgeConcept(
            command,
            deviceID: deviceID,
            failBeforeCommit: await shouldFailBeforeCommit()
        )
    }

    public func createBundleDraft(
        _ command: CreateBundleDraft
    ) async throws -> CreateBundleDraft.Output {
        let database = try openDatabase(for: command.workspaceID)
        return try database.createBundleDraft(
            command,
            deviceID: deviceID,
            failBeforeCommit: await shouldFailBeforeCommit()
        )
    }

    public func freezeBundleVersion(
        _ command: FreezeBundleVersion
    ) async throws -> FreezeBundleVersion.Output {
        let trace = await diagnostics.begin(.bundleBuild)
        do {
            let database = try openDatabase(for: command.workspaceID)
            let result = try database.freezeBundleVersion(
                command,
                deviceID: deviceID,
                failBeforeCommit: await shouldFailBeforeCommit()
            )
            await diagnostics.end(trace, outcome: .success)
            return result
        } catch {
            await recordKnowledgeFailure(error, trace: trace)
            throw error
        }
    }

    public func bundleArtifact(
        workspaceID: WorkspaceID,
        versionID: BundleVersionID
    ) throws -> OKFArtifact {
        try openDatabase(for: workspaceID).bundleArtifact(versionID: versionID)
    }

    public func pendingIntegrationEventCount(
        for workspaceID: WorkspaceID
    ) throws -> Int {
        try openDatabase(for: workspaceID).pendingIntegrationEventCount()
    }

    public func integrationEventPayloads(
        for workspaceID: WorkspaceID
    ) throws -> [Data] {
        try openDatabase(for: workspaceID).integrationEventPayloads()
    }

    private func openDatabase(for workspaceID: WorkspaceID) throws -> WorkspaceDatabase {
        guard let database = sessions[workspaceID] else {
            throw PersistenceError.workspaceNotOpen
        }
        return database
    }

    private func shouldFailBeforeCommit() async -> Bool {
        await failureInjector.shouldFail(at: .databaseTransactionBeforeCommit)
    }

    private func recordKnowledgeFailure(
        _ error: Error,
        trace: DiagnosticTrace
    ) async {
        await diagnostics.record(
            ClassifiedError(
                category: error is KnowledgeAssetError
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
