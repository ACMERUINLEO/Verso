//
//  PreviewPane.swift
//  Verso
//

import SwiftUI

struct PreviewPane: View {
    let node: FileTreeNode?

    var body: some View {
        Group {
            if let node, node.isPreviewable {
                QuickLookPreview(url: node.url)
                    .id(node.id)
            } else if node?.kind == .directory {
                ContentUnavailableView(
                    "选择一个文件",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("文件夹可在左侧展开；选择文件后将在这里使用 Quick Look 预览。")
                )
            } else {
                ContentUnavailableView(
                    "预览区",
                    systemImage: "eye",
                    description: Text("从左侧文件树选择图片、PDF、音视频或文档。")
                )
                .accessibilityIdentifier("preview.empty")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("preview.pane")
    }
}
