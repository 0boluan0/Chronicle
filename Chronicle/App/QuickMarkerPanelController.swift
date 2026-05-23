//
//  QuickMarkerPanelController.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/4.
//

import AppKit
import SwiftUI

final class QuickMarkerPanelController: NSWindowController, NSWindowDelegate {
    static let shared = QuickMarkerPanelController()

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.minSize = NSSize(width: 700, height: 500)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true

        let rootView = LocalizedRootView {
            QuickMarkerPanelView { [weak panel] in
                panel?.close()
            }
        }
        .environmentObject(AppState.shared)
        .environmentObject(AppLanguageManager.shared)

        panel.contentViewController = NSHostingController(rootView: rootView)

        super.init(window: panel)
        window?.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggle() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        guard let window else { return }
        adjustPanelSize(for: window)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closePanel() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window?.orderOut(nil)
    }

    private func adjustPanelSize(for window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let targetWidth = max(800, min(screen.visibleFrame.width * 0.56, 980))
        let targetHeight = max(500, min(max(560, screen.visibleFrame.height * 0.58), screen.visibleFrame.height - 80))
        let targetSize = NSSize(width: targetWidth, height: targetHeight)
        if window.frame.size != targetSize {
            window.setContentSize(targetSize)
        }
        window.minSize = targetSize
    }
}
