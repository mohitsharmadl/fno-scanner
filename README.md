# FnO Scanner

A native macOS SwiftUI app that scans all ~200 NSE F&O stocks in real-time and flags high-probability trading setups.

<img width="800" alt="FnO Scanner" src="https://img.shields.io/badge/platform-macOS%2014+-blue?style=flat-square&logo=apple"> <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift"> <img alt="License" src="https://img.shields.io/badge/license-MIT-green?style=flat-square">

## What It Does

Connects to your Zerodha Kite account and scans every F&O stock for:

| Scanner | What It Finds |
|---------|--------------|
| **Confluence Pullback** | Stock broke above major resistance (52W high / swing high), pulled back to a rising EMA 20/50 where old resistance = new support. The highest-conviction setup. |
| **Volume Spikes** | Today's volume is irrationally high vs 20-day average (configurable, default 2x) |
| **Near Key EMAs** | Price is within configurable % of EMA 20/50/100/200 |
| **Breakout Candidates** | Near 52-week high or breaking above 20-day high |

Each stock gets a **relevance score** — confluence pullbacks score highest and float to the top.

## Architecture

```
┌─────────────────────────────────────────┐
│         SwiftUI Mac App (.app)          │
├──────────┬───────────┬──────────────────┤
│  Views   │ ViewModels │    Services     │
│          │           │                  │
│ MainView │ Scanner   │ KiteAuthService  │
│ Table    │ ViewModel │ KiteAPIService   │
│ Detail   │           │ AnalysisEngine   │
│ Settings │           │ ScannerService   │
└──────────┴───────────┴──────────────────┘
                │
        URLSession (HTTPS)
                │
         Kite REST API
```

**Pure Swift** — no Python backend, no Electron. Calls Kite API directly.

## Project Structure

```
FnOScanner/
├── FnOScannerApp.swift              # App entry point
├── Models/
│   ├── Stock.swift                  # Stock with OHLCV, EMAs, flags
│   ├── ScanResult.swift             # Volume/EMA/breakout/confluence flags
│   └── AppSettings.swift            # Configurable thresholds (@AppStorage)
├── Services/
│   ├── KiteAuthService.swift        # OAuth login → access_token
│   ├── KiteAPIService.swift         # REST client (instruments, quotes, historical)
│   ├── AnalysisEngine.swift         # EMA calc, volume, breakout, confluence detection
│   └── ScannerService.swift         # Orchestrator: fetch → analyze → score
├── ViewModels/
│   └── ScannerViewModel.swift       # State management, filters, auto-refresh
├── Views/
│   ├── MainView.swift               # NavigationSplitView + login sheet
│   ├── ScanResultsTable.swift       # Sortable table with color-coded columns
│   ├── StockDetailView.swift        # Deep-dive panel with confluence analysis
│   ├── SettingsView.swift           # Threshold config + API credentials
│   └── LoginView.swift              # Kite auth status
└── Resources/
    └── fno_stocks.json              # Fallback FnO stock list (~200 stocks)
```

## Confluence Pullback Detection

The highest-value scanner. Detects the classic **breakout → retest → bounce** pattern:

```
                    ╭── Recent High (breakout)
                   ╱
                  ╱
     ───────────╱────── Old Resistance (now support)
               ╱
              ╱        ← You are here: pullback to EMA + support
    EMA 20 ──╱─────────────────
            ╱
```

**Algorithm:**
1. Finds the prior major resistance (highest high before last 60 days)
2. Checks if stock broke above it recently
3. Confirms a 2-20% pullback from breakout high
4. Verifies price is sitting on EMA 20 or 50
5. Checks EMA slope is positive (uptrend intact)
6. Scores confluence: breakout + EMA support + rising trend + old resistance nearby

**Confluence dots (1-4):**
- Breakout confirmed
- EMA support (dynamic)
- EMA trending up
- Old resistance within 3% (double support)

## Setup

### Prerequisites

- macOS 14.0+ (Sonoma)
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Zerodha Kite Connect API credentials

### Build

```bash
git clone https://github.com/mohitsharmadl/fno-scanner.git
cd fno-scanner
xcodegen generate
open FnOScanner.xcodeproj
# Build and run (Cmd+R)
```

### Configure

1. **Settings → Kite API tab** → Enter your API Key and Secret
2. **Login** → Authenticate with Kite (token expires daily)
3. **Scan** → Takes ~70s first time (fetching 300 days of history for ~200 stocks)

### Automated Login (Optional)

For daily automated token refresh, see the companion [fno-scanner-data](https://github.com/mohitsharmadl/fno-scanner-data) repo.

## Configurable Settings

| Setting | Default | Description |
|---------|---------|-------------|
| EMA Proximity % | 1.5% | How close to an EMA to flag it |
| Volume Multiplier | 2.0x | Minimum volume spike to flag |
| 52W Breakout % | 5.0% | How close to 52-week high to flag |
| Confluence Lookback | 60 days | How far back to search for breakout |
| Min Pullback | 2.0% | Minimum pullback from high |
| Max Pullback | 20.0% | Maximum pullback (beyond = trend broken) |
| Auto Refresh | 15 min | Refresh interval during market hours |

## Tech Stack

| Component | Choice | Why |
|-----------|--------|-----|
| UI | SwiftUI | Native macOS, fast, no Electron overhead |
| Networking | URLSession | Built-in, no dependencies |
| Crypto | CryptoKit | SHA256 for Kite checksum |
| Auth | ASWebAuthenticationSession | System browser OAuth |
| Storage | @AppStorage / UserDefaults | Simple key-value for settings |
| Project | XcodeGen | YAML → .xcodeproj, no merge conflicts |

**Zero external dependencies.** Pure Apple frameworks only.

## Kite API Usage

- **Instruments**: `GET /instruments/NFO` → extract ~200 FnO stock names
- **Quotes**: `GET /quote?i=NSE:RELIANCE&...` → batch up to 500 symbols
- **Historical**: `GET /instruments/historical/{token}/day` → 300 days per stock
- Rate limited to ~3 req/sec (built-in throttling with 0.35s delay)
- Historical data cached in-memory, refreshed daily

## License

MIT
