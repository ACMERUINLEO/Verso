//
//  FileBrowserModel.swift
//  Verso
//

import Combine
import Foundation

@MainActor
final class FileBrowserModel: ObservableObject {
    @Published private(set) var root: FileTreeNode?
    @Published var selectedNodeID: String?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var rootURL: URL?
    private var isAccessingSecurityScopedResource = false
    private var loadingTask: Task<Void, Never>?

    var selectedNode: FileTreeNode? {
        guard let selectedNodeID else {
            return nil
        }
        return root?.node(withID: selectedNodeID)
    }

    func open(_ url: URL, managesSecurityScope: Bool = true) {
        loadingTask?.cancel()
        releaseSecurityScopedResource()

        root = nil
        selectedNodeID = nil
        rootURL = url
        isAccessingSecurityScopedResource = managesSecurityScope
            ? url.startAccessingSecurityScopedResource()
            : false
        loadRoot(selecting: nil)
    }

    func reload(selecting nodeID: String? = nil) {
        loadRoot(selecting: nodeID ?? selectedNodeID)
    }

    func present(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    private func loadRoot(selecting previousSelection: String?) {
        guard let rootURL else {
            return
        }

        loadingTask?.cancel()
        isLoading = true
        errorMessage = nil

        loadingTask = Task { [weak self] in
            do {
                let loadedRoot = try await FileTreeLoader.load(from: rootURL)
                try Task.checkCancellation()

                guard let self else {
                    return
                }

                root = loadedRoot
                selectedNodeID = previousSelection.flatMap { loadedRoot.node(withID: $0)?.id }
                isLoading = false
            } catch is CancellationError {
                // A newer folder or reload request superseded this one.
            } catch {
                guard let self else {
                    return
                }
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func releaseSecurityScopedResource() {
        if isAccessingSecurityScopedResource, let rootURL {
            rootURL.stopAccessingSecurityScopedResource()
        }
        isAccessingSecurityScopedResource = false
    }

    deinit {
        loadingTask?.cancel()
        if isAccessingSecurityScopedResource, let rootURL {
            rootURL.stopAccessingSecurityScopedResource()
        }
    }
}
