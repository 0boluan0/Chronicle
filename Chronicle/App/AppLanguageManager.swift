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

    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: Self.languageKey)
        }
    }

    let supportedLanguages: [String] = ["en", "zh-Hans"]

    private init() {
        if let stored = UserDefaults.standard.string(forKey: Self.languageKey), !stored.isEmpty {
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
