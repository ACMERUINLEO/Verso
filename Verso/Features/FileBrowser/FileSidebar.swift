//
//  FileSidebar.swift
//  Verso
//

import AppKit
import SwiftUI

struct FileSidebar: View {
    @ObservedObject var browser: FileBrowserModel
    let chooseFolder: (() -> Void)?

    var body: some View {
        Group {
            if browser.isLoading, browser.root == nil {
                loadingState
            } else if let root = browser.root {
                fileList(root: root)
            } else {
                emptyState
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("file-browser.sidebar")
    }

    private func fileList(root: FileTreeNode) -> some View {
        List(selection: $browser.selectedNodeID) {
            Section {
                if let children = root.children, children.isEmpty {
                    Text("空文件夹")
                        .foregroundStyle(.secondary)
                } else {
                    OutlineGroup(root.children ?? [], children: \.children) { node in
                        FileTreeRow(node: node)
                            .tag(node.id)
                            .contextMenu {
                                Button("在 Finder 中显示") {
                                    NSWorkspace.shared.activateFileViewerSelecting([node.url])
                                }
                            }
                    }
                }
            } header: {
                Label(root.name, systemImage: "folder.fill")
                    .lineLimit(1)
            }
        }
        .overlay(alignment: .center) {
            if browser.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在读取文件树…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("尚未打开文件夹", systemImage: "sidebar.left")
        } description: {
            Text("选择一个文件夹以测试原生文件树与 Quick Look 预览。")
        } actions: {
            if let chooseFolder {
                Button("打开文件夹", action: chooseFolder)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("file-browser.open-folder")
            }
        }
        .accessibilityIdentifier("file-browser.empty")
    }
}

private struct FileTreeRow: View {
    let node: FileTreeNode

    var body: some View {
        Label {
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        }
    }
}
