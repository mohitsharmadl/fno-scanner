import SwiftUI

struct ScanResultsTable: View {
    @EnvironmentObject var viewModel: ScannerViewModel
    @State private var sortOrder = [KeyPathComparator(\ScanResult.score, order: .reverse)]

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.filteredResults.isEmpty && !viewModel.isScanning {
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    if viewModel.scanResults.isEmpty {
                        Text("Click Scan to fetch FnO stock data")
                    } else {
                        Text("No stocks match the current filter")
                    }
                }
            } else {
                Table(viewModel.filteredResults, selection: Binding(
                    get: { viewModel.selectedStock?.id },
                    set: { id in
                        viewModel.selectedStock = viewModel.filteredResults.first { $0.id == id }
                    }
                ), sortOrder: $sortOrder) {
                    TableColumn("Symbol", value: \.stock.id) { result in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.stock.id)
                                .font(.system(.body, design: .monospaced, weight: .semibold))
                            Text(result.stock.name)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .width(min: 100, ideal: 120)

                    TableColumn("Price") { result in
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(formatPrice(result.stock.currentPrice))
                                .font(.system(.body, design: .monospaced))
                            Text(formatChange(result.priceChange))
                                .font(.caption2)
                                .foregroundColor(result.priceChange >= 0 ? .green : .red)
                        }
                    }
                    .width(min: 80, ideal: 90)

                    TableColumn("Volume") { result in
                        Text(formatVolume(result.stock.currentVolume))
                            .font(.system(.caption, design: .monospaced))
                    }
                    .width(min: 70, ideal: 80)

                    TableColumn("Vol Spike") { result in
                        if result.volumeSpike {
                            Text(String(format: "%.1fx", result.volumeMultiplier))
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(spikeColor(result.volumeMultiplier)))
                        } else if result.volumeMultiplier > 1.0 {
                            Text(String(format: "%.1fx", result.volumeMultiplier))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        } else {
                            Text("-")
                                .foregroundColor(.secondary)
                        }
                    }
                    .width(min: 60, ideal: 70)

                    TableColumn("Near EMA") { result in
                        if result.nearEMACount > 0 {
                            Text(result.nearEMASummary)
                                .font(.caption2)
                                .foregroundColor(.blue)
                                .lineLimit(2)
                        } else {
                            Text("-")
                                .foregroundColor(.secondary)
                        }
                    }
                    .width(min: 120, ideal: 180)

                    TableColumn("Confluence") { result in
                        if result.confluence.detected {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(result.confluence.summary)
                                    .font(.caption2)
                                    .foregroundColor(.purple)
                                    .lineLimit(2)
                                HStack(spacing: 2) {
                                    ForEach(0..<result.confluence.confluenceCount, id: \.self) { _ in
                                        Circle().fill(Color.purple).frame(width: 5, height: 5)
                                    }
                                }
                            }
                        } else {
                            Text("-")
                                .foregroundColor(.secondary)
                        }
                    }
                    .width(min: 130, ideal: 170)

                    TableColumn("Breakout") { result in
                        if result.breakout52Week || result.breakout20Day {
                            Text(result.breakoutSummary)
                                .font(.caption2)
                                .foregroundColor(result.above52WeekHigh ? .green : .orange)
                                .lineLimit(2)
                        } else {
                            Text("-")
                                .foregroundColor(.secondary)
                        }
                    }
                    .width(min: 100, ideal: 130)

                    TableColumn("Score", value: \.score) { result in
                        HStack(spacing: 2) {
                            Text("\(result.score)")
                                .font(.system(.body, design: .rounded, weight: .bold))
                                .foregroundColor(scoreColor(result.score))
                            if result.score > 0 {
                                ForEach(0..<min(result.score, 5), id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 6))
                                        .foregroundColor(.yellow)
                                }
                            }
                        }
                    }
                    .width(min: 60, ideal: 80)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private func formatPrice(_ price: Double) -> String {
        if price >= 1000 {
            return String(format: "%.1f", price)
        }
        return String(format: "%.2f", price)
    }

    private func formatChange(_ change: Double) -> String {
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", change))%"
    }

    private func formatVolume(_ volume: Int) -> String {
        if volume >= 10_000_000 {
            return String(format: "%.1fCr", Double(volume) / 10_000_000)
        } else if volume >= 100_000 {
            return String(format: "%.1fL", Double(volume) / 100_000)
        } else if volume >= 1000 {
            return String(format: "%.1fK", Double(volume) / 1000)
        }
        return "\(volume)"
    }

    private func spikeColor(_ multiplier: Double) -> Color {
        if multiplier >= 5.0 { return .red }
        if multiplier >= 3.0 { return .orange }
        return .yellow.opacity(0.8)
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 4 { return .green }
        if score >= 2 { return .orange }
        if score >= 1 { return .blue }
        return .secondary
    }
}
