//
//  FileTreeNode.swift
//  Verso
//

import Foundation

nonisolated struct FileTreeNode: Identifiable, Hashable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        case directory
        case file
        case package
        case symbolicLink
    }

    let id: String
    let url: URL
    let name: String
    let kind: Kind
    let children: [FileTreeNode]?

    var isPreviewable: Bool {
        kind != .directory
    }

    init(url: URL, name: String, kind: Kind, children: [FileTreeNode]?) {
        self.id = url.standardizedFileURL.path
        self.url = url
        self.name = name
        self.kind = kind
        self.children = children
    }

    func node(withID id: String) -> FileTreeNode? {
        if self.id == id {
            return self
        }

        for child in children ?? [] {
            if let match = child.node(withID: id) {
                return match
            }
        }

        return nil
    }
}
