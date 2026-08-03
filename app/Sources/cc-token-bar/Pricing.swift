import Foundation

enum Pricing {
    static let fallback: [String: PriceTier] = [
        "claude-fable-5":   PriceTier(input: 10.0, output: 50.0, cache_write: 12.50, cache_read: 1.00),
        "claude-mythos-5":  PriceTier(input: 10.0, output: 50.0, cache_write: 12.50, cache_read: 1.00),
        "claude-opus-5":    PriceTier(input:  5.0, output: 25.0, cache_write:  6.25, cache_read: 0.50),
        "claude-opus-4-8":  PriceTier(input:  5.0, output: 25.0, cache_write:  6.25, cache_read: 0.50),
        "claude-opus-4-7":  PriceTier(input:  5.0, output: 25.0, cache_write:  6.25, cache_read: 0.50),
        "claude-opus-4-6":  PriceTier(input:  5.0, output: 25.0, cache_write:  6.25, cache_read: 0.50),
        "claude-opus-4-5":  PriceTier(input:  5.0, output: 25.0, cache_write:  6.25, cache_read: 0.50),
        "claude-opus-4":    PriceTier(input: 15.0, output: 75.0, cache_write: 18.75, cache_read: 1.50),
        "claude-sonnet-5":  PriceTier(input:  3.0, output: 15.0, cache_write:  3.75, cache_read: 0.30),
        "claude-sonnet-4":  PriceTier(input:  3.0, output: 15.0, cache_write:  3.75, cache_read: 0.30),
        "claude-haiku-4":   PriceTier(input:  1.0, output:  5.0, cache_write:  1.25, cache_read: 0.10),
    ]

    static func tier(for model: String, table: [String: PriceTier]) -> PriceTier {
        let lower = model.lowercased()
        if let exact = table[lower] { return exact }
        if let match = longestPrefix(lower, in: table) { return match }
        if let match = longestPrefix(lower, in: fallback) { return match }
        return PriceTier(input: 0, output: 0, cache_write: 0, cache_read: 0)
    }

    private static func longestPrefix(_ model: String, in table: [String: PriceTier]) -> PriceTier? {
        var best: (length: Int, tier: PriceTier)?
        for (key, tier) in table where model.hasPrefix(key) {
            if best == nil || key.count > best!.length { best = (key.count, tier) }
        }
        return best?.tier
    }

    static func cost(_ usage: ModelUsage, tier: PriceTier) -> Double {
        let m = 1_000_000.0
        return Double(usage.input_tokens)                   * tier.input       / m
             + Double(usage.output_tokens)                  * tier.output      / m
             + Double(usage.cache_creation_input_tokens)    * tier.cache_write / m
             + Double(usage.cache_read_input_tokens)        * tier.cache_read  / m
    }

    static func loadConfig(from dataDir: URL) -> AppConfig {
        let url = dataDir.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: url),
           let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) {
            let merged = fallback.merging(cfg.pricing) { _, user in user }
            return AppConfig(version: cfg.version,
                             store_project_paths: cfg.store_project_paths,
                             pricing: merged)
        }
        return AppConfig(version: 1, store_project_paths: true, pricing: fallback)
    }
}
