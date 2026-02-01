import Foundation
import Combine

final class HealthCheckService: ObservableObject {
    static let shared = HealthCheckService()

    @Published private(set) var lastReport: HealthCheckReport?
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private init() {}

    func runQuickChecks() {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        DatabaseService.shared.runHealthChecks { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRunning = false
                switch result {
                case .success(let report):
                    self.lastReport = report
                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    #if DEBUG
    func runStartupChecks() {
        runQuickChecks()
    }
    #endif
}
