import Foundation

struct EMAProximity {
    let period: Int             // 20, 50, 100, 200
    let emaValue: Double
    let distancePercent: Double // positive = above, negative = below
    let isNear: Bool
}

// Confluence pullback: breakout above major level → pullback to rising EMA
struct ConfluencePullback {
    let detected: Bool
    let breakoutLevel: Double          // the resistance level that was broken
    let breakoutLevelType: String      // "52W High", "Prior Swing High", etc.
    let recentHigh: Double             // the high after breakout
    let pullbackToEMA: Int?            // which EMA it pulled back to (20, 50)
    let pullbackPercent: Double        // how much it pulled back from recentHigh
    let emaRising: Bool                // is the pullback EMA trending up?
    let emaSlopePercent: Double        // EMA slope over last 10 days (annualized %)
    let breakoutLevelDistance: Double   // distance from breakout level (% from price)
    let daysSinceBreakout: Int         // how recently the breakout happened

    // Confluence quality: more factors aligned = stronger setup
    var confluenceCount: Int {
        var c = 0
        if detected { c += 1 }
        if pullbackToEMA != nil { c += 1 }
        if emaRising { c += 1 }
        if abs(breakoutLevelDistance) <= 3.0 { c += 1 } // breakout level also near = double support
        return c
    }

    var summary: String {
        guard detected else { return "-" }
        var parts: [String] = []
        parts.append("Broke \(breakoutLevelType)")
        if let ema = pullbackToEMA {
            parts.append("→ EMA\(ema)")
        }
        if abs(breakoutLevelDistance) <= 3.0 {
            parts.append("+ Support")
        }
        if emaRising {
            parts.append("(Rising)")
        }
        return parts.joined(separator: " ")
    }
}

struct ScanResult: Identifiable {
    let id: String              // tradingsymbol
    let stock: Stock

    // Volume spike
    var volumeSpike: Bool
    var volumeMultiplier: Double   // e.g., 3.2x

    // EMA proximity
    var emaProximities: [EMAProximity]
    var nearEMACount: Int {
        emaProximities.filter(\.isNear).count
    }

    // Breakout flags
    var breakout52Week: Bool
    var distance52WeekPercent: Double  // how far from 52W high
    var above52WeekHigh: Bool          // actual breakout above 52W high

    var breakout20Day: Bool
    var above20DayHigh: Bool
    var distance20DayPercent: Double

    // Confluence pullback
    var confluence: ConfluencePullback

    // Relevance score
    var score: Int {
        var s = 0
        if volumeSpike { s += 1 }
        s += nearEMACount
        if breakout52Week { s += 2 }
        if above52WeekHigh { s += 1 }
        if breakout20Day { s += 1 }
        if above20DayHigh { s += 1 }
        if confluence.detected { s += 3 } // high-value setup
        return s
    }

    // Price change
    var priceChange: Double {
        guard let prev = stock.previousClose, prev > 0 else { return 0 }
        return ((stock.currentPrice - prev) / prev) * 100
    }

    // Summary helpers
    var nearEMASummary: String {
        let near = emaProximities.filter(\.isNear)
        if near.isEmpty { return "-" }
        return near.map { "EMA\($0.period)(\(String(format: "%.1f", $0.distancePercent))%)" }.joined(separator: ", ")
    }

    var breakoutSummary: String {
        var parts: [String] = []
        if above52WeekHigh { parts.append("52W HIGH!") }
        else if breakout52Week { parts.append("Near 52W(\(String(format: "%.1f", distance52WeekPercent))%)") }
        if above20DayHigh { parts.append("20D Break") }
        else if breakout20Day { parts.append("Near 20D") }
        return parts.isEmpty ? "-" : parts.joined(separator: ", ")
    }
}
