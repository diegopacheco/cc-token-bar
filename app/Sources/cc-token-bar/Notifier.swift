import Foundation

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

    func evaluate(agg: Aggregates, alerts: [AlertRule]) {
        let today = DataStore.dayKey(for: Date(), cal: cal)
        for a in alerts {
            let value = a.metric == .cost ? agg.today.costUSD : Double(agg.today.total)
            guard a.matches(value) else { continue }
            if firedToday[a.id] == today { continue }
            firedToday[a.id] = today
            save()
            let actual = a.metric == .cost ? DataStore.formatUSD(value) : DataStore.formatTokens(Int(value))
            let limit = a.metric == .cost ? DataStore.formatUSD(a.value) : DataStore.formatTokens(Int(a.value))
            notify(title: "cc-token-bar alert",
                   body: "Daily \(a.metric.label.lowercased()) \(actual) \(a.op.rawValue) \(limit)")
        }
    }

    private func notify(title: String, body: String) {
        let script = "display notification \(Self.appleString(body)) with title \(Self.appleString(title)) sound name \"Submarine\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }

    private static func appleString(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                       .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func save() {
        if let data = try? JSONEncoder().encode(firedToday) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }
}
