import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VersoApplication
import VersoDomain

struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var shell = WorkspaceShellModel()

    @State private var isShowingCreateSheet = false
    @State private var isChoosingCreateLocation = false
    @State private var isChoosingExistingWorkspace = false
    @State private var proposedWorkspaceName = ""

    var body: some View {
        Group {
            switch shell.phase {
            case .launching:
                WorkspaceProgressView(message: "正在启动 Verso…")
            case .welcome:
                WorkspaceWelcomeView(
                    hasRecentWorkspace: shell.hasRecentWorkspace,
                    createWorkspace: beginCreatingWorkspace,
                    openWorkspace: { isChoosingExistingWorkspace = true },
                    reopenWorkspace: { Task { await shell.reopenLastWorkspace() } },
                    forgetRecentWorkspace: {
                        Task { await shell.forgetWorkspace() }
                    }
                )
            case let .working(message):
                WorkspaceProgressView(message: message)
            case let .workspace(session):
                WorkspaceContentView(
                    session: session,
                    createWorkspace: beginCreatingWorkspace,
                    switchWorkspace: { isChoosingExistingWorkspace = true },
                    closeWorkspace: {
                        Task { _ = await shell.closeWorkspace() }
                    },
                    forgetWorkspace: { Task { await shell.forgetWorkspace() } },
                    moveWorkspaceToTrash: {
                        Task { await shell.moveWorkspaceToTrash() }
                    },
                    createMarkdown: { name in
                        await shell.createMarkdownDocument(named: name)
                    },
                    importFiles: { urls in
                        await shell.importFiles(from: urls)
                    },
                    readText: { url in
                        await shell.readTextDocument(at: url)
                    },
                    saveText: { contents, url in
                        await shell.saveTextDocument(contents, at: url)
                    }
                )
                .id(session.workspace.id.rawValue)
            case let .recovery(context):
                WorkspaceRecoveryView(
                    context: context,
                    createWorkspace: beginCreatingWorkspace,
                    switchWorkspace: { isChoosingExistingWorkspace = true },
                    closeWorkspace: {
                        Task { _ = await shell.closeWorkspace() }
                    },
                    forgetWorkspace: { Task { await shell.forgetWorkspace() } },
                    moveWorkspaceToTrash: {
                        Task { await shell.moveWorkspaceToTrash() }
                    },
                    restoreWorkspace: { backup in
                        Task { await shell.restoreWorkspace(from: backup) }
                    }
                )
                .id(context.location.rawValue)
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .task {
            do {
                try await environment.start()
                await shell.start(commandBus: environment.commandBus)
            } catch {
                shell.failStartup(with: error)
            }
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            CreateWorkspaceSheet(
                name: $proposedWorkspaceName,
                cancel: { isShowingCreateSheet = false },
                chooseLocation: chooseCreateLocation
            )
        }
        .fileImporter(
            isPresented: $isChoosingCreateLocation,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else {
                if case let .failure(error) = result {
                    shell.errorMessage = "无法选择 Workspace 位置：\(error.localizedDescription)"
                }
                return
            }
            let name = proposedWorkspaceName
            Task {
                guard await shell.closeWorkspace() else { return }
                await shell.createWorkspace(name: name, at: url)
            }
        }
        .fileImporter(
            isPresented: $isChoosingExistingWorkspace,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else {
                if case let .failure(error) = result {
                    shell.errorMessage = "无法选择 Workspace：\(error.localizedDescription)"
                }
                return
            }
            Task {
                guard await shell.closeWorkspace() else { return }
                await shell.openWorkspace(at: url)
            }
        }
        .alert(
            "Workspace 操作失败",
            isPresented: Binding(
                get: { shell.errorMessage != nil },
                set: { if !$0 { shell.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {
                shell.errorMessage = nil
            }
        } message: {
            Text(shell.errorMessage ?? "发生未知错误。")
        }
    }

    private func beginCreatingWorkspace() {
        proposedWorkspaceName = "新 Workspace"
        isShowingCreateSheet = true
    }

    private func chooseCreateLocation() {
        isShowingCreateSheet = false
        Task { @MainActor in
            await Task.yield()
            isChoosingCreateLocation = true
        }
    }
}

private struct WorkspaceWelcomeView: View {
    let hasRecentWorkspace: Bool
    let createWorkspace: () -> Void
    let openWorkspace: () -> Void
    let reopenWorkspace: () -> Void
    let forgetRecentWorkspace: () -> Void

    var body: some View {
        VStack(spacing: 26) {
            Spacer()

            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Verso")
                    .font(.largeTitle.weight(.semibold))
                Text("创建一个本地 Workspace，或继续已有工作。")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button(action: createWorkspace) {
                    Label("创建 Workspace", systemImage: "plus.square.on.square")
                        .frame(width: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("workspace.create")

                Button(action: openWorkspace) {
                    Label("打开已有 Workspace", systemImage: "folder")
                        .frame(width: 220)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)
                .accessibilityIdentifier("workspace.open")

                if hasRecentWorkspace {
                    Button("重新打开上次的 Workspace", action: reopenWorkspace)
                        .buttonStyle(.link)
                        .accessibilityIdentifier("workspace.reopen")
                    Button("忘记最近的 Workspace", action: forgetRecentWorkspace)
                        .buttonStyle(.link)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("workspace.forget-recent")
                }
            }

            Text("所选文件夹本身会成为 Workspace；Verso 的内部数据保存在隐藏的 .verso 文件夹中。")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Verso")
        .accessibilityIdentifier("workspace.welcome")
    }
}

private struct CreateWorkspaceSheet: View {
    @Binding var name: String
    let cancel: () -> Void
    let chooseLocation: () -> Void

    @FocusState private var isNameFocused: Bool

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("创建 Workspace")
                    .font(.title2.weight(.semibold))
                Text("输入显示名称，然后选择要直接作为 Workspace 使用的文件夹。")
                    .foregroundStyle(.secondary)
            }

            TextField("Workspace 名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit {
                    if !normalizedName.isEmpty {
                        chooseLocation()
                    }
                }

            Text("不会创建同名子文件夹；原有文件会直接显示在 Workspace 中。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button("取消", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("选择位置并创建", action: chooseLocation)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(normalizedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 430)
        .onAppear { isNameFocused = true }
    }
}

private struct WorkspaceProgressView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("workspace.progress")
    }
}

private struct WorkspaceContentView: View {
    let session: OpenWorkspaceSession
    let createWorkspace: () -> Void
    let switchWorkspace: () -> Void
    let closeWorkspace: () -> Void
    let forgetWorkspace: () -> Void
    let moveWorkspaceToTrash: () -> Void
    let createMarkdown: (String) async -> URL?
    let importFiles: ([URL]) async -> [URL]
    let readText: (URL) async -> String?
    let saveText: (String, URL) async -> Bool

    @StateObject private var browser = FileBrowserModel()
    @State private var isShowingNewMarkdownSheet = false
    @State private var isImportingFiles = false
    @State private var newMarkdownName = "未命名"
    @State private var isConfirmingForget = false
    @State private var isConfirmingTrash = false

    var body: some View {
        NavigationSplitView {
            FileSidebar(browser: browser, chooseFolder: nil)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
        } detail: {
            WorkspaceDetailPane(
                node: browser.selectedNode,
                readText: readText,
                saveText: saveText
            )
        }
        .navigationTitle(session.workspace.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("新建 Workspace", systemImage: "plus.rectangle.on.folder") {
                    createWorkspace()
                }
                .help("创建并切换到另一个 Workspace")
                .accessibilityIdentifier("workspace.create-another")

                Button("切换 Workspace", systemImage: "folder.badge.plus") {
                    switchWorkspace()
                }
                .help("打开并切换到已有 Workspace")
                .accessibilityIdentifier("workspace.switch")

                Button("新建 Markdown", systemImage: "square.and.pencil") {
                    newMarkdownName = "未命名"
                    isShowingNewMarkdownSheet = true
                }
                .help("在 Workspace 中新建 Markdown")
                .accessibilityIdentifier("workspace.document.new")

                Button("导入文件或文件夹", systemImage: "square.and.arrow.down") {
                    isImportingFiles = true
                }
                .help("递归复制文件或文件夹到 Workspace")
                .accessibilityIdentifier("workspace.document.import")

                Button("重新载入", systemImage: "arrow.clockwise") {
                    browser.reload()
                }
                .disabled(browser.isLoading)
                .help("重新载入 Workspace 文件")

                Menu {
                    Button("关闭 Workspace", action: closeWorkspace)
                    Button("忘记 Workspace…") {
                        isConfirmingForget = true
                    }
                    Divider()
                    Button("移到废纸篓…", role: .destructive) {
                        isConfirmingTrash = true
                    }
                } label: {
                    Label("Workspace 操作", systemImage: "ellipsis.circle")
                }
                .help("关闭、忘记或删除 Workspace")
            }
        }
        .task(id: session.contentURL) {
            browser.open(session.contentURL, managesSecurityScope: false)
        }
        .browserErrorAlert(browser: browser)
        .sheet(isPresented: $isShowingNewMarkdownSheet) {
            NewMarkdownSheet(
                name: $newMarkdownName,
                cancel: { isShowingNewMarkdownSheet = false },
                create: createNewMarkdown
            )
        }
        .fileImporter(
            isPresented: $isImportingFiles,
            allowedContentTypes: [.folder, .item],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            Task {
                let imported = await importFiles(urls)
                browser.reload(
                    selecting: imported.first?.standardizedFileURL.path
                )
            }
        }
        .confirmationDialog(
            "忘记这个 Workspace？",
            isPresented: $isConfirmingForget
        ) {
            Button("忘记 Workspace") { forgetWorkspace() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Verso 会移除访问书签，但不会删除文件夹或其中的任何文件。")
        }
        .confirmationDialog(
            "将整个 Workspace 文件夹移到废纸篓？",
            isPresented: $isConfirmingTrash
        ) {
            Button("移到废纸篓", role: .destructive) {
                moveWorkspaceToTrash()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会移动整个“\(session.rootURL.lastPathComponent)”文件夹，包括其中原有的所有文件。可从废纸篓恢复。")
        }
        .accessibilityIdentifier("workspace.content")
    }

    private func createNewMarkdown() {
        let name = newMarkdownName
        isShowingNewMarkdownSheet = false
        Task {
            if let url = await createMarkdown(name) {
                browser.reload(selecting: url.standardizedFileURL.path)
            }
        }
    }
}

private struct NewMarkdownSheet: View {
    @Binding var name: String
    let cancel: () -> Void
    let create: () -> Void

    @FocusState private var isFocused: Bool

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("新建 Markdown")
                    .font(.title2.weight(.semibold))
                Text("文档会直接保存在 Workspace 文件夹中。")
                    .foregroundStyle(.secondary)
            }

            TextField("文件名", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    if !normalizedName.isEmpty { create() }
                }

            HStack {
                Button("取消", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("创建", action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(normalizedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear { isFocused = true }
    }
}

private struct WorkspaceDetailPane: View {
    let node: FileTreeNode?
    let readText: (URL) async -> String?
    let saveText: (String, URL) async -> Bool

    var body: some View {
        if let node, node.kind == .file, isMarkdown(node.url) {
            MarkdownEditorPane(
                node: node,
                readText: readText,
                saveText: saveText
            )
            .id(node.id)
        } else {
            PreviewPane(node: node)
        }
    }

    private func isMarkdown(_ url: URL) -> Bool {
        ["md", "markdown"].contains(url.pathExtension.lowercased())
    }
}

private struct MarkdownEditorPane: View {
    let node: FileTreeNode
    let readText: (URL) async -> String?
    let saveText: (String, URL) async -> Bool

    @State private var contents = ""
    @State private var savedContents = ""
    @State private var isLoading = true
    @State private var isSaving = false

    private var hasUnsavedChanges: Bool {
        contents != savedContents
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(node.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if hasUnsavedChanges {
                    Circle()
                        .fill(.orange)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel("有未保存的更改")
                }
                Spacer()
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("保存", systemImage: "square.and.arrow.down") {
                    save()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(isLoading || isSaving || !hasUnsavedChanges)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.bar)

            Divider()

            if isLoading {
                ProgressView("正在读取文档…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $contents)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))
                    .accessibilityIdentifier("workspace.markdown.editor")
            }
        }
        .task(id: node.id) {
            isLoading = true
            if let loaded = await readText(node.url) {
                contents = loaded
                savedContents = loaded
            }
            isLoading = false
        }
    }

    private func save() {
        let value = contents
        isSaving = true
        Task {
            if await saveText(value, node.url) {
                savedContents = value
            }
            isSaving = false
        }
    }
}

private struct WorkspaceRecoveryView: View {
    let context: RecoveryContext
    let createWorkspace: () -> Void
    let switchWorkspace: () -> Void
    let closeWorkspace: () -> Void
    let forgetWorkspace: () -> Void
    let moveWorkspaceToTrash: () -> Void
    let restoreWorkspace: (WorkspaceLocation) -> Void

    @StateObject private var browser = FileBrowserModel()
    @State private var pendingBackup: WorkspaceLocation?
    @State private var isConfirmingForget = false
    @State private var isConfirmingTrash = false

    private var contentURL: URL {
        let rootURL = URL(filePath: context.location.rawValue)
        let hiddenDatabase = rootURL
            .appending(path: ".verso", directoryHint: .isDirectory)
            .appending(path: "workspace.sqlite")
        if FileManager.default.fileExists(atPath: hiddenDatabase.path) {
            return rootURL
        }
        return rootURL.appending(path: "Documents", directoryHint: .isDirectory)
    }

    var body: some View {
        NavigationSplitView {
            FileSidebar(browser: browser, chooseFolder: nil)
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 360)
        } content: {
            PreviewPane(node: browser.selectedNode)
                .navigationSplitViewColumnWidth(min: 360, ideal: 560)
        } detail: {
            RecoveryInspector(
                context: context,
                chooseBackup: { pendingBackup = $0 }
            )
            .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 440)
        }
        .navigationTitle("Workspace 恢复")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Label("只读", systemImage: "lock.fill")
                    .foregroundStyle(.orange)
                    .help("数据库未以可写会话打开")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("新建 Workspace…", action: createWorkspace)
                    Button("打开并切换 Workspace…", action: switchWorkspace)
                    Divider()
                    Button("关闭 Workspace", action: closeWorkspace)
                    Button("忘记 Workspace…") {
                        isConfirmingForget = true
                    }
                    Divider()
                    Button("移到废纸篓…", role: .destructive) {
                        isConfirmingTrash = true
                    }
                } label: {
                    Label("Workspace 操作", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("workspace.recovery.close")
            }
        }
        .task(id: contentURL) {
            browser.open(contentURL, managesSecurityScope: false)
        }
        .browserErrorAlert(browser: browser)
        .confirmationDialog(
            "从所选备份恢复 Workspace？",
            isPresented: Binding(
                get: { pendingBackup != nil },
                set: { if !$0 { pendingBackup = nil } }
            )
        ) {
            Button("恢复 Workspace") {
                guard let pendingBackup else { return }
                self.pendingBackup = nil
                restoreWorkspace(pendingBackup)
            }
            Button("取消", role: .cancel) {
                pendingBackup = nil
            }
        } message: {
            Text("Verso 会保留损坏的数据库副本，并用所选备份替换当前数据库。")
        }
        .confirmationDialog(
            "忘记这个 Workspace？",
            isPresented: $isConfirmingForget
        ) {
            Button("忘记 Workspace") { forgetWorkspace() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("文件不会被删除；Verso 只会移除访问书签。")
        }
        .confirmationDialog(
            "将整个 Workspace 文件夹移到废纸篓？",
            isPresented: $isConfirmingTrash
        ) {
            Button("移到废纸篓", role: .destructive) {
                moveWorkspaceToTrash()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会移动整个文件夹及其中所有文件。可从废纸篓恢复。")
        }
        .accessibilityIdentifier("workspace.recovery")
    }
}

private struct RecoveryInspector: View {
    let context: RecoveryContext
    let chooseBackup: (WorkspaceLocation) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label {
                    Text("只读恢复模式")
                        .font(.title2.weight(.semibold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                Text("Workspace 数据库未通过完整性检查。Verso 已停止写入；你仍可只读浏览工作文件。")
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("可用备份")
                        .font(.headline)

                    if context.backupLocations.isEmpty {
                        ContentUnavailableView(
                            "没有可用备份",
                            systemImage: "externaldrive.badge.xmark",
                            description: Text("原始文件仍保持只读，请先复制重要文件后再处理此 Workspace。")
                        )
                    } else {
                        ForEach(context.backupLocations, id: \.self) { backup in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(URL(filePath: backup.rawValue).lastPathComponent)
                                    .font(.body.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button("从此备份恢复") {
                                    chooseBackup(backup)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                DisclosureGroup("技术详情") {
                    Text(context.reason)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }

                Button("在 Finder 中显示 Workspace") {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        URL(filePath: context.location.rawValue)
                    ])
                }
                .buttonStyle(.link)
            }
            .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private extension View {
    func browserErrorAlert(browser: FileBrowserModel) -> some View {
        alert(
            "无法读取 Workspace 文件",
            isPresented: Binding(
                get: { browser.errorMessage != nil },
                set: { if !$0 { browser.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {
                browser.errorMessage = nil
            }
        } message: {
            Text(browser.errorMessage ?? "发生未知错误。")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppEnvironment())
}
