import Foundation

struct Candle: Codable, Identifiable {
    var id: Date { date }
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int
}

struct Stock: Identifiable {
    let id: String                // tradingsymbol (e.g., "RELIANCE")
    let instrumentToken: Int
    let name: String
    let exchange: String          // "NSE"
    var dailyCandles: [Candle]
    var currentPrice: Double
    var currentVolume: Int
    var dayOpen: Double?
    var dayHigh: Double?
    var dayLow: Double?
    var dayClose: Double?
    var previousClose: Double?
    var ema20: Double?
    var ema50: Double?
    var ema100: Double?
    var ema200: Double?
    var avgVolume20: Double?
    var high52Week: Double?
    var low52Week: Double?
    var high20Day: Double?
}

struct InstrumentInfo: Identifiable {
    let id: Int                   // instrument_token
    let tradingsymbol: String
    let name: String
    let exchange: String
    let instrumentToken: Int
}
