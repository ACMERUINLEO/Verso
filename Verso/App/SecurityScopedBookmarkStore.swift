import Foundation

@MainActor
protocol WorkspaceAccessManaging: AnyObject {
    var hasPersistedWorkspace: Bool { get }

    func beginAccess(to url: URL) throws -> URL
    func persistActiveAccess() throws
    func restoreLastAccess() throws -> URL?
    func releaseActiveAccess()
    func clearPersistedAccess()
}

@MainActor
final class SecurityScopedBookmarkStore: WorkspaceAccessManaging {
    enum BookmarkError: LocalizedError {
        case noActiveWorkspace

        var errorDescription: String? {
            switch self {
            case .noActiveWorkspace:
                "没有可保存的 Workspace 访问权限。"
            }
        }
    }

    private enum Keys {
        static let lastWorkspaceBookmark = "workspace.last.security-scoped-bookmark"
    }

    private let defaults: UserDefaults
    private var activeURL: URL?
    private var activeBookmarkData: Data?
    private var didStartSecurityScope = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasPersistedWorkspace: Bool {
        defaults.data(forKey: Keys.lastWorkspaceBookmark) != nil
    }

    func beginAccess(to url: URL) throws -> URL {
        releaseActiveAccess()

        let didStart = url.startAccessingSecurityScopedResource()
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: [.nameKey, .isDirectoryKey],
                relativeTo: nil
            )
            activeURL = url
            activeBookmarkData = bookmarkData
            didStartSecurityScope = didStart
            return url
        } catch {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
            throw error
        }
    }

    func persistActiveAccess() throws {
        guard let activeBookmarkData else {
            throw BookmarkError.noActiveWorkspace
        }
        defaults.set(activeBookmarkData, forKey: Keys.lastWorkspaceBookmark)
    }

    func restoreLastAccess() throws -> URL? {
        guard let bookmarkData = defaults.data(forKey: Keys.lastWorkspaceBookmark) else {
            return nil
        }

        releaseActiveAccess()
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        let didStart = url.startAccessingSecurityScopedResource()
        activeURL = url
        didStartSecurityScope = didStart

        if isStale {
            do {
                activeBookmarkData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: [.nameKey, .isDirectoryKey],
                    relativeTo: nil
                )
                try persistActiveAccess()
            } catch {
                releaseActiveAccess()
                throw error
            }
        } else {
            activeBookmarkData = bookmarkData
        }

        return url
    }

    func releaseActiveAccess() {
        if didStartSecurityScope, let activeURL {
            activeURL.stopAccessingSecurityScopedResource()
        }
        activeURL = nil
        activeBookmarkData = nil
        didStartSecurityScope = false
    }

    func clearPersistedAccess() {
        defaults.removeObject(forKey: Keys.lastWorkspaceBookmark)
    }

    deinit {
        if didStartSecurityScope, let activeURL {
            activeURL.stopAccessingSecurityScopedResource()
        }
    }
}
