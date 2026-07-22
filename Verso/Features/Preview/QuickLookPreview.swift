//
//  QuickLookPreview.swift
//  Verso
//

import QuickLookUI
import SwiftUI

struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> QLPreviewView {
        let previewView = QLPreviewView(frame: .zero, style: .normal)
        previewView?.autostarts = false
        previewView?.shouldCloseWithWindow = true
        update(previewView, coordinator: context.coordinator)
        return previewView!
    }

    func updateNSView(_ previewView: QLPreviewView, context: Context) {
        update(previewView, coordinator: context.coordinator)
    }

    private func update(_ previewView: QLPreviewView?, coordinator: Coordinator) {
        guard coordinator.url != url else {
            return
        }

        coordinator.url = url
        previewView?.previewItem = url as NSURL
    }

    final class Coordinator {
        var url: URL?
    }
}
