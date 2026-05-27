import Foundation
import UserNotifications

final class AlertNotifier {
    private let stateURL: URL
    private let cal = Calendar(identifier: .gregorian)
    private var firedToday: [String: String] = [:]

    init(dataDir: URL) {
        self.stateURL = dataDir.appendingPathComponent("alerts-state.json")
        if let data = try? Data(contentsOf: stateURL),
           let m = try? JSONDecoder().decode([String: String].self, from: data) {
            firedToday = m
        }
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func evaluate(agg: Aggregates, alerts: [AlertRule]) {
        let today = DataStore.dayKey(for: Date(), cal: cal)
        var changed = false
        for a in alerts {
            let value = a.metric == .cost ? agg.today.costUSD : Double(agg.today.total)
            guard a.matches(value) else { continue }
            if firedToday[a.id] == today { continue }
            post(alert: a, value: value)
            firedToday[a.id] = today
            changed = true
        }
        if changed { save() }
    }

    private func post(alert: AlertRule, value: Double) {
        let actual = alert.metric == .cost ? DataStore.formatUSD(value) : DataStore.formatTokens(Int(value))
        let limit = alert.metric == .cost ? DataStore.formatUSD(alert.value) : DataStore.formatTokens(Int(alert.value))
        let content = UNMutableNotificationContent()
        content.title = "cc-token-bar alert"
        content.body = "Daily \(alert.metric.label.lowercased()) \(actual) \(alert.op.rawValue) \(limit)"
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(firedToday) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }
}
