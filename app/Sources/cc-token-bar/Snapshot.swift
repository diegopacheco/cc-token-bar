import AppKit
import SwiftUI

enum Snapshot {
    static func run(outputDir: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let store = DataStore()
        store.start()
        let prefs = PrefsStore(inMemory: true, alerts: [
            AlertRule(metric: .cost, op: .ge, value: 50),
            AlertRule(metric: .cost, op: .gt, value: 200),
            AlertRule(metric: .tokens, op: .ge, value: 500_000_000)
        ], budgetUSD: 500)
        let dir = URL(fileURLWithPath: outputDir)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let targets: [(PanelTab, String)] = [
                (.cost, "screenshot-cost.png"),
                (.latency, "screenshot-latency.png"),
                (.aggregations, "screenshot-aggregates.png"),
                (.projections, "screenshot-projections.png"),
                (.alerts, "screenshot-alerts.png"),
                (.budget, "screenshot-budget.png")
            ]
            for (tab, name) in targets {
                render(tab: tab, store: store, prefs: prefs, to: dir.appendingPathComponent(name))
            }
            app.terminate(nil)
        }
        app.run()
    }

    private static func render(tab: PanelTab, store: DataStore, prefs: PrefsStore, to url: URL) {
        let root = PanelView(store: store, prefs: prefs, initialTab: tab, embedScroll: false)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: AnyView(root))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 800),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        window.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
        FileHandle.standardError.write(Data("wrote \(url.lastPathComponent) \(Int(size.width))x\(Int(size.height))\n".utf8))
    }
}
