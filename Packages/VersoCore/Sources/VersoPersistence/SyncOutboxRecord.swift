import Foundation
import VersoDomain
import VersoSyncProtocol

public struct SyncOutboxRecord: Equatable, Sendable {
    public let id: SyncOutboxEntryID
    public let workspaceID: WorkspaceID
    public let sourceDeviceID: DeviceID
    public let change: SyncChange

    public init(
        id: SyncOutboxEntryID,
        workspaceID: WorkspaceID,
        sourceDeviceID: DeviceID,
        change: SyncChange
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.sourceDeviceID = sourceDeviceID
        self.change = change
    }
}

struct WorkspaceSyncPayload: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let name: String
    let defaultTimeZoneID: String
    let rootNodeID: NodeID
    let revision: Int64
    let modifiedAt: Date
    let deletedAt: Date?
}
