import Foundation

enum HealthCheckSeverity: String {
    case warning
    case error
}

struct HealthCheckIssue: Identifiable {
    let id = UUID()
    let severity: HealthCheckSeverity
    let message: String
    let details: String?
}

struct HealthCheckReport {
    let checkedAt: Date
    let issues: [HealthCheckIssue]
    let metrics: [String: String]

    var hasErrors: Bool {
        issues.contains { $0.severity == .error }
    }
}
