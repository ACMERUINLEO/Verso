import Foundation

public protocol ApplicationCommand: Sendable {
    associatedtype Output: Sendable
    static var identifier: String { get }
}

public enum CommandBusError: Error, Equatable, Sendable {
    case duplicateHandler(String)
    case missingHandler(String)
    case typeMismatch(String)
}

public actor CommandBus {
    private struct Handler: @unchecked Sendable {
        let invoke: @Sendable (any Sendable) async throws -> any Sendable
    }

    private var handlers: [ObjectIdentifier: Handler] = [:]

    public init() {}

    public func register<Command: ApplicationCommand>(
        _ commandType: Command.Type,
        handler: @escaping @Sendable (Command) async throws -> Command.Output
    ) throws {
        let key = ObjectIdentifier(commandType)
        guard handlers[key] == nil else {
            throw CommandBusError.duplicateHandler(Command.identifier)
        }

        handlers[key] = Handler { command in
            guard let typedCommand = command as? Command else {
                throw CommandBusError.typeMismatch(Command.identifier)
            }
            return try await handler(typedCommand)
        }
    }

    public func send<Command: ApplicationCommand>(
        _ command: Command
    ) async throws -> Command.Output {
        let key = ObjectIdentifier(Command.self)
        guard let handler = handlers[key] else {
            throw CommandBusError.missingHandler(Command.identifier)
        }

        let output = try await handler.invoke(command)
        guard let typedOutput = output as? Command.Output else {
            throw CommandBusError.typeMismatch(Command.identifier)
        }
        return typedOutput
    }
}
