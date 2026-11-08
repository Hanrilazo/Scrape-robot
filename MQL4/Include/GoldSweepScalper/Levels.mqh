//+------------------------------------------------------------------+
//| Levels.mqh (MT4) - liquidity levels                              |
//| M15 swings, equal highs/lows, previous day H/L, Asian range      |
//+------------------------------------------------------------------+
#ifndef GSS4_LEVELS_MQH
#define GSS4_LEVELS_MQH

LevelInfo g_lv[];
int       g_nLv   = 0;
datetime  g_lvBar = 0;

//+------------------------------------------------------------------+
void Levels_Add(const double price, const bool isHigh, const string kind, const datetime formed, const int prio)
  {
   double tol = MathMax(g_tick * 3.0, 0.02);
   for(int i = 0; i < g_nLv; i++)
     {
      if(g_lv[i].isHigh == isHigh && MathAbs(g_lv[i].price - price) <= tol)
        {
         if(prio > g_lv[i].prio)
           {
            g_lv[i].price  = price;
            g_lv[i].kind   = kind;
            g_lv[i].formed = formed;
            g_lv[i].prio   = prio;
           }
         return;
        }
     }
   ArrayResize(g_lv, g_nLv + 1, 64);
   g_lv[g_nLv].price  = price;
   g_lv[g_nLv].isHigh = isHigh;
   g_lv[g_nLv].kind   = kind;
   g_lv[g_nLv].formed = formed;
   g_lv[g_nLv].prio   = prio;
   g_nLv++;
  }
//+------------------------------------------------------------------+
//| rebuild once per new M15 bar                                     |
//+------------------------------------------------------------------+
void Levels_Rebuild()
  {
   g_nLv = 0;
   ArrayResize(g_lv, 0);

   int got = iBars(_Symbol, PERIOD_M15);
   if(got > 150)
      got = 150;
   if(got < 20)
      return;

   double   mh[];
   double   ml[];
   datetime mt[];
   ArrayResize(mh, got);
   ArrayResize(ml, got);
   ArrayResize(mt, got);
   for(int i = 0; i < got; i++)
     {
      mh[i] = iHigh(_Symbol, PERIOD_M15, i);
      ml[i] = iLow(_Symbol, PERIOD_M15, i);
      mt[i] = iTime(_Symbol, PERIOD_M15, i);
     }

   double   swH[];
   double   swL[];
   datetime tH[];
   datetime tL[];
   int nH = 0;
   int nL = 0;
   int lastI = MathMin(got - 4, 96);
   for(int i = 4; i <= lastI; i++)
     {
      bool isH = true;
      bool isL = true;
      for(int k = 1; k <= 3; k++)
        {
         if(mh[i] <= mh[i - k] || mh[i] <= mh[i + k])
            isH = false;
         if(ml[i] >= ml[i - k] || ml[i] >= ml[i + k])
            isL = false;
        }
      datetime conf = mt[i - 3] + 900;
      if(isH)
        {
         ArrayResize(swH, nH + 1);
         ArrayResize(tH, nH + 1);
         swH[nH] = mh[i];
         tH[nH]  = conf;
         nH++;
        }
      if(isL)
        {
         ArrayResize(swL, nL + 1);
         ArrayResize(tL, nL + 1);
         swL[nL] = ml[i];
         tL[nL]  = conf;
         nL++;
        }
     }

   if(InpUseSwingLevels)
     {
      for(int i = 0; i < nH; i++)
         Levels_Add(swH[i], true, "SWH", tH[i], 1);
      for(int i = 0; i < nL; i++)
         Levels_Add(swL[i], false, "SWL", tL[i], 1);
     }

   if(InpUseEqualLevels && g_atr15 > 0.0)
     {
      double tol = InpEqTolATR * g_atr15;
      for(int a = 0; a < nH; a++)
         for(int b = a + 1; b < nH; b++)
            if(MathAbs(swH[a] - swH[b]) <= tol)
               Levels_Add(MathMax(swH[a], swH[b]), true, "EQH", MathMax(tH[a], tH[b]), 4);
      for(int a = 0; a < nL; a++)
         for(int b = a + 1; b < nL; b++)
            if(MathAbs(swL[a] - swL[b]) <= tol)
               Levels_Add(MathMin(swL[a], swL[b]), false, "EQL", MathMax(tL[a], tL[b]), 4);
     }

   if(InpUsePrevDayLevels)
     {
      double ph = iHigh(_Symbol, PERIOD_D1, 1);
      double pl = iLow(_Symbol, PERIOD_D1, 1);
      datetime ft = iTime(_Symbol, PERIOD_D1, 0);
      if(ph > 0.0 && ft > 0)
         Levels_Add(ph, true, "PDH", ft, 3);
      if(pl > 0.0 && ft > 0)
         Levels_Add(pl, false, "PDL", ft, 3);
     }

   if(InpUseAsianLevels && InpAsianStartHour < InpAsianEndHour)
     {
      datetime now = TimeCurrent();
      datetime ds  = U_DayStart(now);
      datetime s   = ds + InpAsianStartHour * 3600;
      datetime e   = ds + InpAsianEndHour * 3600;
      if(now < e)
        {
         s -= 86400;
         e -= 86400;
        }
      double hi = -DBL_MAX;
      double lo = DBL_MAX;
      int cnt = 0;
      for(int i = 0; i < got; i++)
        {
         if(mt[i] >= s && mt[i] < e)
           {
            hi = MathMax(hi, mh[i]);
            lo = MathMin(lo, ml[i]);
            cnt++;
           }
        }
      if(cnt >= 8)
        {
         Levels_Add(hi, true, "ASH", e, 2);
         Levels_Add(lo, false, "ASL", e, 2);
        }
     }
  }
//+------------------------------------------------------------------+
void Levels_OnBar()
  {
   datetime t = iTime(_Symbol, PERIOD_M15, 0);
   if(t != g_lvBar)
     {
      g_lvBar = t;
      Levels_Rebuild();
     }
  }
#endif
