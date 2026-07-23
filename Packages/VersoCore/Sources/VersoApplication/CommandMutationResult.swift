import VersoDomain

public enum CommandMutationDisposition: String, Codable, Sendable {
    case applied
    case replayed
}

public struct CommandMutationResult<Value>: Codable, Equatable, Sendable
where Value: Codable & Equatable & Sendable {
    public let value: Value
    public let operationID: OperationID
    public let disposition: CommandMutationDisposition

    public init(
        value: Value,
        operationID: OperationID,
        disposition: CommandMutationDisposition
    ) {
        self.value = value
        self.operationID = operationID
        self.disposition = disposition
    }
}
