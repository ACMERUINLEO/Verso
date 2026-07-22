import Foundation
import Testing
import VersoApplication
@testable import VersoFileSystem

@Suite("Workspace documents")
struct WorkspaceDocumentServiceTests {
    @Test("Markdown documents are created, saved, and read in the workspace root")
    func markdownRoundTrip() async throws {
        let root = try makeWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceDocumentService()
        let workspace = WorkspaceLocation(rawValue: root.path)

        let created = try await service.createMarkdownDocument(
            in: workspace,
            preferredName: "Notes"
        )
        #expect(
            URL(filePath: created.rawValue).deletingLastPathComponent().path
                == root.path
        )
        #expect(URL(filePath: created.rawValue).lastPathComponent == "Notes.md")

        _ = try await service.saveTextDocument(
            "# Notes\n",
            at: created,
            in: workspace
        )
        let contents = try await service.readTextDocument(
            at: created,
            in: workspace
        )
        #expect(contents == "# Notes\n")
    }

    @Test("Imports avoid overwriting existing files")
    func importWithCollision() async throws {
        let root = try makeWorkspaceRoot()
        let sourceRoot = FileManager.default.temporaryDirectory
            .appending(path: "VersoImportSource-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        try FileManager.default.createDirectory(
            at: sourceRoot,
            withIntermediateDirectories: true
        )
        let source = sourceRoot.appending(path: "Idea.md")
        try Data("first".utf8).write(to: source)

        let service = WorkspaceDocumentService()
        let workspace = WorkspaceLocation(rawValue: root.path)
        let first = try await service.importFiles(
            from: [WorkspaceLocation(rawValue: source.path)],
            into: workspace
        )
        let second = try await service.importFiles(
            from: [WorkspaceLocation(rawValue: source.path)],
            into: workspace
        )

        #expect(URL(filePath: first[0].rawValue).lastPathComponent == "Idea.md")
        #expect(URL(filePath: second[0].rawValue).lastPathComponent == "Idea 2.md")
    }

    @Test("Folders are imported recursively with their contents")
    func importFolder() async throws {
        let root = try makeWorkspaceRoot()
        let sourceRoot = FileManager.default.temporaryDirectory
            .appending(path: "VersoFolderImportSource-\(UUID().uuidString)")
        let sourceFolder = sourceRoot.appending(path: "Research")
        let sourceNotes = sourceFolder.appending(path: "Notes")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        try FileManager.default.createDirectory(
            at: sourceNotes,
            withIntermediateDirectories: true
        )
        try Data("# Imported".utf8).write(
            to: sourceNotes.appending(path: "Idea.md")
        )

        let service = WorkspaceDocumentService()
        let workspace = WorkspaceLocation(rawValue: root.path)
        let imported = try await service.importFiles(
            from: [WorkspaceLocation(rawValue: sourceFolder.path)],
            into: workspace
        )

        #expect(imported.count == 1)
        let nestedDocument = URL(filePath: imported[0].rawValue)
            .appending(path: "Notes/Idea.md")
        #expect(
            try String(contentsOf: nestedDocument, encoding: .utf8) == "# Imported"
        )
    }

    @Test("Internal metadata cannot be edited as a document")
    func metadataIsProtected() async throws {
        let root = try makeWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceDocumentService()
        let workspace = WorkspaceLocation(rawValue: root.path)
        let internalDocument = WorkspaceLocation(
            rawValue: root.appending(path: ".verso/secret.md").path
        )

        await #expect(throws: WorkspaceDocumentError.metadataAccessDenied) {
            try await service.saveTextDocument(
                "secret",
                at: internalDocument,
                in: workspace
            )
        }
    }

    private func makeWorkspaceRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "VersoDocumentTests-\(UUID().uuidString)")
        let metadata = root.appending(path: ".verso")
        try FileManager.default.createDirectory(
            at: metadata,
            withIntermediateDirectories: true
        )
        try Data().write(to: metadata.appending(path: "workspace.sqlite"))
        return root
    }
}
