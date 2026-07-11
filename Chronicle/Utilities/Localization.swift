//
//  Localization.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/29.
//

import Foundation
import SwiftUI

func L(_ key: String) -> String {
    AppLanguageManager.shared.localizedString(key)
}

struct LocalizedRootView<Content: View>: View {
    @EnvironmentObject private var languageManager: AppLanguageManager
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.locale, Locale(identifier: languageManager.currentLanguage))
            .defaultAppStorage(AppRuntime.configuredDefaults())
    }
}
