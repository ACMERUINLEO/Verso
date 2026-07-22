public struct CreateMarkdownDocument: ApplicationCommand {
    public static let identifier = "workspace.document.create-markdown.v1"
    public typealias Output = WorkspaceLocation

    public let workspaceLocation: WorkspaceLocation
    public let preferredName: String

    public init(workspaceLocation: WorkspaceLocation, preferredName: String) {
        self.workspaceLocation = workspaceLocation
        self.preferredName = preferredName
    }
}

public struct ImportWorkspaceFiles: ApplicationCommand {
    public static let identifier = "workspace.document.import.v1"
    public typealias Output = [WorkspaceLocation]

    public let workspaceLocation: WorkspaceLocation
    public let sourceLocations: [WorkspaceLocation]

    public init(
        workspaceLocation: WorkspaceLocation,
        sourceLocations: [WorkspaceLocation]
    ) {
        self.workspaceLocation = workspaceLocation
        self.sourceLocations = sourceLocations
    }
}

public struct ReadWorkspaceTextDocument: ApplicationCommand {
    public static let identifier = "workspace.document.read-text.v1"
    public typealias Output = String

    public let workspaceLocation: WorkspaceLocation
    public let documentLocation: WorkspaceLocation

    public init(
        workspaceLocation: WorkspaceLocation,
        documentLocation: WorkspaceLocation
    ) {
        self.workspaceLocation = workspaceLocation
        self.documentLocation = documentLocation
    }
}

public struct SaveWorkspaceTextDocument: ApplicationCommand {
    public static let identifier = "workspace.document.save-text.v1"
    public typealias Output = WorkspaceLocation

    public let workspaceLocation: WorkspaceLocation
    public let documentLocation: WorkspaceLocation
    public let contents: String

    public init(
        workspaceLocation: WorkspaceLocation,
        documentLocation: WorkspaceLocation,
        contents: String
    ) {
        self.workspaceLocation = workspaceLocation
        self.documentLocation = documentLocation
        self.contents = contents
    }
}

public protocol WorkspaceDocumentServicing: Sendable {
    func createMarkdownDocument(
        in workspaceLocation: WorkspaceLocation,
        preferredName: String
    ) async throws -> WorkspaceLocation

    func importFiles(
        from sourceLocations: [WorkspaceLocation],
        into workspaceLocation: WorkspaceLocation
    ) async throws -> [WorkspaceLocation]

    func readTextDocument(
        at documentLocation: WorkspaceLocation,
        in workspaceLocation: WorkspaceLocation
    ) async throws -> String

    func saveTextDocument(
        _ contents: String,
        at documentLocation: WorkspaceLocation,
        in workspaceLocation: WorkspaceLocation
    ) async throws -> WorkspaceLocation
}

public enum WorkspaceDocumentCommandRegistration {
    public static func install<Service: WorkspaceDocumentServicing>(
        on bus: CommandBus,
        service: Service
    ) async throws {
        try await bus.register(CreateMarkdownDocument.self) { command in
            try await service.createMarkdownDocument(
                in: command.workspaceLocation,
                preferredName: command.preferredName
            )
        }
        try await bus.register(ImportWorkspaceFiles.self) { command in
            try await service.importFiles(
                from: command.sourceLocations,
                into: command.workspaceLocation
            )
        }
        try await bus.register(ReadWorkspaceTextDocument.self) { command in
            try await service.readTextDocument(
                at: command.documentLocation,
                in: command.workspaceLocation
            )
        }
        try await bus.register(SaveWorkspaceTextDocument.self) { command in
            try await service.saveTextDocument(
                command.contents,
                at: command.documentLocation,
                in: command.workspaceLocation
            )
        }
    }
}
