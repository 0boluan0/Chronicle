//
//  SystemFolderPicker.swift
//  Chronicle
//
//  Created by Codex on 2026/6/22.
//

import AppKit

@MainActor
enum SystemFolderPicker {
    static func chooseFolder(
        prompt: String,
        onCompletion: @MainActor @escaping (URL?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt

        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            if let window = presentingWindow(), window.attachedSheet == nil {
                panel.beginSheetModal(for: window) { response in
                    onCompletion(response == .OK ? panel.url : nil)
                }
                return
            }

            let response = panel.runModal()
            onCompletion(response == .OK ? panel.url : nil)
        }
    }

    private static func presentingWindow() -> NSWindow? {
        if let keyWindow = NSApp.keyWindow, keyWindow.isVisible, !(keyWindow is NSPanel) {
            return keyWindow
        }
        if let mainWindow = NSApp.mainWindow, mainWindow.isVisible, !(mainWindow is NSPanel) {
            return mainWindow
        }
        return NSApp.orderedWindows.first {
            $0.isVisible && !$0.isMiniaturized && !($0 is NSPanel)
        }
    }
}
