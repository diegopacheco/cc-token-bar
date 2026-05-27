import SwiftUI
import Charts
import AppKit

enum PanelTab: Hashable {
    case cost
    case latency
    case aggregations
    case projections
}

struct PanelView: View {
    @ObservedObject var store: DataStore
    @State private var tab: PanelTab
    private let embedScroll: Bool

    init(store: DataStore, initialTab: PanelTab = .cost, embedScroll: Bool = true) {
        self.store = store
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
            }
            footer
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tabBar: some View {
        Picker("", selection: $tab) {
            Text("Cost").tag(PanelTab.cost)
            Text("Latency").tag(PanelTab.latency)
            Text("Aggregates").tag(PanelTab.aggregations)
            Text("Projections").tag(PanelTab.projections)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14).padding(.vertical, 10)
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
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Rolling windows — cost · tokens · avg latency")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(store.agg.periods) { p in periodCard(p) }
            }
        }
        .padding(14)
    }

    private func periodCard(_ p: PeriodRollup) -> some View {
        let maxCost = store.agg.periods.map(\.costUSD).max() ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(p.label).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(p.sub).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Text(DataStore.formatUSD(p.costUSD))
                .font(.system(size: 18, weight: .bold)).monospacedDigit()
                .foregroundStyle(Color.accentColor)
            bar(fraction: maxCost > 0 ? p.costUSD / maxCost : 0)
            HStack(spacing: 6) {
                Text(DataStore.formatTokens(p.tokens))
                Text("·").foregroundStyle(.tertiary)
                Text(p.avgLatencyMs > 0 ? DataStore.formatMs(p.avgLatencyMs) : "—")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(10)
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
            .chartForegroundStyleScale(["Actual": Color.accentColor, "Projected": Color.orange])
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
