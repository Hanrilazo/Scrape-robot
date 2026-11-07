//+------------------------------------------------------------------+
//| Panel.mqh - on-chart status text and sweep markers               |
//+------------------------------------------------------------------+
#ifndef GSS_PANEL_MQH
#define GSS_PANEL_MQH

void Panel_Init()
  {
   g_draw = InpShowPanel && !g_isOptim && (!g_isTester || g_isVisual);
  }
//+------------------------------------------------------------------+
void Panel_Update()
  {
   if(!g_draw)
      return;
   string biasTxt = "NEUTRAL";
   if(g_bias > 0)
      biasTxt = "UP";
   else
      if(g_bias < 0)
         biasTxt = "DOWN";
   string filterTxt = (g_lastFilter == "") ? "pass" : g_lastFilter;
   string dailyTxt  = g_dayLocked ? "YES" : "no";
   string killTxt   = g_killed ? "YES" : "no";

   string s = "GoldSweepScalper  " + _Symbol + "\n";
   s += "Server time : " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES) + "\n";
   s += "Spread $    : " + DoubleToString(U_Spread(), 2) + "   ATR(M1) $: " + DoubleToString(g_atr1, 2) + "\n";
   s += "M15 bias    : " + biasTxt + "   levels: " + IntegerToString(g_nLv) + "\n";
   s += "Last filter : " + filterTxt + "\n";
   s += "Day P/L     : " + DoubleToString(g_realizedToday + U_FloatingPnL(), 2)
        + "   baskets: " + IntegerToString(g_basketsToday) + "   consec losses: " + IntegerToString(g_consecLoss) + "\n";
   s += "Locks       : daily=" + dailyTxt + " kill=" + killTxt + " cooldown=" + IntegerToString(g_cooldown) + "\n";
   if(g_bk.active)
     {
      string side = (g_bk.dir > 0) ? "BUY" : "SELL";
      string lk   = g_bk.locked ? "  [LOCKED]" : "";
      s += "BASKET " + side + "  positions=" + IntegerToString(U_CountPositions())
           + " pending=" + IntegerToString(U_CountOrders()) + " floating=" + DoubleToString(U_FloatingPnL(), 2) + lk + "\n";
      s += "  SL " + DoubleToString(g_bk.sl, 2) + "  TP " + DoubleToString(g_bk.tp, 2) + "\n";
     }
   Comment(s);
  }
//+------------------------------------------------------------------+
void Panel_DrawSignal(const SweepSignal &sg, const string outcome)
  {
   if(!g_draw)
      return;
   string nm = "GSS_SW_" + IntegerToString((long)sg.time);
   if(ObjectFind(0, nm) >= 0)
      return;
   color c = (sg.dir < 0) ? clrTomato : clrDodgerBlue;
   if(ObjectCreate(0, nm, OBJ_TREND, 0, sg.time - 900, sg.level, sg.time + 1500, sg.level))
     {
      ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
     }
   string tn = nm + "_t";
   if(ObjectCreate(0, tn, OBJ_TEXT, 0, sg.time, sg.wick))
     {
      ObjectSetString(0, tn, OBJPROP_TEXT, sg.kind + " " + outcome);
      ObjectSetInteger(0, tn, OBJPROP_COLOR, c);
      ObjectSetInteger(0, tn, OBJPROP_FONTSIZE, 8);
     }
  }
//+------------------------------------------------------------------+
void Panel_Cleanup()
  {
   if(!g_draw)
      return;
   Comment("");
   ObjectsDeleteAll(0, "GSS_");
  }
#endif
