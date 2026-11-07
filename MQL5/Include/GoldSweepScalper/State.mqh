//+------------------------------------------------------------------+
//| State.mqh - daily counters, locks, persistence in GlobalVars     |
//+------------------------------------------------------------------+
#ifndef GSS_STATE_MQH
#define GSS_STATE_MQH

int      g_dayKey        = 0;
double   g_dayStartBal   = 0.0;
double   g_realizedToday = 0.0;
int      g_basketsToday  = 0;
int      g_consecLoss    = 0;
int      g_cooldown      = 0;
bool     g_dayLocked     = false;
bool     g_killed        = false;
double   g_peakEquity    = 0.0;

//+------------------------------------------------------------------+
string GvPrefix()
  {
   return "GSS" + IntegerToString(InpMagic) + "_";
  }
//+------------------------------------------------------------------+
double GvGet(const string name, const double def)
  {
   string k = GvPrefix() + name;
   if(GlobalVariableCheck(k))
      return GlobalVariableGet(k);
   return def;
  }
//+------------------------------------------------------------------+
void GvSet(const string name, const double v)
  {
   GlobalVariableSet(GvPrefix() + name, v);
  }
//+------------------------------------------------------------------+
//| realized net P/L of this EA's deals since server midnight        |
//+------------------------------------------------------------------+
double State_RealizedFromHistory()
  {
   datetime from = U_DayStart(TimeCurrent());
   if(!HistorySelect(from, TimeCurrent() + 86400))
      return 0.0;
   double s = 0.0;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic)
         continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol)
         continue;
      ENUM_DEAL_TYPE ty = (ENUM_DEAL_TYPE)HistoryDealGetInteger(d, DEAL_TYPE);
      if(ty != DEAL_TYPE_BUY && ty != DEAL_TYPE_SELL)
         continue;
      s += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_COMMISSION)
           + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_FEE);
     }
   return s;
  }
//+------------------------------------------------------------------+
void State_Save()
  {
   GvSet("DAY", (double)g_dayKey);
   GvSet("DAYBAL", g_dayStartBal);
   GvSet("NBASK", (double)g_basketsToday);
   GvSet("CONSEC", (double)g_consecLoss);
   GvSet("COOL", (double)g_cooldown);
   GvSet("LOCK", g_dayLocked ? 1.0 : 0.0);
   GvSet("KILL", g_killed ? 1.0 : 0.0);
   GvSet("PEAK", g_peakEquity);
  }
//+------------------------------------------------------------------+
void State_NewDay(const int dk)
  {
   g_dayKey        = dk;
   g_dayStartBal   = AccountInfoDouble(ACCOUNT_BALANCE);
   g_realizedToday = 0.0;
   g_basketsToday  = 0;
   g_consecLoss    = 0;
   g_cooldown      = 0;
   g_dayLocked     = false;
   State_Save();
  }
//+------------------------------------------------------------------+
void State_Init()
  {
   if(g_isTester)
      GlobalVariablesDeleteAll(GvPrefix());

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   int today = U_DayKey(TimeCurrent());
   int stored = (int)GvGet("DAY", 0.0);

   g_killed     = GvGet("KILL", 0.0) > 0.5;
   g_peakEquity = GvGet("PEAK", eq);
   if(InpResetKillSwitch)
     {
      g_killed = false;
      g_peakEquity = eq;
      Print("GSS: kill switch reset by input. Set InpResetKillSwitch back to false.");
     }
   if(g_peakEquity < eq)
      g_peakEquity = eq;

   if(stored == today)
     {
      g_dayKey        = today;
      g_dayStartBal   = GvGet("DAYBAL", AccountInfoDouble(ACCOUNT_BALANCE));
      g_basketsToday  = (int)GvGet("NBASK", 0.0);
      g_consecLoss    = (int)GvGet("CONSEC", 0.0);
      g_cooldown      = (int)GvGet("COOL", 0.0);
      g_dayLocked     = GvGet("LOCK", 0.0) > 0.5;
      g_realizedToday = State_RealizedFromHistory();
     }
   else
      State_NewDay(today);
   State_Save();
  }
//+------------------------------------------------------------------+
//| called once per new M1 bar                                       |
//+------------------------------------------------------------------+
void State_OnBar()
  {
   int dk = U_DayKey(TimeCurrent());
   if(dk != g_dayKey)
      State_NewDay(dk);
   if(g_cooldown > 0)
     {
      g_cooldown--;
      GvSet("COOL", (double)g_cooldown);
     }
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_peakEquity)
     {
      g_peakEquity = eq;
      GvSet("PEAK", g_peakEquity);
     }
   if(!g_killed && InpMaxDrawdownPct > 0.0 && g_peakEquity > 0.0
      && eq < g_peakEquity * (1.0 - InpMaxDrawdownPct / 100.0))
     {
      g_killed = true;
      GvSet("KILL", 1.0);
      Print("GSS: KILL SWITCH - equity drawdown limit reached, trading halted.");
     }
  }
#endif
