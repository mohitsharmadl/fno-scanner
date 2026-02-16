# FOR-Mohit: FnO Scanner — Native macOS App

## What Is This?

A native macOS SwiftUI app that scans all ~200 NSE F&O stocks and flags interesting ones based on three criteria:

1. **Volume spikes** — today's volume is irrationally high vs 20-day average (like 3x normal)
2. **Near key EMAs** — price is hugging EMA 20/50/100/200 (potential support/resistance)
3. **Breakout candidates** — near 52-week high or breaking above 20-day high

Think of it as a personal screener that runs on your Mac, using your Kite credentials, with zero cloud dependency.

## How It Works (The Big Picture)

```
You click "Scan"
    ↓
App calls Kite API → fetches ~200 FnO stock names from NFO instruments
    ↓
Batch-fetches live quotes (price, volume) for all stocks
    ↓
Fetches 300 days of historical daily data per stock (throttled at 3 req/sec)
    ↓
Runs analysis: computes EMAs, checks volume spikes, detects breakouts
    ↓
Scores and ranks stocks → shows in a sortable table
```

The whole scan takes ~70 seconds because of Kite's rate limit (200 stocks × 0.35s each for historical data). Results are cached, so subsequent scans within the same day are much faster.

## Project Structure

```
~/github/fno-scanner/
├── project.yml                 ← XcodeGen spec (generates .xcodeproj)
├── FnOScanner/
│   ├── FnOScannerApp.swift     ← App entry point
│   ├── Models/
│   │   ├── Stock.swift         ← Stock data model with OHLCV, EMAs
│   │   ├── ScanResult.swift    ← Flags: volume spike, EMA proximity, breakout
│   │   └── AppSettings.swift   ← @AppStorage settings + Keychain helper
│   ├── Services/
│   │   ├── KiteAuthService.swift   ← OAuth login via ASWebAuthenticationSession
│   │   ├── KiteAPIService.swift    ← REST client (instruments, quotes, historical)
│   │   ├── AnalysisEngine.swift    ← EMA calc, volume analysis, breakout detection
│   │   └── ScannerService.swift    ← Orchestrator: fetch → analyze → score
│   ├── ViewModels/
│   │   └── ScannerViewModel.swift  ← Holds state, filters, triggers scans
│   ├── Views/
│   │   ├── MainView.swift          ← NavigationSplitView (sidebar + table + detail)
│   │   ├── ScanResultsTable.swift  ← Sortable table with color-coded columns
│   │   ├── StockDetailView.swift   ← Deep-dive panel for selected stock
│   │   ├── SettingsView.swift      ← Configurable thresholds + API credentials
│   │   └── LoginView.swift         ← Kite auth status + login button
│   └── Resources/
│       └── fno_stocks.json         ← Fallback FnO stock list (~200 stocks)
```

## Tech Decisions

- **Pure Swift + SwiftUI** — no Python backend, no Electron. Native macOS app, snappy UI.
- **XcodeGen** — project.yml generates the .xcodeproj. No checking in Xcode project files.
- **Keychain** for credentials — API key, secret, and access token stored securely.
- **ASWebAuthenticationSession** for Kite OAuth — system browser-based login, captures callback.
- **Actor-based API service** — `KiteAPIService` is an actor for safe concurrent access with built-in rate limiting.
- **CryptoKit** for SHA256 checksum — needed for Kite token exchange.

## Key Concepts

### Kite Auth Flow
1. User clicks "Login" → opens `kite.trade/connect/login?api_key=XXX` in a browser
2. After login, Kite redirects to `fnoscanner://callback?request_token=YYY`
3. App catches the redirect, exchanges request_token for access_token via POST
4. Token stored in Keychain, valid until midnight IST

### EMA Calculation
```
EMA = (Price × k) + (Previous_EMA × (1 - k))
where k = 2 / (period + 1)
```
We start with an SMA (simple average) of the first N values, then apply the EMA formula forward.

### Scoring
Each stock gets a relevance score:
- Volume spike: +1
- Near each EMA: +1 per EMA
- Near 52-week high: +2
- Above 52-week high (actual breakout!): +1 bonus
- 20-day range breakout: +1

Higher score = more interesting stock.

## How to Use

1. Open in Xcode (or `open FnOScanner.xcodeproj`)
2. Go to Settings → Kite API tab → enter API key + secret
3. Click "Login" in toolbar → authenticate in browser
4. Click "Scan" → wait ~70s for first scan
5. Use sidebar filters: Volume Spikes / Near EMA / Breakouts
6. Click any stock for detailed analysis

## Settings You Can Tweak

| Setting | Default | What It Does |
|---------|---------|-------------|
| EMA Proximity % | 1.5% | How close to an EMA to flag it |
| Volume Multiplier | 2.0x | Minimum spike to flag volume |
| 52W Breakout % | 5.0% | How close to 52-week high to flag |
| Auto Refresh | 15 min | Refresh interval during market hours |

## Lessons Learned

- **XcodeGen overwrites entitlements** — need to specify entitlements properties in project.yml, not maintain a separate file manually
- **Kite API rate limit** is ~3 req/sec for historical data — built a serial queue with 0.35s delay
- **Kite quotes return `ohlc.close` as previous day's close**, not today's — important for % change calculation
- **52-week high/low isn't in the quotes endpoint** — have to compute from 252 days of historical data
- **`ASWebAuthenticationSession` needs a presentation anchor** on macOS — use `NSApplication.shared.keyWindow`
- **SwiftUI Table on macOS** requires macOS 13+ and works well for sortable data grids

## If I Had to Rebuild This...

- Would add **persistent storage** (Core Data or SQLite) for historical candle cache so it survives app restarts
- Would add a **mini chart** (sparkline) in the table for quick visual
- Could add **WebSocket streaming** for real-time prices instead of polling
- The fallback `fno_stocks.json` should be auto-updated periodically
