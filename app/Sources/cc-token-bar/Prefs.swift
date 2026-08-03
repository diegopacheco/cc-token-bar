import Foundation
import Combine

enum AlertMetric: String, Codable, CaseIterable, Identifiable {
    case cost
    case tokens
    var id: String { rawValue }
    var label: String { self == .cost ? "Cost" : "Tokens" }
}

enum AlertOp: String, Codable, CaseIterable, Identifiable {
    case lt = "<"
    case le = "<="
    case eq = "="
    case ge = ">="
    case gt = ">"
    var id: String { rawValue }
}

struct AlertRule: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var metric: AlertMetric
    var op: AlertOp
    var value: Double

    func matches(_ x: Double) -> Bool {
        switch op {
        case .lt: return x < value
        case .le: return x <= value
        case .eq: return x == value
        case .ge: return x >= value
        case .gt: return x > value
        }
    }
}

private struct PrefsFile: Codable {
    var alerts: [AlertRule]
    var budget_usd: Double
    var session_token_limit: Int?
    var weekly_token_limit: Int?
}

final class PrefsStore: ObservableObject {
    static let defaultSessionTokenLimit = 500_000_000
    static let defaultWeeklyTokenLimit = 1_500_000_000

    @Published var alerts: [AlertRule] { didSet { save() } }
    @Published var budgetUSD: Double { didSet { save() } }
    @Published var sessionTokenLimit: Int { didSet { save() } }
    @Published var weeklyTokenLimit: Int { didSet { save() } }

    private let url: URL?

    init(inMemory: Bool = false, alerts: [AlertRule] = [], budgetUSD: Double = 0) {
        if inMemory {
            self.url = nil
            self.alerts = alerts
            self.budgetUSD = budgetUSD
            self.sessionTokenLimit = Self.defaultSessionTokenLimit
            self.weeklyTokenLimit = Self.defaultWeeklyTokenLimit
            return
        }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cc-token-bar")
        self.url = dir.appendingPathComponent("prefs.json")
        if let url = self.url, let data = try? Data(contentsOf: url),
           let f = try? JSONDecoder().decode(PrefsFile.self, from: data) {
            self.alerts = f.alerts
            self.budgetUSD = f.budget_usd
            self.sessionTokenLimit = f.session_token_limit ?? Self.defaultSessionTokenLimit
            self.weeklyTokenLimit = f.weekly_token_limit ?? Self.defaultWeeklyTokenLimit
        } else {
            self.alerts = []
            self.budgetUSD = 0
            self.sessionTokenLimit = Self.defaultSessionTokenLimit
            self.weeklyTokenLimit = Self.defaultWeeklyTokenLimit
        }
    }

    func addAlert(metric: AlertMetric, op: AlertOp, value: Double) {
        alerts.append(AlertRule(metric: metric, op: op, value: value))
    }

    func removeAlert(_ id: String) {
        alerts.removeAll { $0.id == id }
    }

    private func save() {
        guard let url = url else { return }
        let f = PrefsFile(alerts: alerts, budget_usd: budgetUSD,
                          session_token_limit: sessionTokenLimit,
                          weekly_token_limit: weeklyTokenLimit)
        if let data = try? JSONEncoder().encode(f) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
