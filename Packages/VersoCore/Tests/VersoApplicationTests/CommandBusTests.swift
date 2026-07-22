import Testing
@testable import VersoApplication

private struct EchoCommand: ApplicationCommand {
    static let identifier = "test.echo"
    typealias Output = String

    let value: String
}

@Suite("Command bus")
struct CommandBusTests {
    @Test("Registered commands return typed outputs")
    func registeredCommand() async throws {
        let bus = CommandBus()
        try await bus.register(EchoCommand.self) { command in
            command.value.uppercased()
        }

        let output = try await bus.send(EchoCommand(value: "verso"))

        #expect(output == "VERSO")
    }

    @Test("Unregistered commands fail closed")
    func missingCommand() async {
        let bus = CommandBus()

        await #expect(throws: CommandBusError.missingHandler("test.echo")) {
            try await bus.send(EchoCommand(value: "verso"))
        }
    }

    @Test("Duplicate handlers are rejected")
    func duplicateRegistration() async throws {
        let bus = CommandBus()
        try await bus.register(EchoCommand.self) { $0.value }

        await #expect(throws: CommandBusError.duplicateHandler("test.echo")) {
            try await bus.register(EchoCommand.self) { $0.value }
        }
    }
}
