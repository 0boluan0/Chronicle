//
//  AppLanguageManager.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/29.
//

import Foundation
import Combine

final class AppLanguageManager: ObservableObject {
    static let shared = AppLanguageManager()

    private let defaults: UserDefaults

    @Published var currentLanguage: String {
        didSet {
            defaults.set(currentLanguage, forKey: Self.languageKey)
        }
    }

    let supportedLanguages: [String] = ["en", "zh-Hans"]

    private init() {
        defaults = AppRuntime.configuredDefaults()
        if let forcedLanguage = AppRuntime.uiTestLanguage,
           supportedLanguages.contains(forcedLanguage) {
            currentLanguage = forcedLanguage
            defaults.set(forcedLanguage, forKey: Self.languageKey)
        } else if let stored = defaults.string(forKey: Self.languageKey), !stored.isEmpty {
            currentLanguage = stored
        } else {
            currentLanguage = "en"
        }
    }

    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: currentLanguage, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    func localizedString(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private static let languageKey = "settings.appLanguage"
}
