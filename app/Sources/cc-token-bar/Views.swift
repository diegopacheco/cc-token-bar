import SwiftUI
import Charts
import AppKit

enum PanelTab: Hashable {
    case cost
    case latency
    case aggregations
    case projections
    case alerts
    case budget
}

struct PanelView: View {
    @ObservedObject var store: DataStore
    @ObservedObject var prefs: PrefsStore
    @State private var tab: PanelTab
    @State private var draftMetric: AlertMetric = .cost
    @State private var draftOp: AlertOp = .ge
    @State private var draftValue: String = ""
    private let embedScroll: Bool

    init(store: DataStore, prefs: PrefsStore, initialTab: PanelTab = .cost, embedScroll: Bool = true) {
        self.store = store
        self.prefs = prefs
        self._tab = State(initialValue: initialTab)
        self.embedScroll = embedScroll
    }

    var body: some View {
        Group {
            if embedScroll {
                ScrollView(.vertical, showsIndicators: false) { content }
            } else {
                content
            }
        }
        .frame(width: 360)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabBar
            switch tab {
            case .cost:
                kpiSection
                divider
                cacheSection
                divider
                chartSection
                divider
                toolsSection
                divider
                modelsSection
            case .latency:
                latencySection
            case .aggregations:
                aggregationsSection
            case .projections:
                projectionsSection
            case .alerts:
                alertsSection
            case .budget:
                budgetSection
            }
            footer
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton(.cost, "dollarsign.circle", "Cost")
            tabButton(.latency, "timer", "Latency")
            tabButton(.aggregations, "square.grid.2x2", "Aggregates")
            tabButton(.projections, "chart.line.uptrend.xyaxis", "Projections")
            tabButton(.alerts, "bell", "Alerts")
            tabButton(.budget, "chart.pie", "Budget")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func tabButton(_ t: PanelTab, _ symbol: String, _ name: String) -> some View {
        Button { tab = t } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                Text(name).font(.system(size: 8)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(tab == t ? Color.accentColor.opacity(0.18) : Color.clear)
            .foregroundStyle(tab == t ? Color.accentColor : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(name)
    }

    private var header: some View {
        HStack {
            Text("cc-token-bar").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.bottom, 10)
        .overlay(Divider(), alignment: .bottom)
    }

    private var divider: some View {
        Divider().opacity(0.6)
    }

    private var kpiSection: some View {
        HStack(spacing: 10) {
            kpi(title: "Today",
                value: DataStore.formatTokens(store.agg.today.total),
                sub: "\(DataStore.formatUSD(store.agg.today.costUSD))  ·  \(DataStore.formatCount(store.agg.sessionsToday)) sessions")
            kpi(title: "All time",
                value: DataStore.formatTokens(store.agg.lifetime.total),
                sub: "\(DataStore.formatUSD(store.agg.lifetime.costUSD))  ·  \(DataStore.formatCount(store.agg.sessionsLifetime)) sessions")
        }
        .padding(14)
    }

    private func kpi(title: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
            Text(sub).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Cache hit ratio")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.1f%%", store.agg.cacheHitRatio * 100))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(store.agg.cacheHitRatio >= 0.6
                        ? Color(red: 0.18, green: 0.62, blue: 0.45)
                        : Color(red: 0.92, green: 0.55, blue: 0.20))
                    .monospacedDigit()
                Text("cache reads vs total input").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Last 7 days — input / output")
            Chart {
                ForEach(store.agg.byDay) { day in
                    BarMark(
                        x: .value("Day", day.label),
                        y: .value("Input", day.input)
                    ).foregroundStyle(Color.accentColor).cornerRadius(2)
                    BarMark(
                        x: .value("Day", day.label),
                        y: .value("Output", day.output)
                    ).foregroundStyle(Color.orange).cornerRadius(2)
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic) {
                    AxisValueLabel().font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .frame(height: 110)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Tools (by cost)")
            if store.agg.tools.isEmpty {
                Text("No tool data yet").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                let maxCost = store.agg.tools.first?.costUSD ?? 1
                ForEach(store.agg.tools) { t in
                    HStack(spacing: 10) {
                        Text(t.name).font(.system(size: 12, weight: .medium))
                            .lineLimit(1).truncationMode(.tail)
                            .frame(width: 96, alignment: .leading)
                        bar(fraction: maxCost > 0 ? t.costUSD / maxCost : 0)
                        Text(DataStore.formatUSD(t.costUSD))
                            .font(.system(size: 11)).monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                        Text("\(DataStore.formatCount(t.count))×")
                            .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var latencySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Tool latency (avg per call)")
            if store.agg.toolLatencies.isEmpty {
                Text("No latency data yet").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                let maxMs = store.agg.toolLatencies.first?.avgMs ?? 1
                ForEach(store.agg.toolLatencies) { t in
                    HStack(spacing: 10) {
                        Text(t.name).font(.system(size: 12, weight: .medium))
                            .lineLimit(1).truncationMode(.tail)
                            .frame(width: 96, alignment: .leading)
                        bar(fraction: maxMs > 0 ? t.avgMs / maxMs : 0)
                        Text(DataStore.formatMs(t.avgMs))
                            .font(.system(size: 11)).monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                        Text("\(DataStore.formatCount(t.count))×")
                            .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var aggregationsSection: some View {
        let periods = store.agg.periods
        let maxCost = periods.map(\.costUSD).max() ?? 0
        let maxTokens = periods.map(\.tokens).max() ?? 0
        let maxLat = periods.map(\.avgLatencyMs).max() ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            metricCard("Cost", rows: periods.map {
                ($0.label, maxCost > 0 ? $0.costUSD / maxCost : 0, DataStore.formatUSD($0.costUSD))
            })
            metricCard("Tokens", rows: periods.map {
                ($0.label, maxTokens > 0 ? Double($0.tokens) / Double(maxTokens) : 0, DataStore.formatTokens($0.tokens))
            })
            metricCard("Avg latency", rows: periods.map {
                ($0.label, maxLat > 0 ? $0.avgLatencyMs / maxLat : 0,
                 $0.avgLatencyMs > 0 ? DataStore.formatMs($0.avgLatencyMs) : "—")
            })
        }
        .padding(14)
    }

    private func metricCard(_ title: String, rows: [(label: String, fraction: Double, value: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            ForEach(rows, id: \.label) { r in
                HStack(spacing: 10) {
                    Text(r.label).font(.system(size: 12, weight: .medium))
                        .frame(width: 46, alignment: .leading)
                    bar(fraction: r.fraction)
                    Text(r.value).font(.system(size: 12)).monospacedDigit()
                        .frame(width: 84, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var projectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Projected at last 7-day pace")
            HStack(spacing: 10) {
                kpi(title: "Next 7 days",
                    value: DataStore.formatUSD(store.agg.projection.weeklyCost),
                    sub: "\(DataStore.formatTokens(store.agg.projection.weeklyTokens)) tokens")
                kpi(title: "Next 30 days",
                    value: DataStore.formatUSD(store.agg.projection.monthlyCost),
                    sub: "\(DataStore.formatTokens(store.agg.projection.monthlyTokens)) tokens")
            }
            trendChart(title: "Cost trend", value: { $0.cost })
            trendChart(title: "Token trend", value: { Double($0.tokens) })
            Text("Solid line = actual daily usage (last 14 days). Dashed line = projected forward at your last 7-day pace.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }

    private func trendChart(title: String, value: @escaping (TrendPoint) -> Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(title)
            Chart(store.agg.trend) { p in
                if !p.projected {
                    AreaMark(x: .value("Day", p.date), y: .value(title, value(p)))
                        .foregroundStyle(LinearGradient(
                            colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                }
                LineMark(x: .value("Day", p.date), y: .value(title, value(p)))
                    .foregroundStyle(by: .value("Kind", p.projected ? "Projected" : "Actual"))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: p.projected ? [4, 3] : []))
                    .interpolationMethod(.monotone)
            }
            .chartForegroundStyleScale(["Actual": Color.accentColor,
                                        "Projected": Color(red: 0.55, green: 0.36, blue: 0.96)])
            .chartLegend(position: .top, alignment: .trailing, spacing: 4)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .frame(height: 92)
        }
    }

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("New alert")
            HStack(spacing: 6) {
                Picker("", selection: $draftMetric) {
                    ForEach(AlertMetric.allCases) { Text($0.label).tag($0) }
                }.labelsHidden().frame(width: 92)
                Picker("", selection: $draftOp) {
                    ForEach(AlertOp.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 64)
                TextField("amount", text: $draftValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 86)
                    .onChange(of: draftValue) { draftValue = Self.numericOnly($0) }
                Button {
                    if let v = Double(draftValue) {
                        prefs.addAlert(metric: draftMetric, op: draftOp, value: v)
                        draftValue = ""
                    }
                } label: { Image(systemName: "plus.circle.fill").font(.system(size: 18)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Double(draftValue) == nil ? Color.secondary : Color.accentColor)
                    .disabled(Double(draftValue) == nil)
            }
            divider
            sectionTitle("Your alerts")
            if prefs.alerts.isEmpty {
                Text("No alerts yet. Add one above — you'll get a notification when a daily total crosses it.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach($prefs.alerts) { $alert in
                    HStack(spacing: 6) {
                        Picker("", selection: $alert.metric) {
                            ForEach(AlertMetric.allCases) { Text($0.label).tag($0) }
                        }.labelsHidden().frame(width: 92)
                        Picker("", selection: $alert.op) {
                            ForEach(AlertOp.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().frame(width: 64)
                        TextField("", value: $alert.value, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 86)
                        Button { prefs.removeAlert(alert.id) } label: {
                            Image(systemName: "trash").font(.system(size: 13))
                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
    }

    private static func numericOnly(_ s: String) -> String {
        var seenDot = false
        return String(s.filter { c in
            if c.isNumber { return true }
            if c == "." && !seenDot { seenDot = true; return true }
            return false
        })
    }

    private var budgetSection: some View {
        let used = store.agg.today.costUSD
        let budget = prefs.budgetUSD
        let remaining = max(0, budget - used)
        let fraction = budget > 0 ? min(1, used / budget) : 0
        let over = budget > 0 && used > budget
        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Daily budget")
            HStack(spacing: 6) {
                Text("$").foregroundStyle(.secondary)
                TextField("amount", value: $prefs.budgetUSD, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 110)
                Text("per day").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if budget <= 0 {
                Text("Set a daily budget to see how much of today's spend is left.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                budgetDonut(fraction: fraction, remaining: remaining, over: over)
                    .frame(maxWidth: .infinity)
                Text(over
                     ? "Over budget by \(DataStore.formatUSD(used - budget)) — used \(DataStore.formatUSD(used)) of \(DataStore.formatUSD(budget))."
                     : "Used \(DataStore.formatUSD(used)) of \(DataStore.formatUSD(budget)) today (\(String(format: "%.0f%%", fraction * 100))).")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }

    private func budgetDonut(fraction: Double, remaining: Double, over: Bool) -> some View {
        let usedColor = over ? Color(red: 0.86, green: 0.24, blue: 0.24) : Color.accentColor
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 18)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(usedColor, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(DataStore.formatUSD(remaining))
                    .font(.system(size: 22, weight: .bold)).monospacedDigit()
                    .foregroundStyle(over ? usedColor : Color.primary)
                Text(over ? "over" : "left today").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 150, height: 150)
        .padding(.vertical, 6)
    }

    private func bar(fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color.accentColor, .orange],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Cost by model")
            if store.agg.byModel.isEmpty {
                Text("No model data yet").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                let total = store.agg.byModel.reduce(0.0) { $0 + $1.1.costUSD }
                ForEach(store.agg.byModel, id: \.0) { (name, t) in
                    HStack {
                        Text(name).font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        let pct = total > 0 ? t.costUSD / total * 100 : 0
                        Text("\(DataStore.formatUSD(t.costUSD))  ·  \(String(format: "%.0f%%", pct))")
                            .font(.system(size: 12)).monospacedDigit()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Button("Open data folder") {
                let url = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".cc-token-bar")
                NSWorkspace.shared.open(url)
            }.buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 11))
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 11))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(Divider(), alignment: .top)
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.6)
    }
}
