import Foundation
import VersoDomain

public enum PersistenceError: Error, Equatable, Sendable {
    case workspaceAlreadyExists
    case workspaceDatabaseMissing
    case workspaceMetadataMissing
    case workspaceNotOpen
    case invalidStoredIdentity
    case integrityCheckFailed(String)
    case backupMissing
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)
    case operationIDConflict(OperationID)
    case revisionConflict(expected: Int64, actual: Int64)
}
