import VersoDomain

public struct WorkspaceLocation: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct CreateWorkspace: ApplicationCommand {
    public static let identifier = "workspace.create.v1"
    public typealias Output = Workspace

    public let name: String
    public let location: WorkspaceLocation
    public let operationID: OperationID

    public init(
        name: String,
        location: WorkspaceLocation,
        operationID: OperationID = OperationID()
    ) {
        self.name = name
        self.location = location
        self.operationID = operationID
    }
}

public struct RenameWorkspace: ApplicationCommand {
    public static let identifier = "workspace.rename.v1"
    public typealias Output = WorkspaceMutationResult

    public let workspaceID: WorkspaceID
    public let name: String
    public let expectedRevision: Int64
    public let operationID: OperationID

    public init(
        workspaceID: WorkspaceID,
        name: String,
        expectedRevision: Int64,
        operationID: OperationID = OperationID()
    ) {
        self.workspaceID = workspaceID
        self.name = name
        self.expectedRevision = expectedRevision
        self.operationID = operationID
    }
}

public enum WorkspaceMutationDisposition: String, Codable, Sendable {
    case applied
    case replayed
}

public struct WorkspaceMutationResult: Codable, Equatable, Sendable {
    public let workspace: Workspace
    public let operationID: OperationID
    public let disposition: WorkspaceMutationDisposition

    public init(
        workspace: Workspace,
        operationID: OperationID,
        disposition: WorkspaceMutationDisposition
    ) {
        self.workspace = workspace
        self.operationID = operationID
        self.disposition = disposition
    }
}

public struct OpenWorkspace: ApplicationCommand {
    public static let identifier = "workspace.open.v1"
    public typealias Output = WorkspaceOpenOutcome

    public let location: WorkspaceLocation

    public init(location: WorkspaceLocation) {
        self.location = location
    }
}

public struct CloseWorkspace: ApplicationCommand {
    public static let identifier = "workspace.close.v1"
    public typealias Output = Workspace

    public let workspaceID: WorkspaceID

    public init(workspaceID: WorkspaceID) {
        self.workspaceID = workspaceID
    }
}

public struct RestoreWorkspace: ApplicationCommand {
    public static let identifier = "workspace.restore.v1"
    public typealias Output = WorkspaceOpenOutcome

    public let location: WorkspaceLocation
    public let backupLocation: WorkspaceLocation

    public init(
        location: WorkspaceLocation,
        backupLocation: WorkspaceLocation
    ) {
        self.location = location
        self.backupLocation = backupLocation
    }
}

public struct RecoveryContext: Codable, Equatable, Sendable {
    public let location: WorkspaceLocation
    public let reason: String
    public let backupLocations: [WorkspaceLocation]

    public init(
        location: WorkspaceLocation,
        reason: String,
        backupLocations: [WorkspaceLocation]
    ) {
        self.location = location
        self.reason = reason
        self.backupLocations = backupLocations
    }
}

public enum WorkspaceOpenOutcome: Sendable {
    case ready(Workspace)
    case recoveryRequired(RecoveryContext)
}

public protocol WorkspaceLifecycleServicing: Sendable {
    func createWorkspace(
        name: String,
        at location: WorkspaceLocation,
        operationID: OperationID
    ) async throws -> Workspace
    func openWorkspace(at location: WorkspaceLocation) async -> WorkspaceOpenOutcome
    func closeWorkspace(id: WorkspaceID) async throws -> Workspace
    func renameWorkspace(
        id: WorkspaceID,
        to name: String,
        expectedRevision: Int64,
        operationID: OperationID
    ) async throws -> WorkspaceMutationResult
    func restoreWorkspace(
        at location: WorkspaceLocation,
        from backupLocation: WorkspaceLocation
    ) async throws -> WorkspaceOpenOutcome
}

public enum WorkspaceCommandRegistration {
    public static func install<Service: WorkspaceLifecycleServicing>(
        on bus: CommandBus,
        service: Service
    ) async throws {
        try await bus.register(CreateWorkspace.self) { command in
            try await service.createWorkspace(
                name: command.name,
                at: command.location,
                operationID: command.operationID
            )
        }
        try await bus.register(RenameWorkspace.self) { command in
            try await service.renameWorkspace(
                id: command.workspaceID,
                to: command.name,
                expectedRevision: command.expectedRevision,
                operationID: command.operationID
            )
        }
        try await bus.register(OpenWorkspace.self) { command in
            await service.openWorkspace(at: command.location)
        }
        try await bus.register(CloseWorkspace.self) { command in
            try await service.closeWorkspace(id: command.workspaceID)
        }
        try await bus.register(RestoreWorkspace.self) { command in
            try await service.restoreWorkspace(
                at: command.location,
                from: command.backupLocation
            )
        }
    }
}
