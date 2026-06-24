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
            cachedBundle = Self.resolveBundle(for: currentLanguage)
        }
    }

    let supportedLanguages: [String] = ["en", "zh-Hans"]
    private var cachedBundle: Bundle?

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
        cachedBundle = Self.resolveBundle(for: currentLanguage)
    }

    var bundle: Bundle {
        cachedBundle ?? .main
    }

    func localizedString(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private static func resolveBundle(for language: String) -> Bundle {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    private static let languageKey = "settings.appLanguage"
}
