# forexeaEURJPY — EUR/JPY Expert Advisor

A MetaTrader 5 Expert Advisor (EA) implementing a trend-following strategy for the EUR/JPY currency pair.

## Strategy Overview

The EA combines two classic technical indicators into a rules-based system:

| Component | Details |
|-----------|---------|
| **Trend signal** | EMA 20 / EMA 50 crossover on the H1 timeframe |
| **Entry filter** | RSI(14) — avoids buying into overbought conditions and selling into oversold conditions |
| **Stop Loss** | ATR(14) × 1.5 multiplier (dynamic, adapts to volatility) |
| **Take Profit** | ATR(14) × 2.5 multiplier (≈ 1 : 1.67 risk-reward) |
| **Position sizing** | Percentage-of-balance risk (default 1% per trade) |

### Entry Rules

**BUY** when (on bar close):
1. Fast EMA (20) crosses **above** Slow EMA (50)
2. RSI is **below** 70 (not overbought)

**SELL** when (on bar close):
1. Fast EMA (20) crosses **below** Slow EMA (50)
2. RSI is **above** 30 (not oversold)

Any existing opposite position is closed before a new trade is opened.

### Trade Management

- **Break-even**: Once price moves 1 × ATR in profit the stop loss is moved to entry + 1 pip.
- **Trailing stop**: Stop loss trails price by 1 × ATR as the trade moves further into profit.
- Both features can be toggled independently via input parameters.

### Session Filter

By default the EA only trades between **07:00 – 20:00 server time** to avoid the thin Asian overnight session. Adjust `SessionStartHour` and `SessionEndHour` as required, or disable the filter entirely.

---

## Installation

1. Copy `EURJPY_EA.mq5` to your MetaTrader 5 **Experts** folder:
   ```
   %APPDATA%\MetaQuotes\Terminal\<terminal-id>\MQL5\Experts\
   ```
2. Open MetaEditor, compile the file (`F7`), and verify there are no errors.
3. In MetaTrader 5, drag the EA onto an **EURJPY H1** chart.
4. Enable **Algo Trading** (the green button in the toolbar).

---

## Input Parameters

### Strategy Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| `FastEMA_Period` | 20 | Period of the fast Exponential Moving Average |
| `SlowEMA_Period` | 50 | Period of the slow Exponential Moving Average |
| `RSI_Period` | 14 | RSI calculation period |
| `RSI_Overbought` | 70 | RSI level above which buy entries are blocked |
| `RSI_Oversold` | 30 | RSI level below which sell entries are blocked |

### Risk Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| `RiskPercent` | 1.0 | Account balance percentage risked per trade |
| `ATR_SL_Mult` | 1.5 | ATR multiplier applied to the stop loss distance |
| `ATR_TP_Mult` | 2.5 | ATR multiplier applied to the take profit distance |
| `ATR_Period` | 14 | ATR calculation period |
| `MaxLotSize` | 10.0 | Hard cap on position size (lots) |
| `MinLotSize` | 0.01 | Minimum allowable position size (lots) |

### Trade Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| `UseBreakEven` | true | Move stop to break-even once profit ≥ 1 × ATR |
| `BreakEvenATRMult` | 1.0 | ATR multiplier required to trigger break-even |
| `UseTrailingStop` | true | Activate trailing stop |
| `TrailingATRMult` | 1.0 | ATR distance behind price for the trailing stop |

### Session Filter
| Parameter | Default | Description |
|-----------|---------|-------------|
| `UseSessionFilter` | true | Restrict trading to session hours |
| `SessionStartHour` | 7 | First hour trades may be opened (server time) |
| `SessionEndHour` | 20 | Last hour trades may be opened (server time) |

### General
| Parameter | Default | Description |
|-----------|---------|-------------|
| `MagicNumber` | 20241001 | Unique identifier for EA orders |
| `TradeComment` | EURJPY_EA | Comment attached to orders |
| `FillType` | ORDER_FILLING_IOC | Order fill type (`IOC`, `FOK`, or `RETURN`) — adjust to match your broker |

---

## Backtesting

1. Open the **Strategy Tester** (`Ctrl+R`).
2. Select `EURJPY_EA` as the Expert Advisor.
3. Set the symbol to **EURJPY**, timeframe **H1**.
4. Choose **Every tick based on real ticks** for the most accurate results.
5. Adjust the date range and click **Start**.

---

## Disclaimer

This software is provided for educational purposes only. Past performance is not indicative of future results. Trading foreign exchange on margin carries a high level of risk and may not be suitable for all investors. Always test thoroughly on a demo account before deploying on a live account.
