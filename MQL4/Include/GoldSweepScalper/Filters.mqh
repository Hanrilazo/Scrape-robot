//+------------------------------------------------------------------+
//| Filters.mqh (MT4) - trading permission checks                    |
//+------------------------------------------------------------------+
#ifndef GSS4_FILTERS_MQH
#define GSS4_FILTERS_MQH

void Filters_Init()
  {
   g_nSes = U_ParseWindows(InpSessions, g_sesA, g_sesB);
   g_nRol = U_ParseWindows(InpRolloverBlock, g_rolA, g_rolB);
   g_nBlk = U_ParseWindows(InpExtraBlackouts, g_blkA, g_blkB);
   g_fridayNoNew = (StringLen(InpFridayNoNewAfter) > 0) ? U_ParseHM(InpFridayNoNewAfter) : -1;
   g_fridayFlat  = (StringLen(InpFridayFlatten) > 0) ? U_ParseHM(InpFridayFlatten) : -1;
  }
//+------------------------------------------------------------------+
string Filters_Reason(const int dir)
  {
   datetime now = TimeCurrent();
   int mins = U_MinutesOfDay(now);

   if(g_killed)
      return "KILL_SWITCH";
   if(g_dayLocked)
      return "DAILY_LOCK";
   if(g_bk.active)
      return "BASKET_OPEN";
   if(g_basketsToday >= InpMaxBasketsPerDay)
      return "MAX_BASKETS";
   if(InpMaxConsecLosses > 0 && g_consecLoss >= InpMaxConsecLosses)
      return "CONSEC_LOSSES";
   if(g_cooldown > 0)
      return "COOLDOWN";
   if(g_nSes > 0 && !U_InAnyWindow(mins, g_sesA, g_sesB, g_nSes))
      return "SESSION";
   if(U_InAnyWindow(mins, g_rolA, g_rolB, g_nRol))
      return "ROLLOVER";
   if(U_InAnyWindow(mins, g_blkA, g_blkB, g_nBlk))
      return "BLACKOUT";
   if(U_Dow(now) == 5 && g_fridayNoNew >= 0 && mins >= g_fridayNoNew)
      return "FRIDAY";
   if(U_Spread() > InpMaxSpreadUSD)
      return "SPREAD";
   if(g_atr1 < InpMinATRUSD)
      return "ATR_LOW";
   if(g_atr1 > InpMaxATRUSD)
      return "ATR_HIGH";
   if(News_Blocked(now))
      return "NEWS";
   if(InpUseHTFBias && g_bias != dir)
      return "BIAS";
   return "";
  }
//+------------------------------------------------------------------+
//| "" when a new basket in direction 'dir' may be opened,           |
//| otherwise a short reason code                                    |
//+------------------------------------------------------------------+
string Filters_Check(const int dir)
  {
   string r = Filters_Reason(dir);
   g_lastFilter = r;
   return r;
  }
#endif
