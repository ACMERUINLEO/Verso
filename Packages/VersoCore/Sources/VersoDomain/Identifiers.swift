import Foundation

public protocol DomainIdentifier: RawRepresentable, Codable, Hashable, Sendable
where RawValue == UUID {
    init(rawValue: UUID)
}

public extension DomainIdentifier {
    init() {
        self.init(rawValue: UUID())
    }
}

public struct WorkspaceID: DomainIdentifier {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct NodeID: DomainIdentifier {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct JobID: DomainIdentifier {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct OperationID: DomainIdentifier {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct DeviceID: DomainIdentifier {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct SyncOutboxEntryID: DomainIdentifier {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}
