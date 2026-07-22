import Foundation

public struct BackupPolicy: Equatable, Sendable {
    public let maximumRegularBackups: Int
    public let minimumFreeSpaceReserveBytes: Int64

    public init(
        maximumRegularBackups: Int = 10,
        minimumFreeSpaceReserveBytes: Int64 = 64 * 1_048_576
    ) {
        self.maximumRegularBackups = max(1, maximumRegularBackups)
        self.minimumFreeSpaceReserveBytes = max(0, minimumFreeSpaceReserveBytes)
    }
}

public protocol DiskCapacityProviding: Sendable {
    func availableCapacity(at url: URL) throws -> Int64?
}

public struct VolumeDiskCapacityProvider: DiskCapacityProviding {
    public init() {}

    public func availableCapacity(at url: URL) throws -> Int64? {
        let values = try url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        if let importantUsage = values.volumeAvailableCapacityForImportantUsage {
            return importantUsage
        }
        if let available = values.volumeAvailableCapacity {
            return Int64(available)
        }
        return nil
    }
}
