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
    private static let frameAutosaveName = "ChronicleQuickMarkerPanel"
    private static let minimumPanelSize = NSSize(width: 700, height: 500)
    private var hasPreparedInitialFrame = false

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.minSize = Self.minimumPanelSize
        panel.setFrameAutosaveName(Self.frameAutosaveName)
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

    @available(*, unavailable, message: "Use QuickMarkerPanelController.shared instead.")
    required init?(coder: NSCoder) {
        return nil
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
        preparePanelFrameIfNeeded(for: window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closePanel() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window?.orderOut(nil)
    }

    private func preparePanelFrameIfNeeded(for window: NSWindow) {
        window.minSize = Self.minimumPanelSize
        guard !hasPreparedInitialFrame else { return }
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            adjustPanelSize(for: window)
            window.center()
        }
        hasPreparedInitialFrame = true
    }

    private func adjustPanelSize(for window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let targetWidth = max(800, min(screen.visibleFrame.width * 0.56, 980))
        let targetHeight = max(500, min(max(560, screen.visibleFrame.height * 0.58), screen.visibleFrame.height - 80))
        let targetSize = NSSize(width: targetWidth, height: targetHeight)
        if window.frame.size != targetSize {
            window.setContentSize(targetSize)
        }
    }
}
