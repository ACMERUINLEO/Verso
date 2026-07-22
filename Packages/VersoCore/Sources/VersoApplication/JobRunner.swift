import Foundation
import VersoDomain

public struct OutboxJob: Codable, Equatable, Sendable {
    public let id: JobID
    public let kind: String
    public let payload: Data
    public let idempotencyKey: String
    public let attempts: Int

    public init(
        id: JobID,
        kind: String,
        payload: Data,
        idempotencyKey: String,
        attempts: Int
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.idempotencyKey = idempotencyKey
        self.attempts = attempts
    }
}

public protocol OutboxQueue: Sendable {
    func claimNextJob() async throws -> OutboxJob?
    func markCompleted(jobID: JobID) async throws
    func markFailed(jobID: JobID, reason: String) async throws
}

public protocol BackgroundJobExecuting: Sendable {
    func execute(_ job: OutboxJob) async throws
}

public actor JobRunner {
    private let queue: any OutboxQueue
    private let executor: any BackgroundJobExecuting
    private let diagnostics: any DiagnosticsRecording

    public init(
        queue: any OutboxQueue,
        executor: any BackgroundJobExecuting,
        diagnostics: any DiagnosticsRecording = NoopDiagnosticsRecorder()
    ) {
        self.queue = queue
        self.executor = executor
        self.diagnostics = diagnostics
    }

    @discardableResult
    public func runNext() async throws -> Bool {
        let trace = await diagnostics.begin(.backgroundJob)
        do {
            guard let job = try await queue.claimNextJob() else {
                await diagnostics.end(trace, outcome: .success)
                return false
            }

            do {
                try await executor.execute(job)
                try await queue.markCompleted(jobID: job.id)
                await diagnostics.end(trace, outcome: .success)
            } catch {
                try await queue.markFailed(
                    jobID: job.id,
                    reason: String(describing: error)
                )
                await diagnostics.record(
                    ClassifiedError(
                        category: .unknown,
                        operation: DiagnosticOperation.backgroundJob.rawValue,
                        technicalCode: String(describing: error),
                        traceID: trace.id
                    )
                )
                await diagnostics.end(trace, outcome: .failure)
            }
            return true
        } catch {
            await diagnostics.record(
                ClassifiedError(
                    category: .persistence,
                    operation: DiagnosticOperation.backgroundJob.rawValue,
                    technicalCode: String(describing: error),
                    traceID: trace.id
                )
            )
            await diagnostics.end(trace, outcome: .failure)
            throw error
        }
    }
}
