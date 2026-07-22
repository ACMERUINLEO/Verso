import VersoApplication
import VersoDomain

public actor WorkspaceOutboxQueue: OutboxQueue {
    private let database: WorkspaceDatabase

    init(database: WorkspaceDatabase) {
        self.database = database
    }

    public func claimNextJob() async throws -> OutboxJob? {
        try database.claimNextJob()
    }

    public func markCompleted(jobID: JobID) async throws {
        try database.markJobCompleted(id: jobID)
    }

    public func markFailed(jobID: JobID, reason: String) async throws {
        try database.markJobFailed(id: jobID, reason: reason)
    }
}
