import AppKit
import SwiftUI

enum Snapshot {
    static func run(outputDir: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let store = DataStore()
        store.start()
        let dir = URL(fileURLWithPath: outputDir)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let targets: [(PanelTab, String)] = [
                (.aggregations, "screenshot-aggregates.png"),
                (.projections, "screenshot-projections.png")
            ]
            for (tab, name) in targets {
                render(tab: tab, store: store, to: dir.appendingPathComponent(name))
            }
            app.terminate(nil)
        }
        app.run()
    }

    private static func render(tab: PanelTab, store: DataStore, to url: URL) {
        let root = PanelView(store: store, initialTab: tab, embedScroll: false)
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
