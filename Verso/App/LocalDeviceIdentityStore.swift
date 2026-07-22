import Foundation
import VersoDomain

struct LocalDeviceIdentityStore {
    private static let key = "device.identity.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadOrCreate() -> DeviceID {
        if
            let stored = defaults.string(forKey: Self.key),
            let uuid = UUID(uuidString: stored)
        {
            return DeviceID(rawValue: uuid)
        }

        let identity = DeviceID()
        defaults.set(identity.rawValue.uuidString, forKey: Self.key)
        return identity
    }
}
