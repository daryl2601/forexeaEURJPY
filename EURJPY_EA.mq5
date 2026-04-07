//+------------------------------------------------------------------+
//|                                                   EURJPY_EA.mq5 |
//|                        EUR/JPY Trend-Following Expert Advisor    |
//|                                                                  |
//|  Strategy: EMA 20/50 crossover with RSI filter                  |
//|  Timeframe: H1 (recommended)                                    |
//|  Pair: EUR/JPY                                                   |
//+------------------------------------------------------------------+
#property copyright "forexeaEURJPY"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input parameters
input group "=== Strategy Settings ==="
input int    FastEMA_Period  = 20;         // Fast EMA period
input int    SlowEMA_Period  = 50;         // Slow EMA period
input int    RSI_Period      = 14;         // RSI period
input double RSI_Overbought  = 70.0;       // RSI overbought level
input double RSI_Oversold    = 30.0;       // RSI oversold level

input group "=== Risk Management ==="
input double RiskPercent     = 1.0;        // Risk per trade (% of balance)
input double ATR_SL_Mult     = 1.5;        // ATR multiplier for stop loss
input double ATR_TP_Mult     = 2.5;        // ATR multiplier for take profit
input int    ATR_Period      = 14;         // ATR period
input double MaxLotSize      = 10.0;       // Maximum lot size
input double MinLotSize      = 0.01;       // Minimum lot size

input group "=== Trade Management ==="
input bool   UseBreakEven    = true;       // Enable break-even
input double BreakEvenATRMult= 1.0;        // ATR multiplier to trigger break-even
input bool   UseTrailingStop = true;       // Enable trailing stop
input double TrailingATRMult = 1.0;        // ATR multiplier for trailing stop

input group "=== Session Filter ==="
input bool   UseSessionFilter = true;      // Enable trading session filter
input int    SessionStartHour = 7;         // Session start hour (server time)
input int    SessionEndHour   = 20;        // Session end hour (server time)

input group "=== General ==="
input int    MagicNumber     = 20241001;   // Magic number
input string TradeComment    = "EURJPY_EA";// Trade comment
input ENUM_ORDER_TYPE_FILLING FillType = ORDER_FILLING_IOC; // Order fill type

//--- Global objects
CTrade         trade;
CPositionInfo  posInfo;

//--- Indicator handles
int handleFastEMA;
int handleSlowEMA;
int handleRSI;
int handleATR;

//--- State tracking
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialisation                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate inputs
   if(FastEMA_Period >= SlowEMA_Period)
   {
      Print("Error: FastEMA_Period must be less than SlowEMA_Period");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(RiskPercent <= 0 || RiskPercent > 10)
   {
      Print("Error: RiskPercent must be between 0 and 10");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Create indicator handles
   handleFastEMA = iMA(_Symbol, PERIOD_CURRENT, FastEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleSlowEMA = iMA(_Symbol, PERIOD_CURRENT, SlowEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI     = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   handleATR     = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);

   if(handleFastEMA == INVALID_HANDLE || handleSlowEMA == INVALID_HANDLE ||
      handleRSI == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return INIT_FAILED;
   }

   // Configure trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFilling(FillType);

   Print("EURJPY EA initialised successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleFastEMA);
   IndicatorRelease(handleSlowEMA);
   IndicatorRelease(handleRSI);
   IndicatorRelease(handleATR);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only process on new bar
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime)
   {
      // Still manage open positions on every tick
      ManageOpenPositions();
      return;
   }
   lastBarTime = currentBarTime;

   // Session filter
   if(UseSessionFilter && !IsWithinSession())
      return;

   // Retrieve indicator values (bars 1 and 2 to confirm completed candles)
   double fastEMA[3], slowEMA[3], rsiVal[3], atrVal[3];

   if(CopyBuffer(handleFastEMA, 0, 0, 3, fastEMA) < 3) return;
   if(CopyBuffer(handleSlowEMA, 0, 0, 3, slowEMA) < 3) return;
   if(CopyBuffer(handleRSI,     0, 0, 3, rsiVal)  < 3) return;
   if(CopyBuffer(handleATR,     0, 0, 3, atrVal)  < 3) return;

   // Index 0 = current (forming), index 1 = last closed, index 2 = two bars back
   double fastPrev  = fastEMA[2];
   double fastCurr  = fastEMA[1];
   double slowPrev  = slowEMA[2];
   double slowCurr  = slowEMA[1];
   double rsiCurr   = rsiVal[1];
   double atrCurr   = atrVal[1];

   bool hasBuyPosition  = HasOpenPosition(POSITION_TYPE_BUY);
   bool hasSellPosition = HasOpenPosition(POSITION_TYPE_SELL);

   // --- BUY signal: fast EMA crosses above slow EMA + RSI not overbought ---
   bool bullCrossover = (fastPrev <= slowPrev) && (fastCurr > slowCurr);
   if(bullCrossover && rsiCurr < RSI_Overbought && !hasBuyPosition)
   {
      if(hasSellPosition)
         CloseAllPositions(POSITION_TYPE_SELL);

      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = ask - atrCurr * ATR_SL_Mult;
      double tp  = ask + atrCurr * ATR_TP_Mult;
      double lots = CalculateLotSize(atrCurr * ATR_SL_Mult);

      if(lots > 0)
         trade.Buy(lots, _Symbol, ask, sl, tp, TradeComment);
   }

   // --- SELL signal: fast EMA crosses below slow EMA + RSI not oversold ---
   bool bearCrossover = (fastPrev >= slowPrev) && (fastCurr < slowCurr);
   if(bearCrossover && rsiCurr > RSI_Oversold && !hasSellPosition)
   {
      if(hasBuyPosition)
         CloseAllPositions(POSITION_TYPE_BUY);

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = bid + atrCurr * ATR_SL_Mult;
      double tp  = bid - atrCurr * ATR_TP_Mult;
      double lots = CalculateLotSize(atrCurr * ATR_SL_Mult);

      if(lots > 0)
         trade.Sell(lots, _Symbol, bid, sl, tp, TradeComment);
   }
}

//+------------------------------------------------------------------+
//| Manage open positions (break-even, trailing stop)               |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   if(!UseBreakEven && !UseTrailingStop)
      return;

   double atrVal[1];
   if(CopyBuffer(handleATR, 0, 1, 1, atrVal) < 1)
      return;
   double atr = atrVal[0];

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Magic() != MagicNumber || posInfo.Symbol() != _Symbol)
         continue;

      double openPrice  = posInfo.PriceOpen();
      double currentSL  = posInfo.StopLoss();
      double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      ulong  ticket     = posInfo.Ticket();

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double newSL = currentSL;

         // Break-even
         if(UseBreakEven && currentBid >= openPrice + atr * BreakEvenATRMult)
         {
            double beSL = openPrice + _Point;
            if(currentSL == 0 || currentSL < beSL)
               newSL = beSL;
         }

         // Trailing stop
         if(UseTrailingStop)
         {
            double trailSL = currentBid - atr * TrailingATRMult;
            if(currentSL == 0 || trailSL > newSL)
               newSL = trailSL;
         }

         if(newSL != currentSL && newSL > 0 && newSL < currentBid)
            trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), posInfo.TakeProfit());
      }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double newSL = currentSL;

         // Break-even
         if(UseBreakEven && currentAsk <= openPrice - atr * BreakEvenATRMult)
         {
            double beSL = openPrice - _Point;
            if(currentSL == 0 || currentSL > beSL)
               newSL = beSL;
         }

         // Trailing stop
         if(UseTrailingStop)
         {
            double trailSL = currentAsk + atr * TrailingATRMult;
            if(currentSL == 0 || trailSL < newSL)
               newSL = trailSL;
         }

         if(newSL != currentSL && newSL > currentAsk)
            trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), posInfo.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                      |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossPoints)
{
   double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount  = balance * RiskPercent / 100.0;
   double tickValue   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(tickValue == 0 || tickSize == 0 || stopLossPoints == 0)
      return 0;

   double lotSize = riskAmount / (stopLossPoints / tickSize * tickValue);

   // Clamp to broker limits
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   minVol = MathMax(minVol, MinLotSize);
   maxVol = MathMin(maxVol, MaxLotSize);

   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(MathMin(lotSize, maxVol), minVol);

   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Check if there is an open position of the given type            |
//+------------------------------------------------------------------+
bool HasOpenPosition(ENUM_POSITION_TYPE posType)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Magic() == MagicNumber && posInfo.Symbol() == _Symbol &&
         posInfo.PositionType() == posType)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Close all positions of the given type                            |
//+------------------------------------------------------------------+
void CloseAllPositions(ENUM_POSITION_TYPE posType)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Magic() == MagicNumber && posInfo.Symbol() == _Symbol &&
         posInfo.PositionType() == posType)
         trade.PositionClose(posInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Check whether current time is within the trading session        |
//+------------------------------------------------------------------+
bool IsWithinSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.hour >= SessionStartHour && dt.hour < SessionEndHour);
}
//+------------------------------------------------------------------+
