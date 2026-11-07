//+------------------------------------------------------------------+
//| GoldSweepScalper.mq5                                             |
//| XAUUSD M1 liquidity-sweep scalper with a scale-in basket.        |
//| HEDGING accounts only. Test on demo first.                       |
//+------------------------------------------------------------------+
#property copyright   "scrape-robot"
#property version     "1.00"
#property description "Liquidity sweep after a 3+ candle push, slowdown confirmed,"
#property description "scale-in basket of 0.01 lots, all tickets share one SL and TP."
#property description "Every signal and basket is written to CSV in Common\\Files\\GoldSweep."

#include <Trade\Trade.mqh>

enum ENUM_ENTRY_MODE
  {
   ENTRY_AGGRESSIVE = 0,   // market at the open after the sweep bar
   ENTRY_CONFIRMED  = 1    // wait for a close beyond the sweep candle
  };

//--- identity ---------------------------------------------------------
input group "=== Identity ==="
input long   InpMagic              = 20260507;   // Magic number

//--- signal -----------------------------------------------------------
input group "=== Signal (distances scale with M1 ATR) ==="
input int    InpMinRunCandles      = 3;          // Push candles before the breach (0 = off)
input double InpRunMinATR          = 1.0;        // Run net move >= x ATR
input double InpSweepMinATR        = 0.25;       // Min sweep depth (x ATR)
input double InpSweepMaxATR        = 1.5;        // Max sweep depth (x ATR), deeper = breakout
input int    InpSweepWindowBars    = 1;          // 1 = single bar sweep, 2 = allow 2 bar sweep
input double InpRejectWickPct      = 40.0;       // Rejection wick % of sweep bar range
input double InpBodyRatioMax       = 0.6;        // Sweep bar body <= x avg run body
input int    InpMinLevelAgeMin     = 15;         // Level must be at least this old (minutes)
input ENUM_ENTRY_MODE InpEntryMode = ENTRY_AGGRESSIVE; // Entry mode
input int    InpConfirmBars        = 5;          // Confirmed mode: max bars to wait
input int    InpAtrPeriod          = 14;         // ATR period

input group "=== Liquidity levels ==="
input bool   InpUseSwingLevels     = true;       // M15 swing highs/lows
input bool   InpUseEqualLevels     = true;       // Equal highs/lows
input bool   InpUsePrevDayLevels   = true;       // Previous day high/low
input bool   InpUseAsianLevels     = true;       // Asian range high/low
input int    InpAsianStartHour     = 1;          // Asian start (server hour)
input int    InpAsianEndHour       = 9;          // Asian end (server hour)
input double InpEqTolATR           = 0.15;       // Equal level tolerance (x M15 ATR)

//--- basket -----------------------------------------------------------
input group "=== Basket (scale-in) ==="
input double InpLotPerTicket       = 0.01;       // Lot per ticket
input int    InpMaxTickets         = 5;          // Max tickets per basket (1-6)
input double InpTargetPips         = 12.0;       // Close all when WORST entry is this many pips in profit
input double InpPipSizeUSD         = 0.10;       // Price value of 1 pip (gold: 0.10)
input double InpSLBufferATR        = 0.3;        // SL buffer beyond wick (x ATR, + spread)
input double InpMaxStopToTarget    = 3.0;        // Skip if first-entry stop > x target
input double InpMinAddStepPips     = 4.0;        // Min spacing between tickets (pips)
input int    InpAddWindowBars      = 15;         // Pending adds expire after N bars
input double InpLockTriggerPips    = 8.0;        // Lock: profit beyond basket break-even (0 = off)
input double InpLockOffsetPips     = 2.0;        // Lock: SL = break-even + this
input double InpMaxRiskPerBasketPct = 1.5;       // Worst-case basket loss % of equity (0 = off)
input double InpMaxBasketLossUSD   = 0.0;        // Hard floating loss cap in USD (0 = off)
input double InpCommissionPerLotRT = 0.0;        // Round-turn commission per lot (USD)
input int    InpMaxHoldBars        = 45;         // Time stop in M1 bars (0 = off)
input double InpMaxEntrySlipPips   = 3.0;        // Abort if first fill slips more than this
input int    InpDeviationPoints    = 30;         // Max deviation in points

//--- filters ----------------------------------------------------------
input group "=== Filters (server time) ==="
input double InpMaxSpreadUSD       = 0.40;       // Max spread in USD
input string InpSessions           = "10:00-13:00;15:30-19:00"; // Allowed windows (empty = always)
input string InpRolloverBlock      = "23:30-01:30";             // No trading window
input string InpExtraBlackouts     = "";         // More no-trade windows, e.g. "17:55-18:10"
input string InpFridayNoNewAfter   = "20:00";    // No new baskets on Friday after
input string InpFridayFlatten      = "22:30";    // Flatten on Friday at
input double InpMinATRUSD          = 0.30;       // Min M1 ATR in USD
input double InpMaxATRUSD          = 5.00;       // Max M1 ATR in USD
input bool   InpUseHTFBias         = true;       // Trade only with M15 EMA bias
input int    InpBiasEMAPeriod      = 50;         // M15 EMA period
input bool   InpUseNewsFilter      = true;       // High impact USD news blackout
input int    InpNewsBeforeMin      = 15;         // Minutes before news
input int    InpNewsAfterMin       = 15;         // Minutes after news
input int    InpFlattenBeforeNewsMin = 5;        // Close open basket this many minutes before news

//--- account guards ---------------------------------------------------
input group "=== Account guards ==="
input int    InpMaxBasketsPerDay   = 8;          // Max baskets per day
input int    InpMaxConsecLosses    = 3;          // Stop for the day after N losing baskets in a row (0 = off)
input int    InpCooldownBars       = 10;         // Bars to wait after a losing basket
input double InpDailyMaxLossPct    = 3.0;        // Daily loss lock % of day-start balance (0 = off)
input double InpMaxDrawdownPct     = 10.0;       // Kill switch: equity drawdown % from peak (0 = off)
input bool   InpResetKillSwitch    = false;      // Set true for ONE start to clear the kill switch

//--- journal / ui -----------------------------------------------------
input group "=== Journal & UI ==="
input bool   InpJournal            = true;       // Write CSV journal
input string InpCsvSep             = ",";        // CSV separator (use ; for comma-decimal Excel)
input bool   InpScreenshots        = true;       // Chart screenshot at entry/exit
input bool   InpNotify             = false;      // Push notifications
input bool   InpShowPanel          = true;       // On-chart panel

#include <GoldSweepScalper/Utils.mqh>
#include <GoldSweepScalper/State.mqh>
#include <GoldSweepScalper/Journal.mqh>
#include <GoldSweepScalper/News.mqh>
#include <GoldSweepScalper/Levels.mqh>
#include <GoldSweepScalper/Filters.mqh>
#include <GoldSweepScalper/Risk.mqh>
#include <GoldSweepScalper/Panel.mqh>
#include <GoldSweepScalper/Basket.mqh>
#include <GoldSweepScalper/Signal.mqh>

//+------------------------------------------------------------------+
int OnInit()
  {
   g_isTester = (bool)MQLInfoInteger(MQL_TESTER);
   g_isVisual = (bool)MQLInfoInteger(MQL_VISUAL_MODE);
   g_isOptim  = (bool)MQLInfoInteger(MQL_OPTIMIZATION);

   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("GSS: this EA needs a HEDGING account (several tickets in one direction). Netting account detected - stopping.");
      return INIT_FAILED;
     }
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
      Print("GSS: WARNING - symbol ", _Symbol, " does not look like gold. Defaults are tuned for XAUUSD.");
   if(Period() != PERIOD_M1)
      Print("GSS: note - the EA works on M1 data internally; attach it to an M1 chart for clean visuals.");
   if(!SymbolSelect(_Symbol, true))
      Print("GSS: could not select ", _Symbol, " in Market Watch");

   g_digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_tick     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_tick <= 0.0)
      g_tick = _Point;
   g_contract = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   g_pip      = InpPipSizeUSD;
   if(g_pip <= 0.0)
     {
      Print("GSS: InpPipSizeUSD must be > 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vstep <= 0.0)
      vstep = 0.01;
   g_lot = MathFloor(InpLotPerTicket / vstep + 1e-9) * vstep;
   g_lot = MathMax(vmin, MathMin(vmax, g_lot));
   g_lot = NormalizeDouble(g_lot, 3);
   if(MathAbs(g_lot - InpLotPerTicket) > 1e-9)
      PrintFormat("GSS: lot adjusted from %.3f to %.3f (broker limits)", InpLotPerTicket, g_lot);
   if(InpMaxTickets < 1 || InpMaxTickets > 6)
      Print("GSS: InpMaxTickets should be 1..6, value is clamped");

   g_hAtr1  = iATR(_Symbol, PERIOD_M1, InpAtrPeriod);
   g_hAtr15 = iATR(_Symbol, PERIOD_M15, InpAtrPeriod);
   g_hEma15 = iMA(_Symbol, PERIOD_M15, InpBiasEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hAtr1 == INVALID_HANDLE || g_hAtr15 == INVALID_HANDLE || g_hEma15 == INVALID_HANDLE)
     {
      Print("GSS: could not create indicator handles");
      return INIT_FAILED;
     }
   ArraySetAsSeries(g_buf, true);
   ArraySetAsSeries(g_rates, true);

   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   ZeroMemory(g_st);
   g_pend.active = false;
   Basket_Reset();

   Panel_Init();
   Filters_Init();
   State_Init();
   Journal_Init();
   News_Init();
   Basket_Restore();

   PrintFormat("GSS: started on %s, lot %.2f, tickets up to %d, target %.1f pips (%.2f USD), tester=%s",
               _Symbol, g_lot, MathMax(1, MathMin(InpMaxTickets, 6)), InpTargetPips, U_Pip(InpTargetPips),
               g_isTester ? "yes" : "no");
   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Stats_Print();
   if(g_bk.active && U_CountPositions() > 0)
      Print("GSS: stopped with an open basket. Server-side SL/TP remain active; pending adds expire on their own.");
   Panel_Cleanup();
   if(g_hAtr1 != INVALID_HANDLE)
      IndicatorRelease(g_hAtr1);
   if(g_hAtr15 != INVALID_HANDLE)
      IndicatorRelease(g_hAtr15);
   if(g_hEma15 != INVALID_HANDLE)
      IndicatorRelease(g_hEma15);
  }
//+------------------------------------------------------------------+
void OnTick()
  {
   bool nb = U_IsNewBar();
   if(nb)
     {
      State_OnBar();
      U_RefreshMarketData();
      Levels_OnBar();
      News_OnBar();
     }

   if(g_bk.active)
      Basket_Manage(nb);
   else
      if(nb)
        {
         bool hadPending = g_pend.active;
         Pending_Process();
         if(!hadPending && !g_bk.active)
            Signal_Scan();
        }

   if(nb)
      Panel_Update();
  }
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   ENUM_DEAL_ENTRY en = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(en == DEAL_ENTRY_IN)
      Basket_OnEntryDeal(trans.deal);
   else
      if(en == DEAL_ENTRY_OUT || en == DEAL_ENTRY_OUT_BY)
         Basket_OnExitDeal(trans.deal);
  }
//+------------------------------------------------------------------+
//| optimisation criterion: needs at least 100 baskets               |
//+------------------------------------------------------------------+
double OnTester()
  {
   if(g_st.n < 100)
      return 0.0;
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double dd = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   return (pf - 1.0) * MathSqrt((double)g_st.n) / (1.0 + dd);
  }
//+------------------------------------------------------------------+
