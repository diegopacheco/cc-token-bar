import Foundation
import Combine
import CCMetrics

final class DataStore: ObservableObject {
    @Published private(set) var agg: Aggregates = Aggregates()
    var onAgg: ((Aggregates) -> Void)?

    private let dataDir: URL
    private let sessionsDir: URL
    private let toolsDir: URL
    private var watcher: FSWatcher?
    private var visibleTimer: Timer?
    private let queue = DispatchQueue(label: "cc-token-bar.scan", qos: .userInitiated)
    private var refreshGeneration = 0
    private let transcripts = TranscriptScanner()
    private let subscriptionClient = ClaudeUsageClient()
    private var subscriptionUsage: SubscriptionUsage?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.dataDir = home.appendingPathComponent(".cc-token-bar")
        self.sessionsDir = dataDir.appendingPathComponent("sessions")
        self.toolsDir = dataDir.appendingPathComponent("tools")
    }

    func start() {
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: toolsDir, withIntermediateDirectories: true)
        watcher = FSWatcher(paths: [sessionsDir.path, toolsDir.path]) { [weak self] in
            self?.scheduleRefresh()
        }
        watcher?.start()
        scheduleRefresh()
    }

    func refreshNow() {
        scheduleRefresh(delay: 0)
        refreshSubscription()
    }

    func startVisibleRefresh() {
        stopVisibleRefresh()
        refreshNow()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshNow()
        }
        RunLoop.main.add(t, forMode: .common)
        visibleTimer = t
    }

    func stopVisibleRefresh() {
        visibleTimer?.invalidate()
        visibleTimer = nil
    }

    private func scheduleRefresh(delay: TimeInterval = 0.1) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.refreshGeneration += 1
            let generation = self.refreshGeneration
            self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.refreshGeneration == generation else { return }
                self.refresh()
            }
        }
    }

    private func refreshSubscription() {
        subscriptionClient.fetch { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                switch result {
                case let .success(usage):
                    self.subscriptionUsage = usage
                    self.publishSubscription(usage)
                case .unavailable:
                    guard self.subscriptionUsage != nil else { return }
                    self.subscriptionUsage = nil
                    self.scheduleRefresh(delay: 0)
                case .failed:
                    break
                }
            }
        }
    }

    private func publishSubscription(_ usage: SubscriptionUsage) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var next = self.agg
            Self.applySubscription(usage, to: &next)
            if self.agg != next { self.agg = next }
        }
    }

    private func refresh() {
        let cfg = Pricing.loadConfig(from: dataDir)
        let pricing = cfg.pricing.isEmpty ? Pricing.fallback : cfg.pricing
        let sessions = mergedSessions()
        let tools = loadTools()
        var next = aggregate(sessions: sessions, tools: tools, pricing: pricing)
        if let usage = subscriptionUsage {
            Self.applySubscription(usage, to: &next)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.agg != next { self.agg = next }
            self.onAgg?(next)
        }
    }

    private static func applySubscription(_ usage: SubscriptionUsage, to agg: inout Aggregates) {
        if let session = usage.session {
            agg.sessionUsage = UsageWindow(
                label: "Session (5h)",
                tokens: agg.sessionUsage.tokens,
                resetAt: session.resetAt,
                utilization: session.utilization
            )
        }
        if let weekly = usage.weekly {
            agg.weeklyUsage = UsageWindow(
                label: "Weekly",
                tokens: agg.weeklyUsage.tokens,
                resetAt: weekly.resetAt,
                utilization: weekly.utilization
            )
        }
    }

    private func mergedSessions() -> [SessionFile] {
        let live = transcripts.scan()
        let cached = loadSessions()
        var merged: [String: SessionFile] = [:]
        for s in cached { merged[s.session_id] = s }
        for s in live { merged[s.session_id] = s }
        return Array(merged.values)
    }

    private func loadSessions() -> [SessionFile] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        let dec = JSONDecoder()
        var out: [SessionFile] = []
        out.reserveCapacity(urls.count)
        for url in urls where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let s = try? dec.decode(SessionFile.self, from: data) {
                out.append(s)
            }
        }
        return out
    }

    private func loadTools() -> [ToolsFile] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: toolsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        let dec = JSONDecoder()
        var out: [ToolsFile] = []
        out.reserveCapacity(urls.count)
        for url in urls where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let t = try? dec.decode(ToolsFile.self, from: data) {
                out.append(t)
            }
        }
        return out
    }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoBasic = ISO8601DateFormatter()

    private static func parseISO(_ s: String) -> Date? {
        if let d = isoFrac.date(from: s) { return d }
        return isoBasic.date(from: s)
    }

    private func aggregate(sessions: [SessionFile], tools: [ToolsFile], pricing: [String: PriceTier]) -> Aggregates {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let todayKey = Self.dayKey(for: now, cal: cal)
        let oneDay: TimeInterval = 86_400
        let trendDays = 14
        let sevenDaysAgo = now.addingTimeInterval(-6 * oneDay)
        let trendStart = now.addingTimeInterval(-Double(trendDays - 1) * oneDay)
        let windowSecs: [TimeInterval] = [oneDay, 7 * oneDay, 30 * oneDay, 365 * oneDay]

        var lifetime = TokenTotals()
        var today = TokenTotals()
        var byModelMap: [String: TokenTotals] = [:]
        var byDayMap: [String: (input: Int, output: Int)] = [:]
        var dailyMap: [String: (cost: Double, tokens: Int)] = [:]
        var sessionsTodaySet: Set<String> = []
        var periodCost = [Double](repeating: 0, count: windowSecs.count)
        var periodTokens = [Int](repeating: 0, count: windowSecs.count)
        var periodLatTotal = [Double](repeating: 0, count: windowSecs.count)
        var periodLatCount = [Int](repeating: 0, count: windowSecs.count)
        var stamps: [(when: Date, tokens: Int)] = []

        for s in sessions {
            let when = s.updated_at.flatMap { Self.parseISO($0) }
                ?? s.started_at.flatMap { Self.parseISO($0) }
            let dayKey = when.map { Self.dayKey(for: $0, cal: cal) } ?? todayKey
            let isToday = dayKey == todayKey
            let inWeek = when.map { $0 >= sevenDaysAgo } ?? false

            var sessionCost = 0.0
            var sessionTokens = 0
            for (model, usage) in s.by_model {
                if Self.isSyntheticModel(model) { continue }
                let tier = Pricing.tier(for: model, table: pricing)
                let cost = Pricing.cost(usage, tier: tier)
                add(&lifetime, usage: usage, cost: cost)
                var m = byModelMap[model] ?? TokenTotals()
                add(&m, usage: usage, cost: cost)
                byModelMap[model] = m
                sessionCost += cost
                sessionTokens += usage.input_tokens + usage.output_tokens
                    + usage.cache_creation_input_tokens + usage.cache_read_input_tokens
                if isToday {
                    add(&today, usage: usage, cost: cost)
                    sessionsTodaySet.insert(s.session_id)
                }
                if inWeek {
                    var d = byDayMap[dayKey] ?? (0, 0)
                    d.input  += usage.input_tokens + usage.cache_creation_input_tokens + usage.cache_read_input_tokens
                    d.output += usage.output_tokens
                    byDayMap[dayKey] = d
                }
            }

            var sessionLatTotal = 0.0
            var sessionLatCount = 0
            for (_, lat) in s.tool_latency ?? [:] {
                sessionLatTotal += lat.totalMs
                sessionLatCount += lat.count
            }

            if let when = when {
                if sessionTokens > 0 { stamps.append((when, sessionTokens)) }
                let age = now.timeIntervalSince(when)
                for i in windowSecs.indices where age <= windowSecs[i] {
                    periodCost[i] += sessionCost
                    periodTokens[i] += sessionTokens
                    periodLatTotal[i] += sessionLatTotal
                    periodLatCount[i] += sessionLatCount
                }
                if when >= trendStart {
                    var d = dailyMap[dayKey] ?? (0, 0)
                    d.cost += sessionCost
                    d.tokens += sessionTokens
                    dailyMap[dayKey] = d
                }
            }
        }

        let periodLabels = ["Day", "Week", "Month", "Year"]
        let periodSubs = ["last 24h", "last 7 days", "last 30 days", "last 365 days"]
        let periods: [PeriodRollup] = windowSecs.indices.map { i in
            PeriodRollup(label: periodLabels[i], sub: periodSubs[i],
                         costUSD: periodCost[i], tokens: periodTokens[i],
                         avgLatencyMs: periodLatCount[i] > 0 ? periodLatTotal[i] / Double(periodLatCount[i]) : 0)
        }
        let dailyCostRate = periodCost[1] / 7.0
        let dailyTokenRate = Double(periodTokens[1]) / 7.0
        let projection = Projection(
            weeklyCost: dailyCostRate * 7.0,
            monthlyCost: dailyCostRate * 30.0,
            weeklyTokens: Int(dailyTokenRate * 7.0),
            monthlyTokens: Int(dailyTokenRate * 30.0)
        )

        var trendActual: [TrendPoint] = []
        for i in 0..<trendDays {
            let day = cal.startOfDay(for: now.addingTimeInterval(-Double(trendDays - 1 - i) * oneDay))
            let key = Self.dayKey(for: day, cal: cal)
            let v = dailyMap[key] ?? (0, 0)
            trendActual.append(TrendPoint(id: "a-\(key)", date: day, cost: v.cost, tokens: v.tokens, projected: false))
        }
        var trend = trendActual
        if let last = trendActual.last {
            trend.append(TrendPoint(id: "p-0", date: last.date, cost: last.cost, tokens: last.tokens, projected: true))
            for j in 1...7 {
                let day = cal.startOfDay(for: now.addingTimeInterval(Double(j) * oneDay))
                trend.append(TrendPoint(id: "p-\(j)", date: day, cost: dailyCostRate, tokens: Int(dailyTokenRate), projected: true))
            }
        }

        let weekKeys: [String] = (0..<7).map { i in
            let d = Date().addingTimeInterval(-Double(6 - i) * oneDay)
            return Self.dayKey(for: d, cal: cal)
        }
        let weekLabels: [String] = (0..<7).map { i in
            let d = Date().addingTimeInterval(-Double(6 - i) * oneDay)
            return Self.shortDayLabel(for: d, cal: cal)
        }
        let byDay: [DayBucket] = zip(weekKeys, weekLabels).map { (key, label) in
            let v = byDayMap[key] ?? (0, 0)
            return DayBucket(id: key, label: label, input: v.input, output: v.output)
        }

        let avgInputPricePerM: Double = {
            var totalInput = 0
            var totalCost = 0.0
            for (model, t) in byModelMap {
                let tier = Pricing.tier(for: model, table: pricing)
                totalInput += t.input
                totalCost += Double(t.input) * tier.input / 1_000_000.0
            }
            guard totalInput > 0 else { return 5.0 }
            return totalCost / Double(totalInput) * 1_000_000.0
        }()

        var toolStats: [ToolStat] = []
        var toolAcc: [String: (count: Int, bytes: Int)] = [:]
        for tf in tools {
            for (name, e) in tf.tools {
                let key = ToolMetrics.normalizeToolName(name)
                var v = toolAcc[key] ?? (0, 0)
                v.count += e.count
                v.bytes += e.input_bytes + e.output_bytes
                toolAcc[key] = v
            }
        }
        for (name, v) in toolAcc {
            let approxTokens = v.bytes / 4
            let cost = Double(approxTokens) / 1_000_000.0 * avgInputPricePerM
            toolStats.append(ToolStat(name: name, count: v.count, approxTokens: approxTokens, costUSD: cost))
        }
        toolStats.sort { $0.costUSD > $1.costUSD }

        var latAcc: [String: (count: Int, total: Double)] = [:]
        for s in sessions {
            guard let tl = s.tool_latency else { continue }
            for (name, agg) in tl {
                let key = ToolMetrics.normalizeToolName(name)
                var v = latAcc[key] ?? (0, 0)
                v.count += agg.count
                v.total += agg.totalMs
                latAcc[key] = v
            }
        }
        var toolLatencies: [ToolLatency] = latAcc.map { (name, v) in
            ToolLatency(name: name, count: v.count,
                        avgMs: v.count > 0 ? v.total / Double(v.count) : 0,
                        totalMs: v.total)
        }
        toolLatencies.sort { $0.avgMs > $1.avgMs }

        let cacheReads = byModelMap.values.reduce(0) { $0 + $1.cacheRead }
        let cacheDen = byModelMap.values.reduce(0) { $0 + $1.input + $1.cacheWrite + $1.cacheRead }
        let cacheRatio = cacheDen > 0 ? Double(cacheReads) / Double(cacheDen) : 0

        let byModelSorted = byModelMap
            .map { ($0.key, $0.value) }
            .sorted { $0.1.costUSD > $1.1.costUSD }

        let label = Self.formatStatusLabel(today: today)
        let sessionUsage = Self.sessionWindow(stamps: stamps, now: now, cal: cal)
        let weeklyUsage = Self.weeklyWindow(stamps: stamps, now: now)

        return Aggregates(
            today: today,
            lifetime: lifetime,
            sessionUsage: sessionUsage,
            weeklyUsage: weeklyUsage,
            byModel: byModelSorted,
            byDay: byDay,
            tools: Array(toolStats.prefix(10)),
            toolLatencies: Array(toolLatencies.prefix(10)),
            periods: periods,
            projection: projection,
            trend: trend,
            cacheHitRatio: cacheRatio,
            sessionsToday: sessionsTodaySet.count,
            sessionsLifetime: sessions.count,
            statusLabel: label
        )
    }

    private func add(_ t: inout TokenTotals, usage: ModelUsage, cost: Double) {
        t.input      += usage.input_tokens
        t.output     += usage.output_tokens
        t.cacheWrite += usage.cache_creation_input_tokens
        t.cacheRead  += usage.cache_read_input_tokens
        t.costUSD    += cost
    }

    static let blockLength: TimeInterval = 5 * 3600

    static func sessionWindow(stamps: [(when: Date, tokens: Int)], now: Date, cal: Calendar) -> UsageWindow {
        let sorted = stamps.sorted { $0.when < $1.when }
        var blockStart: Date?
        for s in sorted {
            if let start = blockStart, s.when < start.addingTimeInterval(blockLength) { continue }
            var c = cal.dateComponents([.year, .month, .day, .hour], from: s.when)
            c.minute = 0
            c.second = 0
            blockStart = cal.date(from: c) ?? s.when
        }
        guard let start = blockStart else {
            return UsageWindow(label: "Session (5h)", tokens: 0, resetAt: nil)
        }
        let end = start.addingTimeInterval(blockLength)
        guard now < end else {
            return UsageWindow(label: "Session (5h)", tokens: 0, resetAt: nil)
        }
        let total = sorted.filter { $0.when >= start && $0.when < end }.reduce(0) { $0 + $1.tokens }
        return UsageWindow(label: "Session (5h)", tokens: total, resetAt: end)
    }

    static func weeklyWindow(stamps: [(when: Date, tokens: Int)], now: Date) -> UsageWindow {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else {
            return UsageWindow(label: "Weekly", tokens: 0, resetAt: nil)
        }
        let total = stamps.filter { $0.when >= week.start && $0.when < week.end }.reduce(0) { $0 + $1.tokens }
        return UsageWindow(label: "Weekly", tokens: total, resetAt: week.end)
    }

    static func formatReset(_ date: Date?, now: Date) -> String {
        guard let date = date else { return "no active block" }
        let secs = date.timeIntervalSince(now)
        if secs <= 0 { return "resetting" }
        if secs < 86_400 {
            let h = Int(secs) / 3600
            let m = (Int(secs) % 3600) / 60
            return h > 0 ? "resets in \(h)h \(m)m" : "resets in \(m)m"
        }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return "resets \(f.string(from: date))"
    }

    static func dayKey(for date: Date, cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func shortDayLabel(for date: Date, cal: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = cal
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    static func formatStatusLabel(today: TokenTotals) -> String {
        return "\(formatTokens(today.total)) \(formatUSD(today.costUSD))"
    }

    private static let groupedIntFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.maximumFractionDigits = 0
        return f
    }()

    private static let usdFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static func formatTokens(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1_000_000_000 { return String(format: "%.2fB", d / 1_000_000_000) }
        if d >= 1_000_000     { return String(format: "%.1fM", d / 1_000_000) }
        if d >= 10_000        { return String(format: "%.0fk", d / 1_000) }
        if d >= 1_000         { return String(format: "%.1fk", d / 1_000) }
        return groupedIntFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func formatUSD(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "$%.2fM", v / 1_000_000) }
        return usdFormatter.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
    }

    static func formatCount(_ n: Int) -> String {
        return groupedIntFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func formatMs(_ ms: Double) -> String {
        if ms >= 1000 { return String(format: "%.2fs", ms / 1000) }
        return String(format: "%.0f ms", ms)
    }

    static func isSyntheticModel(_ name: String) -> Bool {
        return name.hasPrefix("<") || name.lowercased().contains("synthetic")
    }
}
