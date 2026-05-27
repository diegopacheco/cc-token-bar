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
}

final class PrefsStore: ObservableObject {
    @Published var alerts: [AlertRule] { didSet { save() } }
    @Published var budgetUSD: Double { didSet { save() } }

    private let url: URL?

    init(inMemory: Bool = false, alerts: [AlertRule] = [], budgetUSD: Double = 0) {
        if inMemory {
            self.url = nil
            self.alerts = alerts
            self.budgetUSD = budgetUSD
            return
        }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cc-token-bar")
        self.url = dir.appendingPathComponent("prefs.json")
        if let url = self.url, let data = try? Data(contentsOf: url),
           let f = try? JSONDecoder().decode(PrefsFile.self, from: data) {
            self.alerts = f.alerts
            self.budgetUSD = f.budget_usd
        } else {
            self.alerts = []
            self.budgetUSD = 0
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
        let f = PrefsFile(alerts: alerts, budget_usd: budgetUSD)
        if let data = try? JSONEncoder().encode(f) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
