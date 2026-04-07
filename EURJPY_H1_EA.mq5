//+------------------------------------------------------------------+
//|                                               EURJPY_H1_EA.mq5  |
//|                        EURJPY H1 Mathematical Model EA           |
//|                                                                  |
//|  Based on Linear Regression / Statistical Trading Model          |
//|  Regression anchors: (350, 175.679618) and (360, 180.427674)    |
//|  Secondary stats:    173.282 / 174.352  and  176.368 / 177.490  |
//+------------------------------------------------------------------+
#property copyright "EURJPY Mathematical Model EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input Parameters
input group "===== Trading Parameters ====="
input double   InpLotSize        = 0.5;      // Lot Size
input double   InpPipValue       = 10.0;     // Pip Consideration (pips)
input double   InpStopLossPips   = 50.0;     // Stop Loss (pips)
input double   InpTakeProfitPips = 100.0;    // Take Profit (pips)
input int      InpMagicNumber    = 202601;   // Magic Number
input bool     InpEnableBuy      = true;     // Enable Buy Orders
input bool     InpEnableSell     = true;     // Enable Sell Orders

input group "===== Model Parameters ====="
input int      InpMA_Period      = 9;        // MA Period for P/Q calculations
input double   InpQ_Offset       = 5.00;     // Q formula offset (default 5.00)
input double   InpQ_AddMA        = 10.00;    // Q formula MA addition
input double   InpC_Adjust       = 0.144;    // C formula final adjustment
input double   InpC_LowAdj       = 0.2;      // C formula low adjustment
input double   InpD_Adj          = 0.3;      // d formula open/high adjustment
input double   InpE_Adjust       = 0.044;    // e formula final adjustment
input double   InpRegAdj         = 1.44;     // Regression adjustment constant
input double   InpSellSF         = 0.0;      // Sell Stop 'sf' parameter
input double   InpBuyOffset      = 0.03;     // Buy Stop P formula offset

input group "===== Risk Management ====="
input double   InpMaxSpreadPips  = 3.0;      // Maximum allowed spread (pips)
input bool     InpUseStopOrders  = true;     // Use Stop Orders (vs Market Orders)
input int      InpMaxPositions   = 1;        // Maximum open positions

input group "===== Session & Timing ====="
input bool     InpTradeOnNewBar  = true;     // Only trade on new H1 bar open
input int      InpStartHour      = 0;        // Trading start hour (server time)
input int      InpEndHour        = 23;       // Trading end hour (server time)

//--- Global Variables
CTrade         g_trade;
CPositionInfo  g_position;

datetime       g_lastBarTime = 0;
double         g_pipSize     = 0.0;
int            g_digits      = 0;

// Historical data storage (indexed by days back: 0=today, 1=1 day ago, 2=2 days ago, 3=3 days ago)
struct DayData
{
   double openH0;       // Open of hour(0)
   double highH0;       // High of hour(0)
   double lowH0;        // Low of hour(0)
   double closeH0;      // Close of hour(0)
   double openH7;       // Open of hour(7)
   double highH7;       // High of hour(7)
   double lowH7;        // Low of hour(7)
   double openH9;       // Open of hour(9)
   double highH9;       // High of hour(9)
   double lowH9;        // Low of hour(9)
   double maH0;         // MA at hour(0)
   double maH9;         // MA at hour(9)
   double lowH1;        // Low of hour(1)
   double lowH2;        // Low of hour(2)
   double highestHigh;  // Highest high over hours 0-9
   double P;            // P value for this day
   double Q;            // Q value for this day
};

DayData g_day[4]; // 0=today, 1=1 day ago, 2=2 days ago, 3=3 days ago

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate symbol
   if(Symbol() != "EURJPY")
   {
      Print("WARNING: This EA is designed for EURJPY. Current symbol: ", Symbol());
   }

   // Set pip size based on digits
   g_digits  = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   g_pipSize = (g_digits == 3 || g_digits == 5) ? 10 * Point() : Point();

   // Configure trade object
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   Print("=== EURJPY H1 Mathematical Model EA Initialized ===");
   Print("Symbol: ", Symbol(), " | Digits: ", g_digits, " | PipSize: ", g_pipSize);
   Print("LotSize: ", InpLotSize, " | PipValue: ", InpPipValue,
         " | SL: ", InpStopLossPips, " pips | TP: ", InpTakeProfitPips, " pips");

   // Pre-load historical data
   if(!CollectHistoricalData())
   {
      Print("WARNING: Could not pre-load all historical data. Will retry on first tick.");
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== EA Deinitialized. Reason: ", reason, " ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new H1 bar
   datetime currentBarTime = iTime(Symbol(), PERIOD_H1, 0);
   if(currentBarTime == g_lastBarTime && InpTradeOnNewBar)
      return;
   g_lastBarTime = currentBarTime;

   // Check trading hours
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpStartHour || dt.hour > InpEndHour)
      return;

   // Check spread
   double spreadPips = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * Point() / g_pipSize;
   if(spreadPips > InpMaxSpreadPips)
   {
      Print("Spread too wide: ", DoubleToString(spreadPips, 1), " pips. Skipping.");
      return;
   }

   // Collect fresh historical data
   if(!CollectHistoricalData())
   {
      Print("ERROR: Failed to collect historical data. Skipping bar.");
      return;
   }

   // Calculate model values
   double modelP = CalcP();          // P = today's P
   double modelQ = g_day[0].Q;       // Q = today's Q
   double modelC = CalcC();          // C (uses 2 days ago data)
   double modelD = CalcD();          // d (uses 2-3 days ago data)
   double modelE = CalcE();          // e (uses 1 day ago data)
   double modelF = CalcF();          // F = min(low[9] today, low[9] 1 day ago)

   // Retrieve a and b (open and high of hour(0) two trading days ago)
   double varA = g_day[2].openH0;    // a = open of hour(0) two trading days ago
   double varB = g_day[2].highH0;    // b = high of hour(0) two trading days ago

   // Calculate entry levels
   double sellStop = CalcSellStop(varA, varB, modelC, modelD, modelE, InpSellSF);
   double buyStop  = CalcBuyStop(modelP, modelF);

   // Log calculated values
   LogModelValues(modelP, modelQ, modelC, modelD, modelE, modelF,
                  varA, varB, sellStop, buyStop);

   // Validate calculated levels
   if(sellStop <= 0.0 || buyStop <= 0.0)
   {
      Print("WARNING: Invalid entry levels. SellStop=", sellStop, " BuyStop=", buyStop);
      return;
   }

   // Check existing positions
   int openPositions = CountOpenPositions();
   if(openPositions >= InpMaxPositions)
   {
      Print("Max positions reached (", openPositions, "). No new orders.");
      return;
   }

   // Place orders
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

   if(InpEnableSell && sellStop < bid)
   {
      PlaceSellStopOrder(sellStop);
   }

   if(InpEnableBuy && buyStop > ask)
   {
      PlaceBuyStopOrder(buyStop);
   }
}

//+------------------------------------------------------------------+
//| Collect all required historical bar data                         |
//| Fills g_day[0..3] with open/high/low/close/MA for each day      |
//+------------------------------------------------------------------+
bool CollectHistoricalData()
{
   // We need H1 bars; find bar indices for hour(0) of each trading day
   // "Today" means the current day; we look for bar at midnight (hour 0)
   // of today, yesterday, 2 days ago, 3 days ago

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   // Build target dates
   datetime targetDays[4];
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00",
                                              now.year, now.mon, now.day));
   targetDays[0] = today;

   // Walk back, skipping weekends
   int daysFound = 1;
   for(int back = 1; daysFound < 4 && back <= 14; back++)
   {
      datetime candidate = today - back * 86400;
      MqlDateTime cdt;
      TimeToStruct(candidate, cdt);
      // Skip Saturday (6) and Sunday (0)
      if(cdt.day_of_week == 0 || cdt.day_of_week == 6)
         continue;
      targetDays[daysFound] = candidate;
      daysFound++;
   }

   if(daysFound < 4)
   {
      Print("WARNING: Could not locate 4 trading days of history.");
      return false;
   }

   // For each day, collect hourly bar data
   for(int day = 0; day < 4; day++)
   {
      datetime dayStart = targetDays[day];

      // Locate H1 bar index for hour 0 of this day
      int barH0 = FindBarAtTime(dayStart + 0 * 3600);
      int barH1 = FindBarAtTime(dayStart + 1 * 3600);
      int barH2 = FindBarAtTime(dayStart + 2 * 3600);
      int barH7 = FindBarAtTime(dayStart + 7 * 3600);
      int barH9 = FindBarAtTime(dayStart + 9 * 3600);

      if(barH0 < 0 || barH9 < 0)
      {
         Print("WARNING: Cannot find H1 bars for day ", day, " (", TimeToString(dayStart), ")");
         // Zero out the day's data
         ZeroMemory(g_day[day]);
         continue;
      }

      // Fill basic OHLC
      g_day[day].openH0  = iOpen (Symbol(), PERIOD_H1, barH0);
      g_day[day].highH0  = iHigh (Symbol(), PERIOD_H1, barH0);
      g_day[day].lowH0   = iLow  (Symbol(), PERIOD_H1, barH0);
      g_day[day].closeH0 = iClose(Symbol(), PERIOD_H1, barH0);

      g_day[day].lowH1   = (barH1 >= 0) ? iLow(Symbol(), PERIOD_H1, barH1) : g_day[day].lowH0;
      g_day[day].lowH2   = (barH2 >= 0) ? iLow(Symbol(), PERIOD_H1, barH2) : g_day[day].lowH0;

      g_day[day].highH7  = (barH7 >= 0) ? iHigh(Symbol(), PERIOD_H1, barH7) : 0.0;
      g_day[day].openH7  = (barH7 >= 0) ? iOpen(Symbol(), PERIOD_H1, barH7) : 0.0;
      g_day[day].lowH7   = (barH7 >= 0) ? iLow (Symbol(), PERIOD_H1, barH7) : 0.0;

      g_day[day].highH9  = (barH9 >= 0) ? iHigh(Symbol(), PERIOD_H1, barH9) : 0.0;
      g_day[day].openH9  = (barH9 >= 0) ? iOpen(Symbol(), PERIOD_H1, barH9) : 0.0;
      g_day[day].lowH9   = (barH9 >= 0) ? iLow (Symbol(), PERIOD_H1, barH9) : 0.0;

      // Calculate MA (Simple Moving Average over InpMA_Period bars) at H0 and H9
      g_day[day].maH0 = CalcSMA(barH0, InpMA_Period);
      g_day[day].maH9 = CalcSMA(barH9, InpMA_Period);

      // Highest High over hours 0 through 9
      g_day[day].highestHigh = CalcHighestHigh(dayStart, 0, 9);

      // Calculate P and Q for this day
      g_day[day].P = CalcPForDay(day);
      g_day[day].Q = CalcQForDay(day);
   }

   return true;
}

//+------------------------------------------------------------------+
//| Find H1 bar index closest to the given datetime                  |
//+------------------------------------------------------------------+
int FindBarAtTime(datetime targetTime)
{
   int shift = iBarShift(Symbol(), PERIOD_H1, targetTime, true);
   if(shift < 0)
      return -1;

   // Verify the bar time matches (within 1 hour tolerance)
   datetime barTime = iTime(Symbol(), PERIOD_H1, shift);
   if(MathAbs((double)(barTime - targetTime)) > 3600.0)
      return -1;

   return shift;
}

//+------------------------------------------------------------------+
//| Calculate Simple Moving Average at a given bar index             |
//+------------------------------------------------------------------+
double CalcSMA(int barIndex, int period)
{
   if(barIndex < 0 || period <= 0)
      return 0.0;

   double sum = 0.0;
   int count = 0;
   for(int i = barIndex; i < barIndex + period; i++)
   {
      double c = iClose(Symbol(), PERIOD_H1, i);
      if(c <= 0.0)
         break;
      sum += c;
      count++;
   }
   return (count > 0) ? sum / count : 0.0;
}

//+------------------------------------------------------------------+
//| Calculate Highest High from startHour to endHour for a given day |
//+------------------------------------------------------------------+
double CalcHighestHigh(datetime dayStart, int startHour, int endHour)
{
   double highest = 0.0;
   for(int h = startHour; h <= endHour; h++)
   {
      int bar = FindBarAtTime(dayStart + h * 3600);
      if(bar < 0)
         continue;
      double hi = iHigh(Symbol(), PERIOD_H1, bar);
      if(hi > highest)
         highest = hi;
   }
   return highest;
}

//+------------------------------------------------------------------+
//| Calculate P for a given day index                                |
//| P = ((MA of hour(0) / MA of hour(9)) + BuyOffset)               |
//+------------------------------------------------------------------+
double CalcPForDay(int dayIndex)
{
   double maH0 = g_day[dayIndex].maH0;
   double maH9 = g_day[dayIndex].maH9;

   if(maH9 == 0.0)
      return 0.0;

   return (maH0 / maH9) + InpBuyOffset;
}

//+------------------------------------------------------------------+
//| Calculate P for today (day 0)                                   |
//+------------------------------------------------------------------+
double CalcP()
{
   return CalcPForDay(0);
}

//+------------------------------------------------------------------+
//| Calculate Q for a given day index                                |
//| Q = ((High(9) + High(7)) / 2 + MA of hour(0) + Q_AddMA)        |
//|       - Q_Offset                                                 |
//+------------------------------------------------------------------+
double CalcQForDay(int dayIndex)
{
   double highH9  = g_day[dayIndex].highH9;
   double highH7  = g_day[dayIndex].highH7;
   double maH0    = g_day[dayIndex].maH0;

   return ((highH9 + highH7) / 2.0 + maH0 + InpQ_AddMA) - InpQ_Offset;
}

//+------------------------------------------------------------------+
//| Calculate C (uses 2 trading days ago data)                       |
//| C = (((Low(0)_2dAgo + Low(0)_2dAgo) / 2 - LowAdj               |
//|        + Low(2)_2dAgo) / 2 + P_2dAgo - RegAdj) / 2 + C_Adjust  |
//+------------------------------------------------------------------+
double CalcC()
{
   double low0    = g_day[2].lowH0;
   double low2    = g_day[2].lowH2;
   double p2dAgo  = g_day[2].P;

   // (Low(0) + Low(0)) / 2 = Low(0)  (averaging identical values)
   double innerAvg = (low0 + low0) / 2.0;
   double step1    = (innerAvg - InpC_LowAdj + low2) / 2.0;
   double step2    = (step1 + p2dAgo - InpRegAdj) / 2.0;
   return step2 + InpC_Adjust;
}

//+------------------------------------------------------------------+
//| Calculate d (uses 2-3 trading days ago data)                     |
//| d = ((((Open(0)_2dAgo + High(0)_2dAgo) / 2                     |
//|         + Q_3dAgo - D_Adj) / 2                                  |
//|        + P_3dAgo / 2                                             |
//|        + HighestHigh(0+9)_2dAgo - RegAdj) / 2                  |
//+------------------------------------------------------------------+
double CalcD()
{
   double open0_2d  = g_day[2].openH0;
   double high0_2d  = g_day[2].highH0;
   double q3dAgo    = g_day[3].Q;
   double p3dAgo    = g_day[3].P;
   double hhigh2d   = g_day[2].highestHigh;

   double step1 = (open0_2d + high0_2d) / 2.0;
   double step2 = (step1 + q3dAgo - InpD_Adj) / 2.0;
   double step3 = (step2 + p3dAgo / 2.0 + hhigh2d - InpRegAdj) / 2.0;
   return step3;
}

//+------------------------------------------------------------------+
//| Calculate e (uses 1 trading day ago data)                        |
//| e = (((Low(0)_1dAgo + Low(1)_1dAgo) / 2 + Low(2)_1dAgo) / 2  |
//|        + HighestHigh(0+9)_1dAgo - RegAdj) / 2 + E_Adjust       |
//+------------------------------------------------------------------+
double CalcE()
{
   double low0_1d  = g_day[1].lowH0;
   double low1_1d  = g_day[1].lowH1;
   double low2_1d  = g_day[1].lowH2;
   double hhigh1d  = g_day[1].highestHigh;

   double step1 = (low0_1d + low1_1d) / 2.0;
   double step2 = (step1 + low2_1d) / 2.0;
   double step3 = (step2 + hhigh1d - InpRegAdj) / 2.0;
   return step3 + InpE_Adjust;
}

//+------------------------------------------------------------------+
//| Calculate F                                                       |
//| F = min(low at hour(9) today, low at hour(9) one day ago)        |
//+------------------------------------------------------------------+
double CalcF()
{
   double lowH9_today    = g_day[0].lowH9;
   double lowH9_1dAgo    = g_day[1].lowH9;

   if(lowH9_today <= 0.0 && lowH9_1dAgo <= 0.0)
      return 0.0;
   if(lowH9_today <= 0.0)
      return lowH9_1dAgo;
   if(lowH9_1dAgo <= 0.0)
      return lowH9_today;

   return MathMin(lowH9_today, lowH9_1dAgo);
}

//+------------------------------------------------------------------+
//| Calculate Sell Stop                                              |
//| SellStop = ((((a + b + modelC) / 2 + 0.1 + modelD) / 2         |
//|              + modelE) / 2 + sellFactor) / 6                    |
//+------------------------------------------------------------------+
double CalcSellStop(double openH0_2d, double highH0_2d, double modelC,
                    double modelD,    double modelE,    double sellFactor)
{
   double step1 = (openH0_2d + highH0_2d + modelC) / 2.0;
   double step2 = (step1 + 0.1 + modelD) / 2.0;
   double step3 = ((step2 + modelE) / 2.0 + sellFactor) / 6.0;
   return step3;
}

//+------------------------------------------------------------------+
//| Calculate Buy Stop                                               |
//| BuyStop = P(today) × MA_hour(9) − F × pipSize                   |
//| P is a ratio (~1.0003); converting back to price requires        |
//| multiplying by MA(H9). F provides a floor offset in pip units.  |
//+------------------------------------------------------------------+
double CalcBuyStop(double P, double F)
{
   if(P <= 0.0)
      return 0.0;

   // Interpret "Buy Stop = P today - [F adjustment]"
   // Use F as a fractional pip-level offset from P
   // P is a ratio (~1.0003); scale back to price by multiplying by MA(H9)
   double maH9 = g_day[0].maH9;
   if(maH9 <= 0.0)
      return 0.0;

   double priceP = P * maH9;   // Convert ratio back to approximate price

   // Buy stop: P price level, offset downward by pip consideration
   double buyLevel = priceP - F * g_pipSize;
   return (buyLevel > 0.0) ? NormalizeDouble(buyLevel, g_digits) : 0.0;
}

//+------------------------------------------------------------------+
//| Place a Sell Stop order                                          |
//+------------------------------------------------------------------+
void PlaceSellStopOrder(double price)
{
   double sl = 0.0, tp = 0.0;
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

   price = NormalizeDouble(price, g_digits);

   // Validate: sell stop must be below current bid
   if(price >= bid)
   {
      Print("SellStop price (", price, ") >= Bid (", bid, "). Adjusting to market sell.");
      // Place market sell instead
      sl = (InpStopLossPips > 0)   ? NormalizeDouble(bid + InpStopLossPips * g_pipSize, g_digits)   : 0.0;
      tp = (InpTakeProfitPips > 0) ? NormalizeDouble(bid - InpTakeProfitPips * g_pipSize, g_digits) : 0.0;
      if(g_trade.Sell(InpLotSize, Symbol(), bid, sl, tp, "EURJPY Model Sell"))
         Print("Market SELL placed at ", bid, " SL=", sl, " TP=", tp);
      else
         Print("Market SELL failed: ", g_trade.ResultRetcodeDescription());
      return;
   }

   sl = (InpStopLossPips > 0)   ? NormalizeDouble(price + InpStopLossPips * g_pipSize, g_digits)   : 0.0;
   tp = (InpTakeProfitPips > 0) ? NormalizeDouble(price - InpTakeProfitPips * g_pipSize, g_digits) : 0.0;

   if(InpUseStopOrders)
   {
      if(g_trade.SellStop(InpLotSize, price, Symbol(), sl, tp, ORDER_TIME_GTC, 0, "EURJPY Model SellStop"))
         Print("SELL STOP placed at ", price, " SL=", sl, " TP=", tp);
      else
         Print("SELL STOP failed: ", g_trade.ResultRetcodeDescription());
   }
   else
   {
      if(g_trade.Sell(InpLotSize, Symbol(), bid, sl, tp, "EURJPY Model Sell"))
         Print("Market SELL placed. SL=", sl, " TP=", tp);
      else
         Print("Market SELL failed: ", g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Place a Buy Stop order                                           |
//+------------------------------------------------------------------+
void PlaceBuyStopOrder(double price)
{
   double sl = 0.0, tp = 0.0;
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

   price = NormalizeDouble(price, g_digits);

   // Validate: buy stop must be above current ask
   if(price <= ask)
   {
      Print("BuyStop price (", price, ") <= Ask (", ask, "). Adjusting to market buy.");
      sl = (InpStopLossPips > 0)   ? NormalizeDouble(ask - InpStopLossPips * g_pipSize, g_digits)   : 0.0;
      tp = (InpTakeProfitPips > 0) ? NormalizeDouble(ask + InpTakeProfitPips * g_pipSize, g_digits) : 0.0;
      if(g_trade.Buy(InpLotSize, Symbol(), ask, sl, tp, "EURJPY Model Buy"))
         Print("Market BUY placed at ", ask, " SL=", sl, " TP=", tp);
      else
         Print("Market BUY failed: ", g_trade.ResultRetcodeDescription());
      return;
   }

   sl = (InpStopLossPips > 0)   ? NormalizeDouble(price - InpStopLossPips * g_pipSize, g_digits)   : 0.0;
   tp = (InpTakeProfitPips > 0) ? NormalizeDouble(price + InpTakeProfitPips * g_pipSize, g_digits) : 0.0;

   if(InpUseStopOrders)
   {
      if(g_trade.BuyStop(InpLotSize, price, Symbol(), sl, tp, ORDER_TIME_GTC, 0, "EURJPY Model BuyStop"))
         Print("BUY STOP placed at ", price, " SL=", sl, " TP=", tp);
      else
         Print("BUY STOP failed: ", g_trade.ResultRetcodeDescription());
   }
   else
   {
      // Market buy: SL/TP based on current ask price
      double slMkt = (InpStopLossPips > 0)   ? NormalizeDouble(ask - InpStopLossPips * g_pipSize, g_digits)   : 0.0;
      double tpMkt = (InpTakeProfitPips > 0) ? NormalizeDouble(ask + InpTakeProfitPips * g_pipSize, g_digits) : 0.0;
      if(g_trade.Buy(InpLotSize, Symbol(), ask, slMkt, tpMkt, "EURJPY Model Buy"))
         Print("Market BUY placed. SL=", slMkt, " TP=", tpMkt);
      else
         Print("Market BUY failed: ", g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Count open positions for this EA (by magic number)              |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_position.SelectByIndex(i))
      {
         if(g_position.Symbol() == Symbol() &&
            g_position.Magic()  == InpMagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Log all model values for debugging / audit trail                 |
//+------------------------------------------------------------------+
void LogModelValues(double P,  double Q,  double C,
                    double d,  double e,  double F,
                    double a,  double b,
                    double sellStop, double buyStop)
{
   Print("========= EURJPY Model Calculation @ ", TimeToString(TimeCurrent()), " =========");
   Print(StringFormat("  P (today)   = %.6f", P));
   Print(StringFormat("  Q (today)   = %.6f", Q));
   Print(StringFormat("  a (open H0 -2d) = %.3f | b (high H0 -2d) = %.3f", a, b));
   Print(StringFormat("  C           = %.6f", C));
   Print(StringFormat("  d           = %.6f", d));
   Print(StringFormat("  e           = %.6f", e));
   Print(StringFormat("  F           = %.6f", F));
   Print(StringFormat("  SELL STOP   = %.3f", sellStop));
   Print(StringFormat("  BUY STOP    = %.3f", buyStop));

   // Day-by-day snapshot
   for(int i = 0; i < 4; i++)
   {
      Print(StringFormat("  Day[%d]: openH0=%.3f highH0=%.3f lowH0=%.3f "
                         "maH0=%.3f maH9=%.3f hhigh=%.3f P=%.6f Q=%.6f",
                         i,
                         g_day[i].openH0, g_day[i].highH0, g_day[i].lowH0,
                         g_day[i].maH0,   g_day[i].maH9,
                         g_day[i].highestHigh,
                         g_day[i].P, g_day[i].Q));
   }
   Print("==========================================================================");
}

//+------------------------------------------------------------------+
//| OnTradeTransaction — log closed trades with P&L                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;
      if(dealTicket > 0)
      {
         if(HistoryDealSelect(dealTicket))
         {
            long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
            if(magic == InpMagicNumber)
            {
               double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
               double volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
               string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
               Print(StringFormat("[TRADE] Deal #%llu | %s | Volume: %.2f | Profit: %.2f",
                                  dealTicket, symbol, volume, profit));
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
