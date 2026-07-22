import Foundation

public struct WorkspaceLayout: Equatable, Sendable {
    public let root: URL
    public let metadataRoot: URL
    public let documents: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        let hiddenMetadataRoot = self.root.appending(
            path: ".verso",
            directoryHint: .isDirectory
        )
        let legacyDatabase = self.root.appending(path: "workspace.sqlite")
        let usesLegacyLayout = FileManager.default.fileExists(
            atPath: legacyDatabase.path
        ) && !FileManager.default.fileExists(
            atPath: hiddenMetadataRoot.appending(path: "workspace.sqlite").path
        )

        if usesLegacyLayout {
            metadataRoot = self.root
            documents = self.root.appending(
                path: "Documents",
                directoryHint: .isDirectory
            )
        } else {
            metadataRoot = hiddenMetadataRoot
            documents = self.root
        }
    }

    public var database: URL { metadataRoot.appending(path: "workspace.sqlite") }
    public var managedFiles: URL { metadataRoot.appending(path: "ManagedFiles", directoryHint: .isDirectory) }
    public var backups: URL { metadataRoot.appending(path: "Backups", directoryHint: .isDirectory) }
    public var recovery: URL { metadataRoot.appending(path: "Recovery", directoryHint: .isDirectory) }

    func createDirectories() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for directory in [metadataRoot, managedFiles, backups, recovery] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if documents != root {
            try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        }
    }
}
