import Foundation
import VersoApplication

public enum WorkspaceDocumentError: LocalizedError, Equatable, Sendable {
    case invalidName
    case locationOutsideWorkspace
    case metadataAccessDenied
    case unsupportedDocumentType
    case documentTooLarge(maximumBytes: Int)
    case invalidTextEncoding
    case recursiveImport

    public var errorDescription: String? {
        switch self {
        case .invalidName:
            "文件名不能为空。"
        case .locationOutsideWorkspace:
            "目标文件不在当前 Workspace 中。"
        case .metadataAccessDenied:
            "不能直接访问 Workspace 的内部元数据。"
        case .unsupportedDocumentType:
            "当前只支持编辑 Markdown 文档。"
        case let .documentTooLarge(maximumBytes):
            "文档超过可编辑上限（\(maximumBytes / 1_048_576) MB）。"
        case .invalidTextEncoding:
            "文档不是有效的 UTF-8 文本。"
        case .recursiveImport:
            "不能把 Workspace 或它的上级目录导入自身。"
        }
    }
}

public actor WorkspaceDocumentService: WorkspaceDocumentServicing {
    private static let maximumEditableDocumentBytes = 5 * 1_048_576
    private let fileManager: FileManager
    private let diagnostics: any DiagnosticsRecording

    public init(
        fileManager: FileManager = .default,
        diagnostics: any DiagnosticsRecording = NoopDiagnosticsRecorder()
    ) {
        self.fileManager = fileManager
        self.diagnostics = diagnostics
    }

    public func createMarkdownDocument(
        in workspaceLocation: WorkspaceLocation,
        preferredName: String
    ) async throws -> WorkspaceLocation {
        let layout = layout(for: workspaceLocation)
        let destination = try uniqueDestination(
            named: normalizedMarkdownName(preferredName),
            in: layout.contentRoot
        )
        let writer = AtomicFileWriter(
            recoveryDirectory: layout.recoveryRoot,
            diagnostics: diagnostics
        )
        try await writer.write(Data(), to: destination)
        return WorkspaceLocation(rawValue: destination.path)
    }

    public func importFiles(
        from sourceLocations: [WorkspaceLocation],
        into workspaceLocation: WorkspaceLocation
    ) async throws -> [WorkspaceLocation] {
        let layout = layout(for: workspaceLocation)
        var imported: [WorkspaceLocation] = []
        imported.reserveCapacity(sourceLocations.count)

        for sourceLocation in sourceLocations {
            let source = URL(filePath: sourceLocation.rawValue)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            try preventRecursiveImport(source: source, workspaceRoot: layout.root)
            let destination = try uniqueDestination(
                named: source.lastPathComponent,
                in: layout.contentRoot
            )
            let temporary = layout.contentRoot.appending(
                path: ".verso-import-\(UUID().uuidString)"
            )
            do {
                try fileManager.copyItem(at: source, to: temporary)
                try fileManager.moveItem(at: temporary, to: destination)
                imported.append(WorkspaceLocation(rawValue: destination.path))
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw error
            }
        }

        return imported
    }

    public func readTextDocument(
        at documentLocation: WorkspaceLocation,
        in workspaceLocation: WorkspaceLocation
    ) async throws -> String {
        let layout = layout(for: workspaceLocation)
        let document = try validatedMarkdownURL(
            documentLocation,
            layout: layout
        )
        let values = try document.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize,
           fileSize > Self.maximumEditableDocumentBytes {
            throw WorkspaceDocumentError.documentTooLarge(
                maximumBytes: Self.maximumEditableDocumentBytes
            )
        }
        let data = try Data(contentsOf: document)
        guard data.count <= Self.maximumEditableDocumentBytes else {
            throw WorkspaceDocumentError.documentTooLarge(
                maximumBytes: Self.maximumEditableDocumentBytes
            )
        }
        guard let contents = String(data: data, encoding: .utf8) else {
            throw WorkspaceDocumentError.invalidTextEncoding
        }
        return contents
    }

    public func saveTextDocument(
        _ contents: String,
        at documentLocation: WorkspaceLocation,
        in workspaceLocation: WorkspaceLocation
    ) async throws -> WorkspaceLocation {
        let layout = layout(for: workspaceLocation)
        let document = try validatedMarkdownURL(
            documentLocation,
            layout: layout
        )
        let data = Data(contents.utf8)
        guard data.count <= Self.maximumEditableDocumentBytes else {
            throw WorkspaceDocumentError.documentTooLarge(
                maximumBytes: Self.maximumEditableDocumentBytes
            )
        }
        let writer = AtomicFileWriter(
            recoveryDirectory: layout.recoveryRoot,
            diagnostics: diagnostics
        )
        try await writer.write(data, to: document)
        return WorkspaceLocation(rawValue: document.path)
    }

    private func normalizedMarkdownName(_ preferredName: String) throws -> String {
        let proposed = URL(filePath: preferredName).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proposed.isEmpty, proposed != ".", proposed != ".." else {
            throw WorkspaceDocumentError.invalidName
        }
        if proposed.lowercased().hasSuffix(".md") ||
            proposed.lowercased().hasSuffix(".markdown") {
            return proposed
        }
        return proposed + ".md"
    }

    private func uniqueDestination(named name: String, in directory: URL) throws -> URL {
        let safeName = URL(filePath: name).lastPathComponent
        guard !safeName.isEmpty, safeName != ".", safeName != ".." else {
            throw WorkspaceDocumentError.invalidName
        }

        var destination = directory.appending(path: safeName)
        guard fileManager.fileExists(atPath: destination.path) else {
            return destination
        }

        let extensionName = destination.pathExtension
        let baseName = destination.deletingPathExtension().lastPathComponent
        var suffix = 2
        repeat {
            let candidateName = extensionName.isEmpty
                ? "\(baseName) \(suffix)"
                : "\(baseName) \(suffix).\(extensionName)"
            destination = directory.appending(path: candidateName)
            suffix += 1
        } while fileManager.fileExists(atPath: destination.path)
        return destination
    }

    private func validatedMarkdownURL(
        _ location: WorkspaceLocation,
        layout: Layout
    ) throws -> URL {
        let document = URL(filePath: location.rawValue)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = layout.contentRoot.path
        guard document.path.hasPrefix(rootPath + "/") else {
            throw WorkspaceDocumentError.locationOutsideWorkspace
        }
        if layout.contentRoot == layout.root {
            let metadataPath = layout.metadataRoot.path
            guard document.path != metadataPath,
                  !document.path.hasPrefix(metadataPath + "/") else {
                throw WorkspaceDocumentError.metadataAccessDenied
            }
        }
        guard ["md", "markdown"].contains(document.pathExtension.lowercased()) else {
            throw WorkspaceDocumentError.unsupportedDocumentType
        }
        return document
    }

    private func preventRecursiveImport(source: URL, workspaceRoot: URL) throws {
        let rootPath = workspaceRoot.path
        let sourcePath = source.path
        if sourcePath == rootPath || rootPath.hasPrefix(sourcePath + "/") {
            throw WorkspaceDocumentError.recursiveImport
        }
    }

    private func layout(for location: WorkspaceLocation) -> Layout {
        let root = URL(filePath: location.rawValue)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let hiddenMetadata = root.appending(
            path: ".verso",
            directoryHint: .isDirectory
        )
        if fileManager.fileExists(
            atPath: hiddenMetadata.appending(path: "workspace.sqlite").path
        ) {
            return Layout(
                root: root,
                metadataRoot: hiddenMetadata,
                contentRoot: root
            )
        }
        return Layout(
            root: root,
            metadataRoot: root,
            contentRoot: root.appending(path: "Documents", directoryHint: .isDirectory)
        )
    }

    private struct Layout {
        let root: URL
        let metadataRoot: URL
        let contentRoot: URL

        var recoveryRoot: URL {
            metadataRoot.appending(path: "Recovery", directoryHint: .isDirectory)
        }
    }
}
