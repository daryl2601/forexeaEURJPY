# forexeaEURJPY

## EURJPY H1 Mathematical Model Expert Advisor (MT5)

A MetaTrader 5 Expert Advisor implementing a sophisticated statistical/linear-regression trading model for the **EURJPY** currency pair on the **H1 (1-hour)** timeframe.

---

## Mathematical Model

The EA is built around a multi-day statistical model using the following variables and formulas:

### Regression Anchors
- Primary:   (350, 175.679618) and (360, 180.427674)
- Secondary: 173.282 / 174.352 and 176.368 / 177.490

### Core Variables

| Variable | Formula |
|----------|---------|
| **P** | `(MA_hour(0) ÷ MA_hour(9)) + 0.03` |
| **Q** | `((High(9) + High(7)) ÷ 2 + MA_hour(0) + 10.00) − 5.00` |
| **a** | Open of hour(0) — two trading days ago |
| **b** | High of hour(0) — two trading days ago |
| **C** | `((Low(0)₋₂ − 0.2 + Low(2)₋₂) ÷ 2 + P₋₂ − 1.44) ÷ 2 + 0.144` |
| **d** | `((((Open(0)₋₂ + High(0)₋₂) ÷ 2 + Q₋₃ − 0.3) ÷ 2 + P₋₃ ÷ 2 + HighestHigh(0–9)₋₂ − 1.44) ÷ 2` |
| **e** | `(((Low(0)₋₁ + Low(1)₋₁) ÷ 2 + Low(2)₋₁) ÷ 2 + HighestHigh(0–9)₋₁ − 1.44) ÷ 2 + 0.044` |
| **F** | `min(Low_hour(9) today, Low_hour(9) one day ago)` |

### Entry Levels

| Signal | Formula |
|--------|---------|
| **Sell Stop** | `(((a + b + C) / 2 + 0.1 + d) / 2 + e) / 2 + sf) / 6` → simplified: `((((a+b+C)/2 + 0.1 + d)/2 + e)/2 + sf) / 6` |
| **Buy Stop**  | `P(today) × MA_hour(9) − F × pipSize` (converts P ratio to price, then applies F floor offset) |

---

## EA File

`EURJPY_H1_EA.mq5` — Place this file in your MetaTrader 5 **MQL5/Experts/** directory.

---

## Default Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Lot Size | 0.5 | Position size |
| Pip Value | 10 pips | Pip consideration |
| Stop Loss | 50 pips | SL in pips |
| Take Profit | 100 pips | TP in pips |
| MA Period | 9 | Moving average period for P/Q |
| Magic Number | 202601 | Unique EA identifier |
| Buy Offset | 0.03 | P formula offset |
| Reg Adjustment | 1.44 | Regression constant |
| C Adjustment | 0.144 | C formula final adjustment |
| e Adjustment | 0.044 | e formula final adjustment |
| Max Spread | 3.0 pips | Skip trading if spread exceeds this |
| Max Positions | 1 | Maximum simultaneous open trades |

All parameters are configurable from the MetaTrader 5 EA input panel.

---

## Installation

1. Copy `EURJPY_H1_EA.mq5` to `<MT5_Data_Folder>/MQL5/Experts/`
2. Open MetaEditor and compile the file (F7)
3. Attach the compiled EA to an **EURJPY H1** chart
4. Configure input parameters as desired
5. Enable **AutoTrading** in MetaTrader 5

---

## Requirements

- MetaTrader 5 (build 2755 or later recommended)
- EURJPY symbol available from your broker
- H1 historical data (at least 5 trading days for initialisation)
- AutoTrading enabled

---

## Disclaimer

This EA is provided for educational and research purposes. Past performance does not guarantee future results. Always test on a demo account before trading live capital.
