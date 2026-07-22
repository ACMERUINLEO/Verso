//
//  VersoTests.swift
//  VersoTests
//
//  Created by Leo Chen on 2026/7/22.
//

import Testing
import Foundation
import VersoApplication
import VersoDomain
import VersoPersistence
@testable import Verso

struct VersoTests {

    @MainActor
    @Test func localDeviceIdentityRemainsStableAcrossStoreInstances() throws {
        let suiteName = "VersoDeviceIdentityTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Expected an isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = LocalDeviceIdentityStore(defaults: defaults).loadOrCreate()
        let second = LocalDeviceIdentityStore(defaults: defaults).loadOrCreate()

        #expect(first == second)
    }

    @Test func fileTreeLoadsNestedItemsAndSkipsHiddenFiles() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appending(path: "VersoFileTreeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let folderURL = rootURL.appending(path: "Notes", directoryHint: .isDirectory)
        let nestedFileURL = folderURL.appending(path: "Idea.md", directoryHint: .notDirectory)
        let rootFileURL = rootURL.appending(path: "Brief.pdf", directoryHint: .notDirectory)
        let hiddenFileURL = rootURL.appending(path: ".verso-hidden", directoryHint: .notDirectory)

        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data("# Idea".utf8).write(to: nestedFileURL)
        try Data().write(to: rootFileURL)
        try Data().write(to: hiddenFileURL)

        defer {
            try? fileManager.removeItem(at: rootURL)
        }

        let tree = try await FileTreeLoader.load(from: rootURL)

        #expect(tree.kind == .directory)
        #expect(tree.children?.map(\.name) == ["Notes", "Brief.pdf"])
        #expect(tree.node(withID: nestedFileURL.standardizedFileURL.path)?.name == "Idea.md")
        #expect(tree.node(withID: hiddenFileURL.standardizedFileURL.path) == nil)
    }

}

@MainActor
@Suite("Workspace app shell")
struct WorkspaceAppShellTests {
    @Test("The shell creates, closes, and reopens the last workspace")
    func createCloseReopen() async throws {
        let rootURL = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let accessManager = TestWorkspaceAccessManager()
        let environment = AppEnvironment()
        try await environment.start()
        let shell = WorkspaceShellModel(accessManager: accessManager)
        await shell.start(commandBus: environment.commandBus)

        await shell.createWorkspace(name: "Shell Test", at: rootURL)
        guard case let .workspace(createdSession) = shell.phase else {
            Issue.record("Expected the created workspace to be open")
            return
        }
        let createdID = createdSession.workspace.id
        #expect(accessManager.hasPersistedWorkspace)

        await shell.closeWorkspace()
        guard case .welcome = shell.phase else {
            Issue.record("Expected the welcome screen after close")
            return
        }
        #expect(accessManager.releaseCount == 1)

        await shell.reopenLastWorkspace()
        guard case let .workspace(reopenedSession) = shell.phase else {
            Issue.record("Expected the last workspace to reopen")
            return
        }
        #expect(reopenedSession.workspace.id == createdID)

        await shell.closeWorkspace()
    }

    @Test("A corrupt workspace opens in recovery and can restore a backup")
    func recoveryFlow() async throws {
        let rootURL = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let accessManager = TestWorkspaceAccessManager()
        let environment = AppEnvironment()
        try await environment.start()
        let shell = WorkspaceShellModel(accessManager: accessManager)
        await shell.start(commandBus: environment.commandBus)

        await shell.createWorkspace(name: "Recovery Test", at: rootURL)
        guard case let .workspace(session) = shell.phase else {
            Issue.record("Expected the created workspace to be open")
            return
        }
        let workspaceID = session.workspace.id
        let backup = try await environment.workspaceService.createBackup(
            workspaceID: workspaceID
        )
        await shell.closeWorkspace()

        try Data("not a sqlite database".utf8).write(
            to: rootURL.appending(path: ".verso/workspace.sqlite")
        )
        await shell.reopenLastWorkspace()

        guard case let .recovery(context) = shell.phase else {
            Issue.record("Expected read-only recovery mode")
            return
        }
        let backupName = URL(filePath: backup.rawValue).lastPathComponent
        #expect(
            context.backupLocations.contains {
                URL(filePath: $0.rawValue).lastPathComponent == backupName
            }
        )

        await shell.restoreWorkspace(from: backup)
        guard case let .workspace(restoredSession) = shell.phase else {
            Issue.record("Expected the restored workspace to open")
            return
        }
        #expect(restoredSession.workspace.id == workspaceID)

        await shell.closeWorkspace()
    }

    @Test("Forgetting a workspace clears access without deleting its files")
    func forgetWorkspaceKeepsFiles() async throws {
        let rootURL = temporaryWorkspaceURL()
        let userFileURL = rootURL.appending(path: "Keep Me.md")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        try Data("# Keep me".utf8).write(to: userFileURL)

        let accessManager = TestWorkspaceAccessManager()
        let environment = AppEnvironment()
        try await environment.start()
        let shell = WorkspaceShellModel(accessManager: accessManager)
        await shell.start(commandBus: environment.commandBus)

        await shell.createWorkspace(name: "Forget Test", at: rootURL)
        #expect(accessManager.hasPersistedWorkspace)

        await shell.forgetWorkspace()

        guard case .welcome = shell.phase else {
            Issue.record("Expected the welcome screen after forgetting")
            return
        }
        #expect(!accessManager.hasPersistedWorkspace)
        #expect(FileManager.default.fileExists(atPath: userFileURL.path))
        #expect(
            FileManager.default.fileExists(
                atPath: rootURL.appending(path: ".verso/workspace.sqlite").path
            )
        )
    }

    @Test("Moving a workspace to Trash clears access after requesting the whole root")
    func moveWorkspaceToTrash() async throws {
        let rootURL = temporaryWorkspaceURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let accessManager = TestWorkspaceAccessManager()
        let trashManager = TestWorkspaceTrashManager()
        let environment = AppEnvironment()
        try await environment.start()
        let shell = WorkspaceShellModel(
            accessManager: accessManager,
            trashManager: trashManager
        )
        await shell.start(commandBus: environment.commandBus)

        await shell.createWorkspace(name: "Trash Test", at: rootURL)
        await shell.moveWorkspaceToTrash()

        guard case .welcome = shell.phase else {
            Issue.record("Expected the welcome screen after moving to Trash")
            return
        }
        #expect(trashManager.requestedURL?.standardizedFileURL == rootURL.standardizedFileURL)
        #expect(!accessManager.hasPersistedWorkspace)
        #expect(accessManager.releaseCount == 1)
    }

    private func temporaryWorkspaceURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "VersoAppShellTests-\(UUID().uuidString)")
    }
}

@MainActor
private final class TestWorkspaceAccessManager: WorkspaceAccessManaging {
    private(set) var persistedURL: URL?
    private var activeURL: URL?
    private(set) var releaseCount = 0

    var hasPersistedWorkspace: Bool {
        persistedURL != nil
    }

    func beginAccess(to url: URL) throws -> URL {
        activeURL = url
        return url
    }

    func persistActiveAccess() throws {
        persistedURL = activeURL
    }

    func restoreLastAccess() throws -> URL? {
        activeURL = persistedURL
        return persistedURL
    }

    func releaseActiveAccess() {
        if activeURL != nil {
            releaseCount += 1
        }
        activeURL = nil
    }

    func clearPersistedAccess() {
        persistedURL = nil
    }
}

@MainActor
private final class TestWorkspaceTrashManager: WorkspaceTrashManaging {
    private(set) var requestedURL: URL?

    func moveToTrash(_ url: URL) throws {
        requestedURL = url
    }
}
