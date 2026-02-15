//
//  HotKeyManager.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/4.
//

import Carbon
import Foundation

final class HotKeyManager {
    static let shared = HotKeyManager()

    var onHotKeyPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handlerUPP: EventHandlerUPP?

    private init() {}

    func register() {
        unregister()

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onHotKeyPressed?()
            return noErr
        }
        handlerUPP = handler

        let target = GetApplicationEventTarget()
        let installStatus = InstallEventHandler(
            target,
            handler,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        if installStatus != noErr {
            AppLogger.log("HotKey install handler failed status=\(installStatus)", category: "ui")
        }

        var hotKeyID = EventHotKeyID(signature: OSType(0x4D4B4D52), id: UInt32(1))
        let modifiers: UInt32 = UInt32(optionKey | cmdKey)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            modifiers,
            hotKeyID,
            target,
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            AppLogger.log("HotKey register failed status=\(registerStatus)", category: "ui")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        handlerUPP = nil
    }
}
