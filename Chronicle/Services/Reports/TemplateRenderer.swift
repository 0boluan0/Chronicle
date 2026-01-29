//
//  TemplateRenderer.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import Foundation

enum TemplateRenderer {
    static func render(template: String, values: [String: String]) -> String {
        var output = template
        for (key, value) in values {
            output = output.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return output
    }
}
