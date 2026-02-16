import Foundation

struct AnalysisEngine {
    let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    // MARK: - EMA Calculation

    func computeEMA(closes: [Double], period: Int) -> Double? {
        guard closes.count >= period else { return nil }

        let k = 2.0 / Double(period + 1)

        // Start with SMA of first `period` values
        let sma = closes.prefix(period).reduce(0, +) / Double(period)

        // Then apply EMA formula for remaining values
        var ema = sma
        for i in period..<closes.count {
            ema = (closes[i] * k) + (ema * (1 - k))
        }

        return ema
    }

    // MARK: - Volume Analysis

    func compute20DayAvgVolume(candles: [Candle]) -> Double? {
        let recent = candles.suffix(20)
        guard recent.count >= 10 else { return nil } // need at least 10 days
        let total = recent.reduce(0) { $0 + Double($1.volume) }
        return total / Double(recent.count)
    }

    func volumeSpikeMultiplier(currentVolume: Int, avgVolume: Double) -> Double {
        guard avgVolume > 0 else { return 0 }
        return Double(currentVolume) / avgVolume
    }

    // MARK: - EMA Proximity

    func checkEMAProximity(currentPrice: Double, emaValue: Double, period: Int) -> EMAProximity {
        guard emaValue > 0 else {
            return EMAProximity(period: period, emaValue: 0, distancePercent: 0, isNear: false)
        }
        let distance = ((currentPrice - emaValue) / emaValue) * 100
        let isNear = abs(distance) <= settings.emaProximityPercent
        return EMAProximity(period: period, emaValue: emaValue, distancePercent: distance, isNear: isNear)
    }

    // MARK: - Breakout Detection

    func compute52WeekHigh(candles: [Candle]) -> Double? {
        let oneYearCandles = candles.suffix(252)
        guard !oneYearCandles.isEmpty else { return nil }
        return oneYearCandles.map(\.high).max()
    }

    func compute52WeekLow(candles: [Candle]) -> Double? {
        let oneYearCandles = candles.suffix(252)
        guard !oneYearCandles.isEmpty else { return nil }
        return oneYearCandles.map(\.low).min()
    }

    func compute20DayHigh(candles: [Candle]) -> Double? {
        let recent = candles.suffix(20)
        guard !recent.isEmpty else { return nil }
        return recent.map(\.high).max()
    }

    // MARK: - EMA Series (for slope calculation)

    /// Returns EMA values for the last `count` candles
    func computeEMASeries(closes: [Double], period: Int, lastN: Int = 10) -> [Double] {
        guard closes.count >= period + lastN else { return [] }

        let k = 2.0 / Double(period + 1)
        let sma = closes.prefix(period).reduce(0, +) / Double(period)

        var ema = sma
        var series: [Double] = []
        for i in period..<closes.count {
            ema = (closes[i] * k) + (ema * (1 - k))
            let fromEnd = closes.count - i
            if fromEnd <= lastN {
                series.append(ema)
            }
        }
        return series
    }

    /// EMA slope as % change over last N days
    func emaSlope(series: [Double]) -> Double {
        guard series.count >= 2, let first = series.first, first > 0 else { return 0 }
        let last = series.last!
        return ((last - first) / first) * 100
    }

    // MARK: - Confluence Pullback Detection

    /// Detect: stock broke above major level recently, pulled back to a rising EMA
    func detectConfluencePullback(
        candles: [Candle],
        currentPrice: Double,
        ema20: Double?,
        ema50: Double?,
        closes: [Double]
    ) -> ConfluencePullback {
        let noResult = ConfluencePullback(
            detected: false, breakoutLevel: 0, breakoutLevelType: "",
            recentHigh: 0, pullbackToEMA: nil, pullbackPercent: 0,
            emaRising: false, emaSlopePercent: 0, breakoutLevelDistance: 0,
            daysSinceBreakout: 0
        )

        guard candles.count >= 252 else { return noResult }

        let total = candles.count
        let lookback = settings.confluenceLookbackDays

        // --- Step 1: Find the major resistance level ---
        // Look at the high BEFORE the last N days as the "prior resistance"
        let priorCandles = Array(candles.prefix(total - lookback))
        guard !priorCandles.isEmpty else { return noResult }

        let priorHigh = priorCandles.map(\.high).max() ?? 0
        guard priorHigh > 0 else { return noResult }

        // Also check 52W high excluding last N days
        let older252 = candles.count >= (252 + lookback) ? Array(candles[(total - 252)..<(total - lookback)]) : priorCandles.suffix(252)
        let prior52WH = older252.map(\.high).max() ?? priorHigh

        // Use the higher of the two as the breakout level
        let breakoutLevel = max(priorHigh, prior52WH)

        // --- Step 2: Did the stock break above this level in the last N days? ---
        let recentCandles = Array(candles.suffix(lookback))
        let recentHigh = recentCandles.map(\.high).max() ?? 0
        let brokeAbove = recentHigh > breakoutLevel * 1.005 // at least 0.5% above to confirm breakout

        guard brokeAbove else { return noResult }

        // Find how many days ago the breakout high occurred
        let last60Highs = recentCandles.map(\.high)
        let daysSinceHigh = last60Highs.count - 1 - (last60Highs.lastIndex(of: recentHigh) ?? 0)

        // --- Step 3: Has it pulled back? ---
        // Current price should be below the recent high (meaningful pullback)
        let pullbackPct = ((recentHigh - currentPrice) / recentHigh) * 100
        guard pullbackPct >= settings.confluenceMinPullbackPercent else { return noResult }
        guard pullbackPct <= settings.confluenceMaxPullbackPercent else { return noResult } // too deep = trend broken

        // --- Step 4: Is the pullback landing on EMA 20 or 50? ---
        let proximityThreshold = settings.emaProximityPercent
        var pullbackEMA: Int? = nil

        if let ema = ema20 {
            let dist = abs((currentPrice - ema) / ema) * 100
            if dist <= proximityThreshold {
                pullbackEMA = 20
            }
        }
        if pullbackEMA == nil, let ema = ema50 {
            let dist = abs((currentPrice - ema) / ema) * 100
            if dist <= proximityThreshold {
                pullbackEMA = 50
            }
        }

        guard pullbackEMA != nil else { return noResult }

        // --- Step 5: Is the EMA rising? ---
        let emaPeriod = pullbackEMA!
        let emaSeries = computeEMASeries(closes: closes, period: emaPeriod, lastN: 10)
        let slope = emaSlope(series: emaSeries)
        let isRising = slope > 0.3 // EMA must be rising at least 0.3% over last 10 days

        // --- Step 6: How close is the breakout level (old resistance = new support)? ---
        let breakoutDist = ((currentPrice - breakoutLevel) / breakoutLevel) * 100

        // Determine breakout level type
        let levelType: String
        if abs(breakoutLevel - prior52WH) / prior52WH < 0.02 {
            levelType = "52W High"
        } else {
            levelType = "Prior Swing High"
        }

        return ConfluencePullback(
            detected: true,
            breakoutLevel: breakoutLevel,
            breakoutLevelType: levelType,
            recentHigh: recentHigh,
            pullbackToEMA: pullbackEMA,
            pullbackPercent: pullbackPct,
            emaRising: isRising,
            emaSlopePercent: slope,
            breakoutLevelDistance: breakoutDist,
            daysSinceBreakout: daysSinceHigh
        )
    }

    // MARK: - Full Analysis

    func analyze(stock: Stock) -> ScanResult {
        let closes = stock.dailyCandles.map(\.close)

        // EMAs
        let ema20 = computeEMA(closes: closes, period: 20)
        let ema50 = computeEMA(closes: closes, period: 50)
        let ema100 = computeEMA(closes: closes, period: 100)
        let ema200 = computeEMA(closes: closes, period: 200)

        // Volume
        let avgVol = compute20DayAvgVolume(candles: stock.dailyCandles)
        let volMultiplier = avgVol.map { volumeSpikeMultiplier(currentVolume: stock.currentVolume, avgVolume: $0) } ?? 0
        let isVolumeSpike = volMultiplier >= settings.volumeMultiplier

        // EMA proximity
        var proximities: [EMAProximity] = []
        if let ema = ema20 { proximities.append(checkEMAProximity(currentPrice: stock.currentPrice, emaValue: ema, period: 20)) }
        if let ema = ema50 { proximities.append(checkEMAProximity(currentPrice: stock.currentPrice, emaValue: ema, period: 50)) }
        if let ema = ema100 { proximities.append(checkEMAProximity(currentPrice: stock.currentPrice, emaValue: ema, period: 100)) }
        if let ema = ema200 { proximities.append(checkEMAProximity(currentPrice: stock.currentPrice, emaValue: ema, period: 200)) }

        // 52-week
        let high52 = compute52WeekHigh(candles: stock.dailyCandles)
        let low52 = compute52WeekLow(candles: stock.dailyCandles)
        var dist52: Double = 0
        var near52 = false
        var above52 = false
        if let h52 = high52, h52 > 0 {
            dist52 = ((h52 - stock.currentPrice) / h52) * 100
            near52 = dist52 <= settings.breakout52WeekPercent && dist52 >= 0
            above52 = stock.currentPrice > h52
        }

        // 20-day high
        let high20 = compute20DayHigh(candles: stock.dailyCandles)
        var near20 = false
        var above20 = false
        var dist20: Double = 0
        if let h20 = high20, h20 > 0 {
            dist20 = ((h20 - stock.currentPrice) / h20) * 100
            near20 = dist20 <= 2.0 && dist20 >= 0
            above20 = stock.currentPrice > h20
        }

        // Confluence pullback
        let confluence = detectConfluencePullback(
            candles: stock.dailyCandles,
            currentPrice: stock.currentPrice,
            ema20: ema20,
            ema50: ema50,
            closes: closes
        )

        return ScanResult(
            id: stock.id,
            stock: Stock(
                id: stock.id,
                instrumentToken: stock.instrumentToken,
                name: stock.name,
                exchange: stock.exchange,
                dailyCandles: stock.dailyCandles,
                currentPrice: stock.currentPrice,
                currentVolume: stock.currentVolume,
                dayOpen: stock.dayOpen,
                dayHigh: stock.dayHigh,
                dayLow: stock.dayLow,
                dayClose: stock.dayClose,
                previousClose: stock.previousClose,
                ema20: ema20,
                ema50: ema50,
                ema100: ema100,
                ema200: ema200,
                avgVolume20: avgVol,
                high52Week: high52,
                low52Week: low52,
                high20Day: high20
            ),
            volumeSpike: isVolumeSpike,
            volumeMultiplier: volMultiplier,
            emaProximities: proximities,
            breakout52Week: near52 || above52,
            distance52WeekPercent: dist52,
            above52WeekHigh: above52,
            breakout20Day: near20 || above20,
            above20DayHigh: above20,
            distance20DayPercent: dist20,
            confluence: confluence
        )
    }
}
