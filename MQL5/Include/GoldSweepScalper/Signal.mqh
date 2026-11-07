//+------------------------------------------------------------------+
//| Signal.mqh - liquidity sweep detection                           |
//|                                                                  |
//| 1. a run of >= N push candles ends on the bar BEFORE the breach  |
//| 2. the breach bar(s) pierce an untouched liquidity level by      |
//|    SweepMinATR..SweepMaxATR x ATR                                |
//| 3. bar[1] closes back inside the level (sweep, not breakout)     |
//| 4. bar[1] shows slowdown: long rejection wick + small body       |
//+------------------------------------------------------------------+
#ifndef GSS_SIGNAL_MQH
#define GSS_SIGNAL_MQH

struct PendingSignal
  {
   bool        active;
   SweepSignal sig;
   int         barsLeft;
  };
PendingSignal g_pend;

//+------------------------------------------------------------------+
//| f = index of the first breach bar: 1 (single bar sweep) or 2     |
//| (bar 2 closed outside the level, bar 1 closed back inside)       |
//+------------------------------------------------------------------+
bool Signal_TestBreach(const int li, const int f, const double atr, SweepSignal &s)
  {
   const double L = g_lv[li].price;
   const bool isHigh = g_lv[li].isHigh;
   const int rn = ArraySize(g_rates);
   if(rn < 25)
      return false;

   double ext = 0.0;
   if(isHigh)
     {
      if(!(g_rates[1].close < L))
         return false;
      if(f == 1)
        {
         if(!(g_rates[1].high > L))
            return false;
        }
      else
        {
         if(!(g_rates[2].high > L) || !(g_rates[2].close > L))
            return false;
        }
      ext = g_rates[1].high;
      if(f == 2)
         ext = MathMax(ext, g_rates[2].high);
     }
   else
     {
      if(!(g_rates[1].close > L))
         return false;
      if(f == 1)
        {
         if(!(g_rates[1].low < L))
            return false;
        }
      else
        {
         if(!(g_rates[2].low < L) || !(g_rates[2].close < L))
            return false;
        }
      ext = g_rates[1].low;
      if(f == 2)
         ext = MathMin(ext, g_rates[2].low);
     }

   //--- sweep depth
   double depth = isHigh ? (ext - L) : (L - ext);
   if(depth < InpSweepMinATR * atr || depth > InpSweepMaxATR * atr)
      return false;

   //--- run of push candles directly before the breach
   int first = f + 1;
   int runLen = 0;
   for(int k = first; k < first + 15 && k < rn; k++)
     {
      bool push = isHigh ? (g_rates[k].close > g_rates[k].open) : (g_rates[k].close < g_rates[k].open);
      if(!push)
         break;
      runLen++;
     }
   double runMove = 0.0;
   if(runLen > 0)
      runMove = isHigh ? (g_rates[first].close - g_rates[first + runLen - 1].open)
                       : (g_rates[first + runLen - 1].open - g_rates[first].close);
   if(InpMinRunCandles > 0)
     {
      if(runLen < InpMinRunCandles)
         return false;
      if(runMove < InpRunMinATR * atr)
         return false;
     }

   //--- slowdown: small body compared with the run
   int nb = (InpMinRunCandles > 0) ? MathMin(runLen, InpMinRunCandles + 2) : 3;
   double sumBody = 0.0;
   double sumTv = 0.0;
   int cb = 0;
   for(int k = first; k < first + nb && k < rn; k++)
     {
      sumBody += MathAbs(g_rates[k].close - g_rates[k].open);
      sumTv   += (double)g_rates[k].tick_volume;
      cb++;
     }
   double avgBody = (cb > 0) ? sumBody / cb : 0.0;
   double body1 = MathAbs(g_rates[1].close - g_rates[1].open);
   double bodyRatio = (avgBody > 0.0) ? body1 / avgBody : 999.0;
   if(bodyRatio > InpBodyRatioMax)
      return false;

   //--- slowdown: rejection wick on the closing bar
   double rng = isHigh ? (ext - g_rates[1].low) : (g_rates[1].high - ext);
   if(rng <= 0.0)
      return false;
   double bodyEdge = isHigh ? MathMax(g_rates[1].open, g_rates[1].close) : MathMin(g_rates[1].open, g_rates[1].close);
   double wickLen = isHigh ? (ext - bodyEdge) : (bodyEdge - ext);
   double rej = 100.0 * wickLen / rng;
   if(rej < InpRejectWickPct)
      return false;

   //--- level must be untouched from its formation up to the breach
   int fs = iBarShift(_Symbol, PERIOD_M1, g_lv[li].formed, false);
   if(fs < 0)
      return false;
   int start = f + 1;
   int cnt = fs - start + 1;
   if(cnt >= 1)
     {
      if(isHigh)
        {
         int ix = iHighest(_Symbol, PERIOD_M1, MODE_HIGH, cnt, start);
         if(ix >= 0 && iHigh(_Symbol, PERIOD_M1, ix) >= L)
            return false;
        }
      else
        {
         int ix = iLowest(_Symbol, PERIOD_M1, MODE_LOW, cnt, start);
         if(ix >= 0 && iLow(_Symbol, PERIOD_M1, ix) <= L)
            return false;
        }
     }

   s.found        = true;
   s.dir          = isHigh ? -1 : 1;
   s.kind         = g_lv[li].kind;
   s.level        = L;
   s.formed       = g_lv[li].formed;
   s.wick         = ext;
   s.depthAtr     = depth / atr;
   s.atr          = atr;
   s.runLen       = runLen;
   s.runAtr       = runMove / atr;
   s.rejPct       = rej;
   s.bodyRatio    = bodyRatio;
   s.tvRatio      = (cb > 0 && sumTv > 0.0) ? (double)g_rates[1].tick_volume / (sumTv / cb) : 0.0;
   s.confirmLevel = isHigh ? g_rates[1].low : g_rates[1].high;
   s.time         = g_rates[1].time;
   s.prio         = g_lv[li].prio;
   return true;
  }
//+------------------------------------------------------------------+
bool Signal_Detect(SweepSignal &out)
  {
   out.found = false;
   double atr = g_atr1;
   if(atr <= 0.0 || g_nLv == 0 || ArraySize(g_rates) < 25)
      return false;
   int maxF = (InpSweepWindowBars >= 2) ? 2 : 1;
   datetime barNow = g_rates[0].time;
   bool have = false;
   for(int i = 0; i < g_nLv; i++)
     {
      if((barNow - g_lv[i].formed) < InpMinLevelAgeMin * 60)
         continue;
      SweepSignal s;
      for(int f = 1; f <= maxF; f++)
        {
         if(Signal_TestBreach(i, f, atr, s))
           {
            if(!have || s.prio > out.prio || (s.prio == out.prio && s.depthAtr > out.depthAtr))
              {
               out = s;
               have = true;
              }
            break;
           }
        }
     }
   out.found = have;
   return have;
  }
//+------------------------------------------------------------------+
//| detect, filter, then trade (aggressive) or arm a pending signal  |
//+------------------------------------------------------------------+
void Signal_Scan()
  {
   SweepSignal s;
   if(!Signal_Detect(s))
      return;
   g_lastStopDist = 0.0;
   g_lastAdds = 0;
   string reason = Filters_Check(s.dir);
   if(reason != "")
     {
      Journal_Signal(s, reason);
      Panel_DrawSignal(s, reason);
      return;
     }
   if(InpEntryMode == ENTRY_CONFIRMED)
     {
      g_pend.active   = true;
      g_pend.sig      = s;
      g_pend.barsLeft = InpConfirmBars;
      Panel_DrawSignal(s, "PENDING");
      return;
     }
   string res = Basket_TryOpen(s);
   string outcome = (res == "") ? "TRADED" : res;
   Journal_Signal(s, outcome);
   Panel_DrawSignal(s, outcome);
  }
//+------------------------------------------------------------------+
//| confirmed-entry mode: wait for a close beyond the sweep candle   |
//+------------------------------------------------------------------+
void Pending_Process()
  {
   if(!g_pend.active)
      return;
   g_pend.barsLeft--;
   SweepSignal s = g_pend.sig;
   const bool sell = (s.dir < 0);
   const double hi1 = g_rates[1].high;
   const double lo1 = g_rates[1].low;
   const double cl1 = g_rates[1].close;

   bool broken = sell ? (hi1 > s.wick) : (lo1 < s.wick);
   if(broken)
     {
      g_pend.active = false;
      Journal_Signal(s, "CONFIRM_FAILED");
      return;
     }
   bool confirmed = sell ? (cl1 < s.confirmLevel) : (cl1 > s.confirmLevel);
   if(confirmed)
     {
      g_pend.active = false;
      string reason = Filters_Check(s.dir);
      if(reason != "")
        {
         Journal_Signal(s, reason);
         return;
        }
      g_lastStopDist = 0.0;
      g_lastAdds = 0;
      string res = Basket_TryOpen(s);
      Journal_Signal(s, (res == "") ? "TRADED" : res);
      return;
     }
   if(g_pend.barsLeft <= 0)
     {
      g_pend.active = false;
      Journal_Signal(s, "CONFIRM_TIMEOUT");
     }
  }
#endif
