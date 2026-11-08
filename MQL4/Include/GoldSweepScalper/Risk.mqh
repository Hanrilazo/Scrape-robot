//+------------------------------------------------------------------+
//| Risk.mqh (MT4) - basket sizing, daily lock, kill switch          |
//+------------------------------------------------------------------+
#ifndef GSS4_RISK_MQH
#define GSS4_RISK_MQH

//+------------------------------------------------------------------+
//| loss in account currency if every ticket in px[] is filled and   |
//| the basket stop is hit (commission included)                     |
//+------------------------------------------------------------------+
double Risk_WorstCase(const double &px[], const int n, const double sl)
  {
   double sum = 0.0;
   for(int i = 0; i < n; i++)
     {
      sum += U_UsdPerLot(px[i] - sl) * g_lot;
      sum += InpCommissionPerLotRT * g_lot;
     }
   return sum;
  }
//+------------------------------------------------------------------+
double Risk_MarginNeeded(const int tickets)
  {
   return MarketInfo(_Symbol, MODE_MARGINREQUIRED) * g_lot * tickets;
  }
//+------------------------------------------------------------------+
//| true when the account must be flattened                          |
//+------------------------------------------------------------------+
bool Risk_GuardBreached(string &reason)
  {
   double eq = AccountEquity();
   if(InpMaxDrawdownPct > 0.0 && g_peakEquity > 0.0 && eq < g_peakEquity * (1.0 - InpMaxDrawdownPct / 100.0))
     {
      reason = "KILL_SWITCH";
      return true;
     }
   if(InpDailyMaxLossPct > 0.0 && g_dayStartBal > 0.0)
     {
      double pnl = g_realizedToday + U_FloatingPnL();
      if(pnl <= -g_dayStartBal * InpDailyMaxLossPct / 100.0)
        {
         reason = "DAILY_LOCK";
         return true;
        }
     }
   return false;
  }
//+------------------------------------------------------------------+
void Risk_Lock(const string reason)
  {
   if(reason == "KILL_SWITCH")
      g_killed = true;
   else
      g_dayLocked = true;
   State_Save();
   Print("GSS: ", reason, " triggered - trading halted. Day P/L ", DoubleToString(g_realizedToday + U_FloatingPnL(), 2));
   Journal_Event("GUARD_" + reason, 0.0, 0.0, 0.0, "");
   U_Notify("GoldSweep " + reason + " triggered, trading halted");
  }
//+------------------------------------------------------------------+
//| book a closed basket into the daily counters                     |
//+------------------------------------------------------------------+
void Risk_AfterBasket(const double net)
  {
   g_realizedToday += net;
   g_basketsToday++;
   if(net < 0.0)
     {
      g_consecLoss++;
      g_cooldown = InpCooldownBars;
     }
   else
      g_consecLoss = 0;

   double eq = AccountEquity();
   if(eq > g_peakEquity)
      g_peakEquity = eq;

   if(!g_dayLocked && InpDailyMaxLossPct > 0.0 && g_dayStartBal > 0.0
      && g_realizedToday <= -g_dayStartBal * InpDailyMaxLossPct / 100.0)
     {
      g_dayLocked = true;
      Print("GSS: DAILY_LOCK - daily loss limit reached.");
      U_Notify("GoldSweep daily loss limit reached");
     }
   if(!g_killed && InpMaxDrawdownPct > 0.0 && g_peakEquity > 0.0
      && eq < g_peakEquity * (1.0 - InpMaxDrawdownPct / 100.0))
     {
      g_killed = true;
      Print("GSS: KILL SWITCH - equity drawdown limit reached.");
      U_Notify("GoldSweep KILL SWITCH - drawdown limit reached");
     }
   State_Save();
  }
#endif
