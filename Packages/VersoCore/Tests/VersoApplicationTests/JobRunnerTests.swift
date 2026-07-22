import Foundation
import Testing
import VersoDomain
@testable import VersoApplication

private actor TestQueue: OutboxQueue {
    private var jobs: [OutboxJob]
    private(set) var completed: [JobID] = []
    private(set) var failures: [JobID] = []

    init(jobs: [OutboxJob]) {
        self.jobs = jobs
    }

    func claimNextJob() -> OutboxJob? {
        jobs.isEmpty ? nil : jobs.removeFirst()
    }

    func markCompleted(jobID: JobID) {
        completed.append(jobID)
    }

    func markFailed(jobID: JobID, reason: String) {
        failures.append(jobID)
    }

    func counts() -> (completed: Int, failed: Int) {
        (completed.count, failures.count)
    }
}

private struct SuccessfulExecutor: BackgroundJobExecuting {
    func execute(_ job: OutboxJob) async throws {}
}

private actor RecordingDiagnostics: DiagnosticsRecording {
    private(set) var operations: [DiagnosticOperation] = []
    private(set) var outcomes: [DiagnosticOutcome] = []
    private(set) var errors: [ClassifiedError] = []

    func begin(_ operation: DiagnosticOperation) -> DiagnosticTrace {
        operations.append(operation)
        return DiagnosticTrace(operation: operation)
    }

    func end(_ trace: DiagnosticTrace, outcome: DiagnosticOutcome) {
        outcomes.append(outcome)
    }

    func record(_ error: ClassifiedError) {
        errors.append(error)
    }

    func snapshot() -> (
        operations: [DiagnosticOperation],
        outcomes: [DiagnosticOutcome],
        errorCount: Int
    ) {
        (operations, outcomes, errors.count)
    }
}

@Suite("Background job runner")
struct JobRunnerTests {
    @Test("A claimed job is marked complete")
    func completesJob() async throws {
        let job = OutboxJob(
            id: JobID(),
            kind: "test",
            payload: Data(),
            idempotencyKey: "test:1",
            attempts: 0
        )
        let queue = TestQueue(jobs: [job])
        let diagnostics = RecordingDiagnostics()
        let runner = JobRunner(
            queue: queue,
            executor: SuccessfulExecutor(),
            diagnostics: diagnostics
        )

        #expect(try await runner.runNext())
        let counts = await queue.counts()
        #expect(counts.completed == 1)
        #expect(counts.failed == 0)
        let diagnosticSnapshot = await diagnostics.snapshot()
        #expect(diagnosticSnapshot.operations == [.backgroundJob])
        #expect(diagnosticSnapshot.outcomes == [.success])
        #expect(diagnosticSnapshot.errorCount == 0)
    }
}
