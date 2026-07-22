public enum FailurePoint: String, Codable, CaseIterable, Sendable {
    case databaseTransactionBeforeCommit
    case fileWriteBeforeReplace
    case applicationTerminationAfterFileCommit
    case backupBeforeFinalize
}

public enum ReliabilityError: Error, Equatable, Sendable {
    case injected(FailurePoint)
}

public protocol FailureInjecting: Sendable {
    func shouldFail(at point: FailurePoint) async -> Bool
}

public struct NoFailureInjector: FailureInjecting {
    public init() {}

    public func shouldFail(at point: FailurePoint) async -> Bool {
        false
    }
}

public actor OneShotFailureInjector: FailureInjecting {
    private var remaining: Set<FailurePoint>

    public init(points: Set<FailurePoint>) {
        remaining = points
    }

    public func shouldFail(at point: FailurePoint) -> Bool {
        remaining.remove(point) != nil
    }
}
