//
//  FileTreeLoader.swift
//  Verso
//

import Foundation

nonisolated enum FileTreeLoader {
    private static let maximumDepth = 32
    private static let maximumNodeCount = 10_000

    nonisolated static func load(from rootURL: URL) async throws -> FileTreeNode {
        try await Task.detached(priority: .userInitiated) {
            var remainingNodes = maximumNodeCount
            return try makeNode(
                at: rootURL.standardizedFileURL,
                depth: 0,
                remainingNodes: &remainingNodes
            )
        }.value
    }

    nonisolated private static func makeNode(
        at url: URL,
        depth: Int,
        remainingNodes: inout Int
    ) throws -> FileTreeNode {
        try Task.checkCancellation()

        guard remainingNodes > 0 else {
            throw FileTreeLoadingError.tooManyItems(limit: maximumNodeCount)
        }
        remainingNodes -= 1

        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .nameKey,
        ])
        let name = values.name ?? url.lastPathComponent

        if values.isSymbolicLink == true {
            return FileTreeNode(url: url, name: name, kind: .symbolicLink, children: nil)
        }

        if values.isPackage == true {
            return FileTreeNode(url: url, name: name, kind: .package, children: nil)
        }

        guard values.isDirectory == true else {
            return FileTreeNode(url: url, name: name, kind: .file, children: nil)
        }

        guard depth < maximumDepth else {
            throw FileTreeLoadingError.tooDeep(limit: maximumDepth)
        }

        let childURLs = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isPackageKey,
                .isSymbolicLinkKey,
                .nameKey,
            ],
            options: [.skipsHiddenFiles]
        )

        var children: [FileTreeNode] = []
        children.reserveCapacity(childURLs.count)

        for childURL in childURLs {
            let child = try makeNode(
                at: childURL,
                depth: depth + 1,
                remainingNodes: &remainingNodes
            )
            children.append(child)
        }

        children.sort { lhs, rhs in
            if lhs.kind == .directory, rhs.kind != .directory {
                return true
            }
            if lhs.kind != .directory, rhs.kind == .directory {
                return false
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        return FileTreeNode(url: url, name: name, kind: .directory, children: children)
    }
}

nonisolated enum FileTreeLoadingError: LocalizedError {
    case tooManyItems(limit: Int)
    case tooDeep(limit: Int)

    var errorDescription: String? {
        switch self {
        case let .tooManyItems(limit):
            "该文件夹超过本次框架测试的 \(limit) 个项目上限。请选择更小的文件夹。"
        case let .tooDeep(limit):
            "该文件夹超过本次框架测试的 \(limit) 层目录深度上限。"
        }
    }
}
