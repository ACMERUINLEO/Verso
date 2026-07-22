import Foundation

public struct Workspace: Codable, Equatable, Sendable {
    public let id: WorkspaceID
    public var name: String
    public let schemaVersion: Int
    public let rootNodeID: NodeID
    public let createdAt: Date
    public var modifiedAt: Date
    public var defaultTimeZoneID: String
    public var lifecycleState: WorkspaceLifecycleState
    public var revision: Int64
    public var deletedAt: Date?

    public init(
        id: WorkspaceID,
        name: String,
        schemaVersion: Int,
        rootNodeID: NodeID,
        createdAt: Date,
        modifiedAt: Date,
        defaultTimeZoneID: String,
        lifecycleState: WorkspaceLifecycleState,
        revision: Int64 = 1,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.schemaVersion = schemaVersion
        self.rootNodeID = rootNodeID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.defaultTimeZoneID = defaultTimeZoneID
        self.lifecycleState = lifecycleState
        self.revision = revision
        self.deletedAt = deletedAt
    }
}

public enum WorkspaceLifecycleState: String, Codable, Sendable {
    case active
    case closed
    case recoveryRequired
}

public enum DomainError: Error, Equatable, Sendable {
    case invalidWorkspaceName
    case invalidStateTransition
    case invalidRevision
}

public extension Workspace {
    static func create(
        name: String,
        schemaVersion: Int = 1,
        now: Date = Date()
    ) throws -> Workspace {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw DomainError.invalidWorkspaceName
        }

        return Workspace(
            id: WorkspaceID(),
            name: normalizedName,
            schemaVersion: schemaVersion,
            rootNodeID: NodeID(),
            createdAt: now,
            modifiedAt: now,
            defaultTimeZoneID: TimeZone.current.identifier,
            lifecycleState: .active,
            revision: 1,
            deletedAt: nil
        )
    }


    func renamed(to name: String, at date: Date = Date()) throws -> Workspace {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw DomainError.invalidWorkspaceName
        }
        guard revision < Int64.max else {
            throw DomainError.invalidRevision
        }

        var copy = self
        copy.name = normalizedName
        copy.modifiedAt = date
        copy.revision += 1
        return copy
    }
}
