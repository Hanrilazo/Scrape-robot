//+------------------------------------------------------------------+
//| Utils.mqh - shared types, globals and helpers                    |
//+------------------------------------------------------------------+
#ifndef GSS_UTILS_MQH
#define GSS_UTILS_MQH

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
   bool     finalizeFlag;
   datetime noPosSince;
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
CTrade      g_trade;
BasketState g_bk;
RunStats    g_st;

bool     g_isTester = false;
bool     g_isVisual = false;
bool     g_isOptim  = false;
bool     g_draw     = false;
int      g_digits   = 2;
double   g_tick     = 0.01;
double   g_pip      = 0.10;
double   g_lot      = 0.01;
double   g_contract = 100.0;

int      g_hAtr1    = INVALID_HANDLE;
int      g_hAtr15   = INVALID_HANDLE;
int      g_hEma15   = INVALID_HANDLE;
double   g_atr1     = 0.0;
double   g_atr15    = 0.0;
int      g_bias     = 0;
double   g_buf[];
MqlRates g_rates[];
string   g_sep      = ",";

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
   MqlDateTime d;
   TimeToStruct(t, d);
   return d.hour * 60 + d.min;
  }
//+------------------------------------------------------------------+
int U_DayKey(const datetime t)
  {
   MqlDateTime d;
   TimeToStruct(t, d);
   return d.year * 10000 + d.mon * 100 + d.day;
  }
//+------------------------------------------------------------------+
int U_Dow(const datetime t)
  {
   MqlDateTime d;
   TimeToStruct(t, d);
   return d.day_of_week;
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
   if(CopyBuffer(g_hAtr1, 0, 1, 1, g_buf) == 1)
      g_atr1 = g_buf[0];
   if(CopyBuffer(g_hAtr15, 0, 1, 1, g_buf) == 1)
      g_atr15 = g_buf[0];
   g_bias = 0;
   if(CopyBuffer(g_hEma15, 0, 1, 3, g_buf) == 3)
     {
      double c = iClose(_Symbol, PERIOD_M15, 1);
      if(c > g_buf[0] && g_buf[0] > g_buf[2])
         g_bias = 1;
      else
         if(c < g_buf[0] && g_buf[0] < g_buf[2])
            g_bias = -1;
     }
   CopyRates(_Symbol, PERIOD_M1, 0, 40, g_rates);
  }
//+------------------------------------------------------------------+
double U_Spread()
  {
   return SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
  }
//+------------------------------------------------------------------+
//| broker minimum distance for stops / pendings, in price units     |
//+------------------------------------------------------------------+
double U_StopsLevel()
  {
   long a = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long b = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return (double)MathMax(a, b) * _Point;
  }
//+------------------------------------------------------------------+
int U_CountPositions()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      c++;
     }
   return c;
  }
//+------------------------------------------------------------------+
int U_CountOrders()
  {
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      c++;
     }
   return c;
  }
//+------------------------------------------------------------------+
double U_FloatingPnL()
  {
   double s = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      s += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return s;
  }
//+------------------------------------------------------------------+
ulong U_FirstPositionTicket()
  {
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      return t;
     }
   return 0;
  }
//+------------------------------------------------------------------+
//| volume weighted average open price of the basket's positions     |
//+------------------------------------------------------------------+
void U_AvgEntry(double &avg, double &vol)
  {
   double w = 0.0;
   vol = 0.0;
   avg = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      double v = PositionGetDouble(POSITION_VOLUME);
      w += v * PositionGetDouble(POSITION_PRICE_OPEN);
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
