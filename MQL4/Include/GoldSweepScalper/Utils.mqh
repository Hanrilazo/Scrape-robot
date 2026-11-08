//+------------------------------------------------------------------+
//| Utils.mqh (MT4) - shared types, globals and helpers              |
//+------------------------------------------------------------------+
#ifndef GSS4_UTILS_MQH
#define GSS4_UTILS_MQH

#define GSS_NR     40     // M1 bars cached per new bar
#define GSS_MAXTK  8      // max tracked tickets per basket

//--- one detected liquidity sweep -----------------------------------
struct SweepSignal
  {
   bool     found;
   int      dir;            // +1 BUY (lows swept), -1 SELL (highs swept)
   string   kind;           // SWH SWL EQH EQL PDH PDL ASH ASL
   double   level;
   datetime formed;
   double   wick;           // extreme of the sweep
   double   depthAtr;
   double   atr;
   int      runLen;
   double   runAtr;
   double   rejPct;
   double   bodyRatio;
   double   tvRatio;
   double   confirmLevel;
   datetime time;           // open time of the sweep bar
   int      prio;
  };

//--- liquidity level ------------------------------------------------
struct LevelInfo
  {
   double   price;
   bool     isHigh;
   string   kind;
   datetime formed;
   int      prio;
  };

//--- the one live basket --------------------------------------------
struct BasketState
  {
   bool     active;
   long     id;
   int      dir;
   datetime openTime;
   string   levelKind;
   double   level;
   double   wick;
   double   atr;
   double   sl;
   double   tp;
   double   entry1;
   int      planned;
   bool     locked;
   datetime addsExpire;
   double   mfe;
   double   mae;
   int      barsOpen;
   string   closeReason;
   datetime lastLockTry;
   int      runLen;
   double   rejPct;
  };

struct RunStats
  {
   int      n;
   int      wins;
   int      losses;
   double   grossWin;
   double   grossLoss;
   double   net;
   double   t1Net;
   double   addsNet;
  };

//--- globals --------------------------------------------------------
BasketState g_bk;
RunStats    g_st;

int      g_tk[GSS_MAXTK];          // tickets of the basket
int      g_tkIdx[GSS_MAXTK];       // 1 = first ticket, 2.. = adds
double   g_tkPx[GSS_MAXTK];        // planned price
bool     g_tkFilled[GSS_MAXTK];
int      g_nTk = 0;

bool     g_isTester = false;
bool     g_isVisual = false;
bool     g_isOptim  = false;
bool     g_draw     = false;
int      g_digits   = 2;
double   g_tick     = 0.01;
double   g_tickValue = 1.0;
double   g_pip      = 0.10;
double   g_lot      = 0.01;
double   g_contract = 100.0;

double   g_atr1     = 0.0;
double   g_atr15    = 0.0;
int      g_bias     = 0;
string   g_sep      = ",";

datetime g_rt[GSS_NR];
double   g_ro[GSS_NR];
double   g_rh[GSS_NR];
double   g_rl[GSS_NR];
double   g_rc[GSS_NR];
long     g_rv[GSS_NR];
bool     g_ratesOk  = false;

int      g_sesA[];
int      g_sesB[];
int      g_nSes     = 0;
int      g_rolA[];
int      g_rolB[];
int      g_nRol     = 0;
int      g_blkA[];
int      g_blkB[];
int      g_nBlk     = 0;
int      g_fridayNoNew = -1;
int      g_fridayFlat  = -1;

double   g_lastStopDist = 0.0;
int      g_lastAdds     = 0;
string   g_lastFilter   = "";

//+------------------------------------------------------------------+
double U_Pip(const double pips)
  {
   return pips * g_pip;
  }
//+------------------------------------------------------------------+
double U_RoundTick(const double price)
  {
   if(g_tick <= 0.0)
      return NormalizeDouble(price, g_digits);
   return NormalizeDouble(MathRound(price / g_tick) * g_tick, g_digits);
  }
//+------------------------------------------------------------------+
double U_CeilTick(const double price)
  {
   if(g_tick <= 0.0)
      return NormalizeDouble(price, g_digits);
   return NormalizeDouble(MathCeil(price / g_tick - 1e-9) * g_tick, g_digits);
  }
//+------------------------------------------------------------------+
double U_FloorTick(const double price)
  {
   if(g_tick <= 0.0)
      return NormalizeDouble(price, g_digits);
   return NormalizeDouble(MathFloor(price / g_tick + 1e-9) * g_tick, g_digits);
  }
//+------------------------------------------------------------------+
int U_MinutesOfDay(const datetime t)
  {
   return TimeHour(t) * 60 + TimeMinute(t);
  }
//+------------------------------------------------------------------+
int U_DayKey(const datetime t)
  {
   return TimeYear(t) * 10000 + TimeMonth(t) * 100 + TimeDay(t);
  }
//+------------------------------------------------------------------+
int U_Dow(const datetime t)
  {
   return TimeDayOfWeek(t);      // 0 = Sunday
  }
//+------------------------------------------------------------------+
datetime U_DayStart(const datetime t)
  {
   long v = (long)t;
   return (datetime)(v - (v % 86400));
  }
//+------------------------------------------------------------------+
//| "HH:MM" -> minutes since midnight, -1 on error                   |
//+------------------------------------------------------------------+
int U_ParseHM(string s)
  {
   StringReplace(s, " ", "");
   string p[];
   if(StringSplit(s, ':', p) != 2)
      return -1;
   int h = (int)StringToInteger(p[0]);
   int m = (int)StringToInteger(p[1]);
   if(h < 0 || h > 24 || m < 0 || m > 59)
      return -1;
   return h * 60 + m;
  }
//+------------------------------------------------------------------+
//| "HH:MM-HH:MM;HH:MM-HH:MM" -> arrays of start/end minutes         |
//+------------------------------------------------------------------+
int U_ParseWindows(string list, int &a[], int &b[])
  {
   ArrayResize(a, 0);
   ArrayResize(b, 0);
   StringReplace(list, " ", "");
   if(StringLen(list) == 0)
      return 0;
   string items[];
   int n = StringSplit(list, ';', items);
   int cnt = 0;
   for(int i = 0; i < n; i++)
     {
      string pr[];
      if(StringSplit(items[i], '-', pr) != 2)
        {
         Print("GSS: bad time window '", items[i], "' ignored");
         continue;
        }
      int s = U_ParseHM(pr[0]);
      int e = U_ParseHM(pr[1]);
      if(s < 0 || e < 0)
        {
         Print("GSS: bad time window '", items[i], "' ignored");
         continue;
        }
      ArrayResize(a, cnt + 1);
      ArrayResize(b, cnt + 1);
      a[cnt] = s;
      b[cnt] = e;
      cnt++;
     }
   return cnt;
  }
//+------------------------------------------------------------------+
bool U_InAnyWindow(const int mins, const int &a[], const int &b[], const int n)
  {
   for(int i = 0; i < n; i++)
     {
      if(a[i] == b[i])
         continue;
      if(a[i] < b[i])
        {
         if(mins >= a[i] && mins < b[i])
            return true;
        }
      else
        {
         if(mins >= a[i] || mins < b[i])
            return true;
        }
     }
   return false;
  }
//+------------------------------------------------------------------+
bool U_IsNewBar()
  {
   static datetime last = 0;
   datetime t = iTime(_Symbol, PERIOD_M1, 0);
   if(t == 0 || t == last)
      return false;
   last = t;
   return true;
  }
//+------------------------------------------------------------------+
//| refresh cached indicator values and the last M1 bars             |
//+------------------------------------------------------------------+
void U_RefreshMarketData()
  {
   g_atr1  = iATR(_Symbol, PERIOD_M1, InpAtrPeriod, 1);
   g_atr15 = iATR(_Symbol, PERIOD_M15, InpAtrPeriod, 1);
   double e1 = iMA(_Symbol, PERIOD_M15, InpBiasEMAPeriod, 0, MODE_EMA, PRICE_CLOSE, 1);
   double e3 = iMA(_Symbol, PERIOD_M15, InpBiasEMAPeriod, 0, MODE_EMA, PRICE_CLOSE, 3);
   double c  = iClose(_Symbol, PERIOD_M15, 1);
   g_bias = 0;
   if(e1 > 0.0 && e3 > 0.0)
     {
      if(c > e1 && e1 > e3)
         g_bias = 1;
      else
         if(c < e1 && e1 < e3)
            g_bias = -1;
     }
   double tv = MarketInfo(_Symbol, MODE_TICKVALUE);
   if(tv > 0.0)
      g_tickValue = tv;
   for(int i = 0; i < GSS_NR; i++)
     {
      g_rt[i] = iTime(_Symbol, PERIOD_M1, i);
      g_ro[i] = iOpen(_Symbol, PERIOD_M1, i);
      g_rh[i] = iHigh(_Symbol, PERIOD_M1, i);
      g_rl[i] = iLow(_Symbol, PERIOD_M1, i);
      g_rc[i] = iClose(_Symbol, PERIOD_M1, i);
      g_rv[i] = iVolume(_Symbol, PERIOD_M1, i);
     }
   g_ratesOk = (g_rt[GSS_NR - 1] > 0);
  }
//+------------------------------------------------------------------+
double U_Spread()
  {
   return MarketInfo(_Symbol, MODE_ASK) - MarketInfo(_Symbol, MODE_BID);
  }
//+------------------------------------------------------------------+
//| broker minimum distance for stops / pendings, in price units     |
//+------------------------------------------------------------------+
double U_StopsLevel()
  {
   double a = MarketInfo(_Symbol, MODE_STOPLEVEL);
   double b = MarketInfo(_Symbol, MODE_FREEZELEVEL);
   return MathMax(a, b) * _Point;
  }
//+------------------------------------------------------------------+
//| account-currency value of a price distance for ONE lot           |
//+------------------------------------------------------------------+
double U_UsdPerLot(const double dist)
  {
   if(g_tick > 0.0 && g_tickValue > 0.0)
      return MathAbs(dist) / g_tick * g_tickValue;
   return MathAbs(dist) * g_contract;
  }
//+------------------------------------------------------------------+
bool U_IsPos(const int type)
  {
   return (type == OP_BUY || type == OP_SELL);
  }
//+------------------------------------------------------------------+
//| select order i of the trade pool if it belongs to this EA        |
//+------------------------------------------------------------------+
bool U_SelectMine(const int i)
  {
   if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      return false;
   if(OrderSymbol() != _Symbol)
      return false;
   if(OrderMagicNumber() != InpMagic)
      return false;
   return true;
  }
//+------------------------------------------------------------------+
int U_CountPositions()
  {
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!U_SelectMine(i))
         continue;
      if(U_IsPos(OrderType()))
         c++;
     }
   return c;
  }
//+------------------------------------------------------------------+
int U_CountPendings()
  {
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!U_SelectMine(i))
         continue;
      if(!U_IsPos(OrderType()))
         c++;
     }
   return c;
  }
//+------------------------------------------------------------------+
double U_FloatingPnL()
  {
   double s = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!U_SelectMine(i))
         continue;
      if(!U_IsPos(OrderType()))
         continue;
      s += OrderProfit() + OrderSwap() + OrderCommission();
     }
   return s;
  }
//+------------------------------------------------------------------+
//| volume weighted average open price of the basket's positions     |
//+------------------------------------------------------------------+
void U_AvgEntry(double &avg, double &vol)
  {
   double w = 0.0;
   vol = 0.0;
   avg = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!U_SelectMine(i))
         continue;
      if(!U_IsPos(OrderType()))
         continue;
      double v = OrderLots();
      w += v * OrderOpenPrice();
      vol += v;
     }
   if(vol > 0.0)
      avg = w / vol;
  }
//+------------------------------------------------------------------+
void U_Notify(const string msg)
  {
   if(InpNotify && !g_isTester)
      SendNotification(StringSubstr(msg, 0, 250));
  }
#endif
