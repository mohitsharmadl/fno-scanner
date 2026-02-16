import SwiftUI

struct StockDetailView: View {
    let result: ScanResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                Divider()

                // Price & Volume
                HStack(alignment: .top, spacing: 24) {
                    priceSection
                    volumeSection
                }

                Divider()

                // EMA Section
                emaSection

                Divider()

                // Confluence Pullback Section
                confluenceSection

                Divider()

                // Breakout Section
                breakoutSection

                Divider()

                // Flags Summary
                flagsSection

                Spacer()
            }
            .padding(20)
        }
        .frame(minWidth: 300)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.stock.id)
                    .font(.title.bold())
                Text(result.stock.name)
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                HStack(spacing: 4) {
                    Text("Score:")
                        .foregroundColor(.secondary)
                    Text("\(result.score)")
                        .font(.title2.bold())
                        .foregroundColor(result.score >= 3 ? .green : result.score >= 1 ? .orange : .secondary)
                }
                Text("NSE")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue.opacity(0.15)))
            }
        }
    }

    // MARK: - Price

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRICE")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            Text(String(format: "%.2f", result.stock.currentPrice))
                .font(.system(.title, design: .monospaced, weight: .bold))

            HStack {
                Text(String(format: "%+.2f%%", result.priceChange))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(result.priceChange >= 0 ? .green : .red)
            }

            if let open = result.stock.dayOpen, let high = result.stock.dayHigh,
               let low = result.stock.dayLow {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("Open").font(.caption).foregroundColor(.secondary)
                        Text(String(format: "%.2f", open)).font(.caption.monospaced())
                    }
                    GridRow {
                        Text("High").font(.caption).foregroundColor(.secondary)
                        Text(String(format: "%.2f", high)).font(.caption.monospaced())
                    }
                    GridRow {
                        Text("Low").font(.caption).foregroundColor(.secondary)
                        Text(String(format: "%.2f", low)).font(.caption.monospaced())
                    }
                    if let prev = result.stock.previousClose {
                        GridRow {
                            Text("Prev Close").font(.caption).foregroundColor(.secondary)
                            Text(String(format: "%.2f", prev)).font(.caption.monospaced())
                        }
                    }
                }
            }
        }
    }

    // MARK: - Volume

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VOLUME")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            Text(formatLargeNumber(result.stock.currentVolume))
                .font(.system(.title2, design: .monospaced, weight: .bold))

            if let avg = result.stock.avgVolume20, avg > 0 {
                // Volume bar comparison
                VStack(alignment: .leading, spacing: 4) {
                    Text("vs 20-day avg")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Today")
                                .font(.caption2)
                            GeometryReader { geo in
                                let ratio = min(Double(result.stock.currentVolume) / avg, 5.0)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(result.volumeSpike ? Color.red.opacity(0.8) : Color.blue.opacity(0.6))
                                    .frame(width: geo.size.width * (ratio / 5.0))
                            }
                            .frame(height: 12)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Avg")
                                .font(.caption2)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.gray.opacity(0.4))
                                    .frame(width: geo.size.width * (1.0 / 5.0))
                            }
                            .frame(height: 12)
                        }
                    }
                    .frame(width: 150)

                    if result.volumeSpike {
                        Text(String(format: "%.1fx spike!", result.volumeMultiplier))
                            .font(.caption.bold())
                            .foregroundColor(.red)
                    } else {
                        Text(String(format: "%.1fx of average", result.volumeMultiplier))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - EMA

    private var emaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EMA PROXIMITY")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            if result.emaProximities.isEmpty {
                Text("No EMA data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("EMA").font(.caption.bold())
                        Text("Value").font(.caption.bold())
                        Text("Distance").font(.caption.bold())
                        Text("Status").font(.caption.bold())
                    }
                    .foregroundColor(.secondary)

                    ForEach(result.emaProximities, id: \.period) { prox in
                        GridRow {
                            Text("EMA \(prox.period)")
                                .font(.system(.caption, design: .monospaced))
                            Text(String(format: "%.2f", prox.emaValue))
                                .font(.system(.caption, design: .monospaced))
                            Text(String(format: "%+.2f%%", prox.distancePercent))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(prox.distancePercent >= 0 ? .green : .red)
                            if prox.isNear {
                                Text("NEAR")
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.blue))
                            } else {
                                Text(prox.distancePercent > 0 ? "Above" : "Below")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Confluence Pullback

    private var confluenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CONFLUENCE PULLBACK")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                if result.confluence.detected {
                    HStack(spacing: 3) {
                        ForEach(0..<result.confluence.confluenceCount, id: \.self) { _ in
                            Circle().fill(Color.purple).frame(width: 6, height: 6)
                        }
                    }
                }
            }

            if result.confluence.detected {
                let c = result.confluence

                // Visual: Breakout → Pullback flow
                VStack(alignment: .leading, spacing: 12) {
                    // The setup narrative
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right")
                            .foregroundColor(.green)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Broke above \(c.breakoutLevelType)")
                                .font(.callout.bold())
                            Text("Level: \(String(format: "%.2f", c.breakoutLevel)) → High: \(String(format: "%.2f", c.recentHigh))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(c.daysSinceBreakout) days ago")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Image(systemName: "arrow.down")
                        .foregroundColor(.orange)
                        .padding(.leading, 12)

                    HStack(spacing: 8) {
                        Image(systemName: "arrow.turn.down.right")
                            .foregroundColor(.purple)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            if let ema = c.pullbackToEMA {
                                Text("Pulled back to EMA \(ema)")
                                    .font(.callout.bold())
                            }
                            Text("Pullback: \(String(format: "%.1f", c.pullbackPercent))% from high")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Confluence factors
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Confluence Factors:")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)

                        confluenceFactor(
                            "Breakout confirmed",
                            detail: "\(c.breakoutLevelType) at \(String(format: "%.2f", c.breakoutLevel))",
                            active: true
                        )

                        if let ema = c.pullbackToEMA {
                            confluenceFactor(
                                "EMA \(ema) support",
                                detail: "Price at dynamic support level",
                                active: true
                            )
                        }

                        confluenceFactor(
                            "EMA trending up",
                            detail: String(format: "Slope: %+.2f%% (10d)", c.emaSlopePercent),
                            active: c.emaRising
                        )

                        confluenceFactor(
                            "Old resistance = new support",
                            detail: String(format: "Breakout level %.1f%% away", c.breakoutLevelDistance),
                            active: abs(c.breakoutLevelDistance) <= 3.0
                        )
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.06)))
                }
            } else {
                Text("No confluence pullback detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func confluenceFactor(_ title: String, detail: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundColor(active ? .purple : .secondary.opacity(0.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(active ? .primary : .secondary.opacity(0.5))
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Breakout

    private var breakoutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BREAKOUT ANALYSIS")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                if let h52 = result.stock.high52Week {
                    GridRow {
                        Text("52W High")
                            .font(.caption)
                        Text(String(format: "%.2f", h52))
                            .font(.system(.caption, design: .monospaced))
                        Text(String(format: "%.1f%% away", result.distance52WeekPercent))
                            .font(.caption)
                            .foregroundColor(result.above52WeekHigh ? .green : .secondary)
                        if result.above52WeekHigh {
                            breakoutBadge("NEW HIGH!", color: .green)
                        } else if result.breakout52Week {
                            breakoutBadge("NEAR", color: .orange)
                        }
                    }
                }

                if let l52 = result.stock.low52Week {
                    GridRow {
                        Text("52W Low")
                            .font(.caption)
                        Text(String(format: "%.2f", l52))
                            .font(.system(.caption, design: .monospaced))
                        Text("")
                        Text("")
                    }
                }

                if let h20 = result.stock.high20Day {
                    GridRow {
                        Text("20D High")
                            .font(.caption)
                        Text(String(format: "%.2f", h20))
                            .font(.system(.caption, design: .monospaced))
                        Text(String(format: "%.1f%% away", result.distance20DayPercent))
                            .font(.caption)
                            .foregroundColor(result.above20DayHigh ? .green : .secondary)
                        if result.above20DayHigh {
                            breakoutBadge("BREAKOUT", color: .green)
                        } else if result.breakout20Day {
                            breakoutBadge("NEAR", color: .orange)
                        }
                    }
                }
            }
        }
    }

    private func breakoutBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(color))
    }

    // MARK: - Flags

    private var flagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FLAGS")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                if result.confluence.detected {
                    flagChip("Confluence Pullback (\(result.confluence.confluenceCount))", color: .purple)
                }
                if result.volumeSpike {
                    flagChip("Volume Spike", color: .red)
                }
                if result.nearEMACount > 0 {
                    flagChip("Near EMA (\(result.nearEMACount))", color: .blue)
                }
                if result.above52WeekHigh {
                    flagChip("52W Breakout", color: .green)
                } else if result.breakout52Week {
                    flagChip("Near 52W High", color: .orange)
                }
                if result.above20DayHigh {
                    flagChip("20D Breakout", color: .teal)
                }
                if result.score == 0 {
                    Text("No flags")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func flagChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.12)))
    }

    private func formatLargeNumber(_ number: Int) -> String {
        if number >= 10_000_000 {
            return String(format: "%.2f Cr", Double(number) / 10_000_000)
        } else if number >= 100_000 {
            return String(format: "%.2f L", Double(number) / 100_000)
        } else if number >= 1000 {
            return String(format: "%.1f K", Double(number) / 1000)
        }
        return "\(number)"
    }
}
