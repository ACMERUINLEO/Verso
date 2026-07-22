import Combine
import Foundation
import VersoApplication
import VersoDomain

@MainActor
protocol WorkspaceTrashManaging {
    func moveToTrash(_ url: URL) throws
}

@MainActor
struct SystemWorkspaceTrashManager: WorkspaceTrashManaging {
    func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

struct OpenWorkspaceSession: Sendable {
    let workspace: Workspace
    let rootURL: URL

    var contentURL: URL {
        let hiddenDatabase = rootURL
            .appending(path: ".verso", directoryHint: .isDirectory)
            .appending(path: "workspace.sqlite")
        if FileManager.default.fileExists(atPath: hiddenDatabase.path) {
            return rootURL
        }
        return rootURL.appending(path: "Documents", directoryHint: .isDirectory)
    }
}

@MainActor
final class WorkspaceShellModel: ObservableObject {
    enum Phase {
        case launching
        case welcome
        case working(String)
        case workspace(OpenWorkspaceSession)
        case recovery(RecoveryContext)
    }

    @Published private(set) var phase: Phase = .launching
    @Published var errorMessage: String?

    private let accessManager: any WorkspaceAccessManaging
    private let trashManager: any WorkspaceTrashManaging
    private var commandBus: CommandBus?
    private var activeRootURL: URL?
    private var hasStarted = false

    init(
        accessManager: any WorkspaceAccessManaging = SecurityScopedBookmarkStore(),
        trashManager: any WorkspaceTrashManaging = SystemWorkspaceTrashManager()
    ) {
        self.accessManager = accessManager
        self.trashManager = trashManager
    }

    var hasRecentWorkspace: Bool {
        accessManager.hasPersistedWorkspace
    }

    func start(commandBus: CommandBus) async {
        guard !hasStarted else { return }
        hasStarted = true
        self.commandBus = commandBus

        do {
            guard let url = try accessManager.restoreLastAccess() else {
                phase = .welcome
                return
            }
            activeRootURL = url
            await openResolvedWorkspace(at: url, activity: "正在重新打开 Workspace…")
        } catch {
            accessManager.releaseActiveAccess()
            accessManager.clearPersistedAccess()
            activeRootURL = nil
            phase = .welcome
            errorMessage = "上次 Workspace 的访问授权已失效，请重新选择文件夹。\n\(error.localizedDescription)"
        }
    }

    func failStartup(with error: Error) {
        phase = .welcome
        errorMessage = "Verso 启动失败：\(error.localizedDescription)"
    }

    func createWorkspace(name: String, at selectedURL: URL) async {
        guard let commandBus else {
            errorMessage = "Workspace 服务尚未准备好。"
            return
        }

        phase = .working("正在创建 Workspace…")
        do {
            let url = try accessManager.beginAccess(to: selectedURL)
            activeRootURL = url
            let location = WorkspaceLocation(rawValue: url.standardizedFileURL.path)
            let workspace = try await commandBus.send(
                CreateWorkspace(name: name, location: location)
            )
            persistAccessWithoutClosingWorkspace()
            phase = .workspace(OpenWorkspaceSession(workspace: workspace, rootURL: url))
        } catch {
            accessManager.releaseActiveAccess()
            activeRootURL = nil
            phase = .welcome
            errorMessage = "无法创建 Workspace：\(error.localizedDescription)"
        }
    }

    func openWorkspace(at selectedURL: URL) async {
        phase = .working("正在打开 Workspace…")
        do {
            let url = try accessManager.beginAccess(to: selectedURL)
            activeRootURL = url
            await openResolvedWorkspace(at: url, activity: "正在打开 Workspace…")
        } catch {
            accessManager.releaseActiveAccess()
            activeRootURL = nil
            phase = .welcome
            errorMessage = "无法取得 Workspace 的访问权限：\(error.localizedDescription)"
        }
    }

    @discardableResult
    func closeWorkspace() async -> Bool {
        guard let commandBus else { return false }

        let previousPhase = phase
        phase = .working("正在关闭 Workspace…")

        do {
            if case let .workspace(session) = previousPhase {
                _ = try await commandBus.send(
                    CloseWorkspace(workspaceID: session.workspace.id)
                )
            }
            accessManager.releaseActiveAccess()
            activeRootURL = nil
            phase = .welcome
            return true
        } catch {
            phase = previousPhase
            errorMessage = "无法关闭 Workspace：\(error.localizedDescription)"
            return false
        }
    }

    func forgetWorkspace() async {
        guard let commandBus else { return }

        let previousPhase = phase
        phase = .working("正在忘记 Workspace…")
        do {
            if case let .workspace(session) = previousPhase {
                _ = try await commandBus.send(
                    CloseWorkspace(workspaceID: session.workspace.id)
                )
            }
            accessManager.releaseActiveAccess()
            accessManager.clearPersistedAccess()
            activeRootURL = nil
            phase = .welcome
        } catch {
            phase = previousPhase
            errorMessage = "无法忘记 Workspace：\(error.localizedDescription)"
        }
    }

    func moveWorkspaceToTrash() async {
        guard
            let commandBus,
            let activeRootURL
        else {
            return
        }

        let previousPhase = phase
        phase = .working("正在将 Workspace 移到废纸篓…")
        do {
            if case let .workspace(session) = previousPhase {
                _ = try await commandBus.send(
                    CloseWorkspace(workspaceID: session.workspace.id)
                )
            }
            try trashManager.moveToTrash(activeRootURL)
            accessManager.releaseActiveAccess()
            accessManager.clearPersistedAccess()
            self.activeRootURL = nil
            phase = .welcome
        } catch {
            if case .workspace = previousPhase {
                await openResolvedWorkspace(
                    at: activeRootURL,
                    activity: "正在重新打开 Workspace…"
                )
            } else {
                phase = previousPhase
            }
            errorMessage = "无法将 Workspace 移到废纸篓：\(error.localizedDescription)"
        }
    }

    func reopenLastWorkspace() async {
        guard commandBus != nil else { return }
        phase = .working("正在重新打开 Workspace…")

        do {
            guard let url = try accessManager.restoreLastAccess() else {
                phase = .welcome
                return
            }
            activeRootURL = url
            await openResolvedWorkspace(at: url, activity: "正在重新打开 Workspace…")
        } catch {
            accessManager.releaseActiveAccess()
            accessManager.clearPersistedAccess()
            activeRootURL = nil
            phase = .welcome
            errorMessage = "无法重新打开上次的 Workspace，请重新选择。\n\(error.localizedDescription)"
        }
    }

    func restoreWorkspace(from backupLocation: WorkspaceLocation) async {
        guard
            let commandBus,
            let activeRootURL,
            case let .recovery(context) = phase
        else {
            return
        }

        let recoveryPhase = phase
        phase = .working("正在从备份恢复 Workspace…")
        do {
            let outcome = try await commandBus.send(
                RestoreWorkspace(
                    location: context.location,
                    backupLocation: backupLocation
                )
            )
            apply(outcome, rootURL: activeRootURL)
        } catch {
            phase = recoveryPhase
            errorMessage = "无法恢复 Workspace：\(error.localizedDescription)"
        }
    }

    func createMarkdownDocument(named name: String) async -> URL? {
        guard
            let commandBus,
            case let .workspace(session) = phase
        else {
            return nil
        }
        do {
            let location = try await commandBus.send(
                CreateMarkdownDocument(
                    workspaceLocation: WorkspaceLocation(
                        rawValue: session.rootURL.standardizedFileURL.path
                    ),
                    preferredName: name
                )
            )
            return URL(filePath: location.rawValue)
        } catch {
            errorMessage = "无法新建 Markdown：\(error.localizedDescription)"
            return nil
        }
    }

    func importFiles(from sourceURLs: [URL]) async -> [URL] {
        guard
            let commandBus,
            case let .workspace(session) = phase
        else {
            return []
        }

        let accessingURLs = sourceURLs.filter {
            $0.startAccessingSecurityScopedResource()
        }
        defer {
            for url in accessingURLs {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let locations = try await commandBus.send(
                ImportWorkspaceFiles(
                    workspaceLocation: WorkspaceLocation(
                        rawValue: session.rootURL.standardizedFileURL.path
                    ),
                    sourceLocations: sourceURLs.map {
                        WorkspaceLocation(rawValue: $0.standardizedFileURL.path)
                    }
                )
            )
            return locations.map { URL(filePath: $0.rawValue) }
        } catch {
            errorMessage = "无法导入文件：\(error.localizedDescription)"
            return []
        }
    }

    func readTextDocument(at url: URL) async -> String? {
        guard
            let commandBus,
            case let .workspace(session) = phase
        else {
            return nil
        }
        do {
            return try await commandBus.send(
                ReadWorkspaceTextDocument(
                    workspaceLocation: WorkspaceLocation(
                        rawValue: session.rootURL.standardizedFileURL.path
                    ),
                    documentLocation: WorkspaceLocation(
                        rawValue: url.standardizedFileURL.path
                    )
                )
            )
        } catch {
            errorMessage = "无法读取文档：\(error.localizedDescription)"
            return nil
        }
    }

    func saveTextDocument(_ contents: String, at url: URL) async -> Bool {
        guard
            let commandBus,
            case let .workspace(session) = phase
        else {
            return false
        }
        do {
            _ = try await commandBus.send(
                SaveWorkspaceTextDocument(
                    workspaceLocation: WorkspaceLocation(
                        rawValue: session.rootURL.standardizedFileURL.path
                    ),
                    documentLocation: WorkspaceLocation(
                        rawValue: url.standardizedFileURL.path
                    ),
                    contents: contents
                )
            )
            return true
        } catch {
            errorMessage = "无法保存文档：\(error.localizedDescription)"
            return false
        }
    }

    private func openResolvedWorkspace(at url: URL, activity: String) async {
        guard let commandBus else {
            phase = .welcome
            errorMessage = "Workspace 服务尚未准备好。"
            return
        }

        phase = .working(activity)
        do {
            let location = WorkspaceLocation(rawValue: url.standardizedFileURL.path)
            let outcome = try await commandBus.send(OpenWorkspace(location: location))
            persistAccessWithoutClosingWorkspace()
            apply(outcome, rootURL: url)
        } catch {
            accessManager.releaseActiveAccess()
            activeRootURL = nil
            phase = .welcome
            errorMessage = "无法打开 Workspace：\(error.localizedDescription)"
        }
    }

    private func apply(_ outcome: WorkspaceOpenOutcome, rootURL: URL) {
        switch outcome {
        case let .ready(workspace):
            phase = .workspace(
                OpenWorkspaceSession(workspace: workspace, rootURL: rootURL)
            )
        case let .recoveryRequired(context):
            phase = .recovery(context)
        }
    }

    private func persistAccessWithoutClosingWorkspace() {
        do {
            try accessManager.persistActiveAccess()
        } catch {
            errorMessage = "Workspace 已打开，但无法保存下次启动所需的访问授权。\n\(error.localizedDescription)"
        }
    }
}
