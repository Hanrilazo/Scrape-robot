//+------------------------------------------------------------------+
//| Basket.mqh (MT4) - scale-in basket: entry, adds, lock, close     |
//| Every ticket carries the same server-side SL and TP.             |
//| The basket tracks its own ticket numbers (MT4 has no deals).     |
//+------------------------------------------------------------------+
#ifndef GSS4_BASKET_MQH
#define GSS4_BASKET_MQH

#define GSS_E_SERVER_BUSY      4
#define GSS_E_TOO_FREQUENT     8
#define GSS_E_TIMEOUT          128
#define GSS_E_INVALID_STOPS    130
#define GSS_E_PRICE_CHANGED    135
#define GSS_E_OFF_QUOTES       136
#define GSS_E_REQUOTE          138
#define GSS_E_CONTEXT_BUSY     146
#define GSS_E_EXPIRATION       147

//+------------------------------------------------------------------+
bool Exec_Retryable(const int err)
  {
   return (err == GSS_E_SERVER_BUSY || err == GSS_E_TOO_FREQUENT || err == GSS_E_TIMEOUT
           || err == GSS_E_PRICE_CHANGED || err == GSS_E_OFF_QUOTES || err == GSS_E_REQUOTE
           || err == GSS_E_CONTEXT_BUSY);
  }
//+------------------------------------------------------------------+
void Exec_Wait()
  {
   if(!g_isTester)
      Sleep(150);
  }
//+------------------------------------------------------------------+
//| make sure SL/TP of a ticket match; retries a few times           |
//+------------------------------------------------------------------+
bool Exec_SetStops(const int ticket, const double sl, const double tp)
  {
   for(int a = 0; a < 3; a++)
     {
      if(!OrderSelect(ticket, SELECT_BY_TICKET))
         return false;
      if(MathAbs(OrderStopLoss() - sl) < g_tick * 0.5 && MathAbs(OrderTakeProfit() - tp) < g_tick * 0.5)
         return true;
      if(OrderModify(ticket, OrderOpenPrice(), NormalizeDouble(sl, g_digits), NormalizeDouble(tp, g_digits), 0, clrNONE))
         return true;
      int err = GetLastError();
      if(err == 1)
         return true;                // nothing changed
      if(!Exec_Retryable(err))
         break;
      Exec_Wait();
      RefreshRates();
     }
   return false;
  }
//+------------------------------------------------------------------+
bool Exec_CloseTicket(const int ticket)
  {
   for(int a = 0; a < 3; a++)
     {
      if(!OrderSelect(ticket, SELECT_BY_TICKET))
         return false;
      if(OrderCloseTime() > 0)
         return true;
      RefreshRates();
      int ty = OrderType();
      double px = (ty == OP_BUY) ? MarketInfo(_Symbol, MODE_BID) : MarketInfo(_Symbol, MODE_ASK);
      if(OrderClose(ticket, OrderLots(), NormalizeDouble(px, g_digits), InpDeviationPoints, clrNONE))
         return true;
      int err = GetLastError();
      if(!Exec_Retryable(err))
         break;
      Exec_Wait();
     }
   return false;
  }
//+------------------------------------------------------------------+
//| market order with SL/TP. Returns ticket or -1                    |
//+------------------------------------------------------------------+
int Exec_Market(const int dir, const double lot, const double sl, const double tp, const string cmt, int &err)
  {
   err = 0;
   const int cmd = (dir > 0) ? OP_BUY : OP_SELL;
   for(int a = 0; a < 4; a++)
     {
      RefreshRates();
      double price = (dir > 0) ? MarketInfo(_Symbol, MODE_ASK) : MarketInfo(_Symbol, MODE_BID);
      int t = OrderSend(_Symbol, cmd, lot, NormalizeDouble(price, g_digits), InpDeviationPoints,
                        NormalizeDouble(sl, g_digits), NormalizeDouble(tp, g_digits), cmt, InpMagic, 0, clrNONE);
      if(t > 0)
         return t;
      err = GetLastError();
      if(err == GSS_E_INVALID_STOPS)
        {
         //--- some market-execution brokers refuse stops on the open request
         t = OrderSend(_Symbol, cmd, lot, NormalizeDouble(price, g_digits), InpDeviationPoints, 0.0, 0.0, cmt, InpMagic, 0, clrNONE);
         if(t > 0)
           {
            if(Exec_SetStops(t, sl, tp))
               return t;
            Exec_CloseTicket(t);       // never leave a naked position
            err = GSS_E_INVALID_STOPS;
            return -1;
           }
         err = GetLastError();
        }
      if(Exec_Retryable(err))
        {
         Exec_Wait();
         continue;
        }
      break;
     }
   return -1;
  }
//+------------------------------------------------------------------+
int Exec_Pending(const int dir, const double lot, const double price, const double sl, const double tp,
                 const datetime expiration, const string cmt, int &err)
  {
   err = 0;
   datetime expiry = expiration;
   const int cmd = (dir > 0) ? OP_BUYLIMIT : OP_SELLLIMIT;
   for(int a = 0; a < 4; a++)
     {
      int t = OrderSend(_Symbol, cmd, lot, NormalizeDouble(price, g_digits), 0,
                        NormalizeDouble(sl, g_digits), NormalizeDouble(tp, g_digits), cmt, InpMagic, expiry, clrNONE);
      if(t > 0)
         return t;
      err = GetLastError();
      if(err == GSS_E_EXPIRATION)
        {
         expiry = 0;
         continue;
        }
      if(Exec_Retryable(err))
        {
         Exec_Wait();
         RefreshRates();
         continue;
        }
      break;
     }
   return -1;
  }
//+------------------------------------------------------------------+
void Basket_Reset()
  {
   g_bk.active       = false;
   g_bk.id           = 0;
   g_bk.dir          = 0;
   g_bk.openTime     = 0;
   g_bk.levelKind    = "";
   g_bk.level        = 0.0;
   g_bk.wick         = 0.0;
   g_bk.atr          = 0.0;
   g_bk.sl           = 0.0;
   g_bk.tp           = 0.0;
   g_bk.entry1       = 0.0;
   g_bk.planned      = 0;
   g_bk.locked       = false;
   g_bk.addsExpire   = 0;
   g_bk.mfe          = 0.0;
   g_bk.mae          = 0.0;
   g_bk.barsOpen     = 0;
   g_bk.closeReason  = "";
   g_bk.lastLockTry  = 0;
   g_bk.runLen       = 0;
   g_bk.rejPct       = 0.0;
   g_nTk = 0;
   for(int i = 0; i < GSS_MAXTK; i++)
     {
      g_tk[i] = 0;
      g_tkIdx[i] = 0;
      g_tkPx[i] = 0.0;
      g_tkFilled[i] = false;
     }
  }
//+------------------------------------------------------------------+
void Basket_Track(const int ticket, const int idx, const double plannedPx, const bool filled)
  {
   if(g_nTk >= GSS_MAXTK)
      return;
   g_tk[g_nTk]       = ticket;
   g_tkIdx[g_nTk]    = idx;
   g_tkPx[g_nTk]     = plannedPx;
   g_tkFilled[g_nTk] = filled;
   g_nTk++;
  }
//+------------------------------------------------------------------+
int Basket_CommentIdx(const string cm)
  {
   string p[];
   if(StringSplit(cm, '|', p) >= 3)
      return (int)StringToInteger(p[2]);
   return 0;
  }
//+------------------------------------------------------------------+
int Basket_DeletePending()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!U_SelectMine(i))
         continue;
      if(U_IsPos(OrderType()))
         continue;
      int t = OrderTicket();
      if(OrderDelete(t, clrNONE))
         n++;
     }
   return n;
  }
//+------------------------------------------------------------------+
//| close everything; the basket is booked in Basket_Finalize        |
//+------------------------------------------------------------------+
void Basket_CloseAll(const string reason)
  {
   bool first = (g_bk.closeReason == "");
   if(first)
      g_bk.closeReason = reason;
   Basket_DeletePending();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!U_SelectMine(i))
         continue;
      if(!U_IsPos(OrderType()))
         continue;
      Exec_CloseTicket(OrderTicket());
     }
   if(first)
     {
      double px = (g_bk.dir > 0) ? MarketInfo(_Symbol, MODE_BID) : MarketInfo(_Symbol, MODE_ASK);
      Journal_Event("CLOSE_REQUEST", px, 0.0, 0.0, reason);
     }
  }
//+------------------------------------------------------------------+
//| place the first ticket + limit-order adds. returns "" on success |
//| or a short reason why the signal was not traded                  |
//+------------------------------------------------------------------+
string Basket_TryOpen(const SweepSignal &sig)
  {
   const int    dir = sig.dir;
   const double bid = MarketInfo(_Symbol, MODE_BID);
   const double ask = MarketInfo(_Symbol, MODE_ASK);
   g_lastStopDist = 0.0;
   g_lastAdds     = 0;
   if(bid <= 0.0 || ask <= 0.0)
      return "NO_QUOTE";
   if(!g_isTester && (!IsTradeAllowed() || !IsExpertEnabled()))
      return "TRADE_NOT_ALLOWED";

   const double spread  = ask - bid;
   const double ref     = (dir > 0) ? ask : bid;
   const double target  = U_Pip(InpTargetPips);
   const double minDist = U_StopsLevel();

   //--- the sweep is invalid if price already went beyond the wick
   if(dir < 0 && ref >= sig.wick)
      return "WICK_BROKEN";
   if(dir > 0 && ref <= sig.wick)
      return "WICK_BROKEN";

   //--- stop beyond the wick
   double buf = InpSLBufferATR * sig.atr + spread;
   double sl  = (dir > 0) ? U_FloorTick(sig.wick - buf) : U_CeilTick(sig.wick + buf);
   double stopDist = (dir > 0) ? (ref - sl) : (sl - ref);
   g_lastStopDist = stopDist;
   if(stopDist <= 0.0 || stopDist < minDist)
      return "BAD_STOP";
   if(stopDist > InpMaxStopToTarget * target)
      return "STOP_TOO_WIDE";
   if(target < minDist)
      return "TARGET_TOO_CLOSE";

   //--- how many adds fit between entry and the wick
   int T = MathMax(1, MathMin(InpMaxTickets, 6));
   double span = MathAbs(sig.wick - ref);
   int A = T - 1;
   if(!InpSamePriceMode)
     {
      int byStep = (int)MathFloor(span / U_Pip(InpMinAddStepPips)) - 1;
      A = MathMax(0, MathMin(A, byStep));
     }

   double budget = AccountEquity() * InpMaxRiskPerBasketPct / 100.0;
   double px[];
   while(true)
     {
      ArrayResize(px, A + 1);
      px[0] = ref;
      double step = (A > 0 && !InpSamePriceMode) ? span / (A + 1) : 0.0;
      for(int k = 1; k <= A; k++)
         px[k] = (dir > 0) ? ref - k * step : ref + k * step;
      double worst  = Risk_WorstCase(px, A + 1, sl);
      double margin = Risk_MarginNeeded(A + 1);
      bool riskOk   = (InpMaxRiskPerBasketPct <= 0.0) || (worst <= budget);
      bool marginOk = (margin <= AccountFreeMargin() * 0.6);
      if(riskOk && marginOk)
         break;
      if(A == 0)
         return riskOk ? "MARGIN" : "RISK_TOO_BIG";
      A--;
     }
   g_lastAdds = A;

   //--- first ticket at market
   Basket_Reset();
   g_bk.active    = true;
   g_bk.id        = (long)TimeCurrent();
   g_bk.dir       = dir;
   g_bk.openTime  = TimeCurrent();
   g_bk.levelKind = sig.kind;
   g_bk.level     = sig.level;
   g_bk.wick      = sig.wick;
   g_bk.atr       = sig.atr;
   g_bk.runLen    = sig.runLen;
   g_bk.rejPct    = sig.rejPct;
   g_bk.sl        = sl;

   double tp1 = U_RoundTick((dir > 0) ? ref + target : ref - target);
   string cmt = "GSS|" + IntegerToString(g_bk.id) + "|1";
   int err = 0;
   int t1 = Exec_Market(dir, g_lot, sl, tp1, cmt, err);
   if(t1 < 0)
     {
      PrintFormat("GSS: market order failed, error %d", err);
      Journal_Event("ORDER_FAILED", ref, g_lot, 0.0, "error=" + IntegerToString(err));
      Basket_Reset();
      return "ORDER_FAIL_" + IntegerToString(err);
     }
   double fill = ref;
   if(OrderSelect(t1, SELECT_BY_TICKET))
      fill = OrderOpenPrice();
   Basket_Track(t1, 1, ref, true);

   double slip = (dir > 0) ? (fill - ref) : (ref - fill);
   g_bk.entry1 = fill;
   Journal_Event("ENTRY", fill, g_lot, slip / g_pip,
                 StringFormat("req=%.2f sl=%.2f tp=%.2f adds=%d kind=%s", ref, sl, tp1, A, sig.kind));
   if(slip > U_Pip(InpMaxEntrySlipPips))
     {
      Basket_CloseAll("SLIP_ABORT");
      return "SLIPPAGE";
     }

   //--- the target is measured from the real fill of the worst (first) entry
   double tpReal = U_RoundTick((dir > 0) ? fill + target : fill - target);
   g_bk.tp = tpReal;
   if(MathAbs(tpReal - tp1) > g_tick * 0.5)
      Exec_SetStops(t1, sl, tpReal);

   //--- scale-in limit orders between the fill and the wick
   //--- (same-price mode: the extra tickets are market orders opened right now)
   datetime addExpiry = TimeCurrent() + InpAddWindowBars * 60;
   g_bk.addsExpire = addExpiry;

   double span2 = MathAbs(sig.wick - fill);
   double step2 = (A > 0 && !InpSamePriceMode) ? span2 / (A + 1) : 0.0;
   int placed = 0;
   for(int k = 1; k <= A; k++)
     {
      if(InpSamePriceMode)
        {
         string cm = "GSS|" + IntegerToString(g_bk.id) + "|" + IntegerToString(k + 1);
         int errm = 0;
         int tm = Exec_Market(dir, g_lot, sl, tpReal, cm, errm);
         if(tm > 0)
           {
            double fm = ref;
            if(OrderSelect(tm, SELECT_BY_TICKET))
               fm = OrderOpenPrice();
            Basket_Track(tm, k + 1, ref, true);
            placed++;
            Journal_Event("ADD_MARKET", fm, g_lot, ((dir > 0) ? (fm - ref) : (ref - fm)) / g_pip, "n=" + IntegerToString(k + 1));
           }
         else
            Journal_Event("ADD_FAILED", ref, g_lot, 0.0, "error=" + IntegerToString(errm));
         continue;
        }
      double p = U_RoundTick((dir > 0) ? fill - k * step2 : fill + k * step2);
      double mkt = (dir > 0) ? MarketInfo(_Symbol, MODE_ASK) : MarketInfo(_Symbol, MODE_BID);
      double dist = (dir > 0) ? (mkt - p) : (p - mkt);
      if(dist <= 0.0 || dist < minDist)
        {
         Journal_Event("ADD_SKIPPED", p, g_lot, 0.0, "too_close_to_market");
         continue;
        }
      string c2 = "GSS|" + IntegerToString(g_bk.id) + "|" + IntegerToString(k + 1);
      int err2 = 0;
      int t2 = Exec_Pending(dir, g_lot, p, sl, tpReal, addExpiry, c2, err2);
      if(t2 > 0)
        {
         Basket_Track(t2, k + 1, p, false);
         placed++;
         Journal_Event("ADD_PLACED", p, g_lot, 0.0, "n=" + IntegerToString(k + 1));
        }
      else
         Journal_Event("ADD_FAILED", p, g_lot, 0.0, "error=" + IntegerToString(err2));
     }
   g_bk.planned = 1 + placed;

   Journal_Screenshot("entry");
   U_Notify(StringFormat("GoldSweep %s basket %s @%.2f SL %.2f TP %.2f (%d tickets max)",
                         dir > 0 ? "BUY" : "SELL", sig.kind, fill, sl, tpReal, g_bk.planned));
   return "";
  }
//+------------------------------------------------------------------+
//| refresh the state of the tracked tickets, report add fills,      |
//| delete pending adds as soon as any position has closed.          |
//| returns the number of open positions                             |
//+------------------------------------------------------------------+
int Basket_Sync()
  {
   int open = 0;
   bool exitSeen = false;
   for(int i = 0; i < g_nTk; i++)
     {
      if(!OrderSelect(g_tk[i], SELECT_BY_TICKET))
         continue;
      if(!U_IsPos(OrderType()))
         continue;
      if(!g_tkFilled[i])
        {
         g_tkFilled[i] = true;
         if(g_tkIdx[i] > 1)
           {
            double fill = OrderOpenPrice();
            double slip = (g_bk.dir > 0) ? (fill - g_tkPx[i]) : (g_tkPx[i] - fill);
            Journal_Event("ADD_FILLED", fill, OrderLots(), slip / g_pip, "n=" + IntegerToString(g_tkIdx[i]));
           }
        }
      if(OrderCloseTime() > 0)
         exitSeen = true;
      else
         open++;
     }
   if(exitSeen)
      Basket_DeletePending();
   return open;
  }
//+------------------------------------------------------------------+
//| move all SLs to break-even + offset once price ran far enough    |
//| and stop scaling in (pending adds are deleted)                   |
//+------------------------------------------------------------------+
void Basket_CheckLock()
  {
   if(g_bk.locked || InpLockTriggerPips <= 0.0)
      return;
   datetime now = TimeCurrent();
   if(now == g_bk.lastLockTry)
      return;
   g_bk.lastLockTry = now;

   double avg = 0.0;
   double vol = 0.0;
   U_AvgEntry(avg, vol);
   if(vol <= 0.0)
      return;
   double comm = (g_contract > 0.0) ? InpCommissionPerLotRT / g_contract : 0.0;
   double bid  = MarketInfo(_Symbol, MODE_BID);
   double ask  = MarketInfo(_Symbol, MODE_ASK);
   bool buy = (g_bk.dir > 0);
   double fav = buy ? (bid - avg - comm) : (avg - ask - comm);
   if(fav < U_Pip(InpLockTriggerPips))
      return;

   double newSl = buy ? U_CeilTick(avg + comm + U_Pip(InpLockOffsetPips))
                      : U_FloorTick(avg - comm - U_Pip(InpLockOffsetPips));
   double dist = buy ? (bid - newSl) : (newSl - ask);
   if(dist <= 0.0 || dist < U_StopsLevel())
      return;

   Basket_DeletePending();
   bool allOk = true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!U_SelectMine(i))
         continue;
      if(!U_IsPos(OrderType()))
         continue;
      int t = OrderTicket();
      double curSl = OrderStopLoss();
      double curTp = OrderTakeProfit();
      bool better = buy ? (curSl < newSl - g_tick * 0.5) : (curSl <= 0.0 || curSl > newSl + g_tick * 0.5);
      if(!better)
         continue;
      if(!Exec_SetStops(t, newSl, curTp))
         allOk = false;
     }
   if(allOk)
     {
      g_bk.locked = true;
      g_bk.sl = newSl;
      Journal_Event("LOCK", newSl, vol, 0.0, StringFormat("avg=%.2f fav_pips=%.1f", avg, fav / g_pip));
     }
  }
//+------------------------------------------------------------------+
//| book the closed basket into journal, stats and daily counters    |
//+------------------------------------------------------------------+
void Basket_Finalize()
  {
   Basket_DeletePending();

   double   entVol = 0.0, entW = 0.0, exVol = 0.0, exW = 0.0;
   double   gross = 0.0, comm = 0.0, swap = 0.0, net = 0.0, t1Net = 0.0;
   int      nFilled = 0;
   datetime closeT = 0;
   string   lastComment = "";
   double   lastClosePx = 0.0, lastSl = 0.0, lastTp = 0.0;

   for(int i = 0; i < g_nTk; i++)
     {
      if(!OrderSelect(g_tk[i], SELECT_BY_TICKET))
         continue;
      if(!U_IsPos(OrderType()))
         continue;
      nFilled++;
      double v  = OrderLots();
      double pr = OrderProfit();
      double cm = OrderCommission();
      double sw = OrderSwap();
      entVol += v;
      entW   += v * OrderOpenPrice();
      gross  += pr;
      comm   += cm;
      swap   += sw;
      double tn = pr + cm + sw;
      net += tn;
      if(g_tkIdx[i] <= 1)
         t1Net += tn;
      if(OrderCloseTime() > 0)
        {
         exVol += v;
         exW   += v * OrderClosePrice();
         if(OrderCloseTime() >= closeT)
           {
            closeT      = OrderCloseTime();
            lastComment = OrderComment();
            lastClosePx = OrderClosePrice();
            lastSl      = OrderStopLoss();
            lastTp      = OrderTakeProfit();
           }
        }
     }
   double addsNet  = net - t1Net;
   double avgEntry = (entVol > 0.0) ? entW / entVol : 0.0;
   double exitAvg  = (exVol > 0.0) ? exW / exVol : 0.0;

   string reason = g_bk.closeReason;
   if(reason == "")
     {
      double tol = MathMax(2.0 * g_tick, U_Pip(0.5));
      if(StringFind(lastComment, "[tp]") >= 0)
         reason = "TP";
      else
         if(StringFind(lastComment, "[sl]") >= 0)
            reason = g_bk.locked ? "LOCK_SL" : "SL";
         else
            if(lastTp > 0.0 && MathAbs(lastClosePx - lastTp) <= tol)
               reason = "TP";
            else
               if(lastSl > 0.0 && MathAbs(lastClosePx - lastSl) <= tol)
                  reason = g_bk.locked ? "LOCK_SL" : "SL";
               else
                  reason = "MANUAL_OR_OTHER";
     }

   //--- baskets.csv
   if(g_jOn)
     {
      Rw_Begin();
      Rw("basket_id"); Rw("dir"); Rw("level_kind"); Rw("level"); Rw("wick"); Rw("open_time"); Rw("close_time");
      Rw("duration_s"); Rw("tickets_filled"); Rw("tickets_planned"); Rw("lots"); Rw("entry1"); Rw("avg_entry");
      Rw("exit_avg"); Rw("sl"); Rw("tp"); Rw("locked"); Rw("close_reason"); Rw("mfe_usd"); Rw("mae_usd");
      Rw("gross"); Rw("commission"); Rw("swap"); Rw("net"); Rw("ticket1_net"); Rw("adds_net");
      Rw("balance_after"); Rw("atr_m1"); Rw("run_len"); Rw("rej_pct");
      string hdr = g_row;

      Rw_Begin();
      RwI(g_bk.id);
      Rw(g_bk.dir > 0 ? "BUY" : "SELL");
      RwS(g_bk.levelKind);
      RwD(g_bk.level, 2);
      RwD(g_bk.wick, 2);
      RwT(g_bk.openTime);
      RwT(closeT);
      RwI(closeT > 0 ? (long)(closeT - g_bk.openTime) : 0);
      RwI(nFilled);
      RwI(g_bk.planned);
      RwD(entVol, 2);
      RwD(g_bk.entry1, 2);
      RwD(avgEntry, 2);
      RwD(exitAvg, 2);
      RwD(g_bk.sl, 2);
      RwD(g_bk.tp, 2);
      RwI(g_bk.locked ? 1 : 0);
      RwS(reason);
      RwD(g_bk.mfe, 2);
      RwD(g_bk.mae, 2);
      RwD(gross, 2);
      RwD(comm, 2);
      RwD(swap, 2);
      RwD(net, 2);
      RwD(t1Net, 2);
      RwD(addsNet, 2);
      RwD(AccountBalance(), 2);
      RwD(g_bk.atr, 2);
      RwI(g_bk.runLen);
      RwD(g_bk.rejPct, 0);
      Journal_Append("baskets.csv", hdr, g_row);
     }
   Journal_Event("BASKET_CLOSED", exitAvg, entVol, 0.0,
                 StringFormat("reason=%s net=%.2f tickets=%d", reason, net, nFilled));
   Journal_Screenshot("exit");

   Stats_Add(net, t1Net, addsNet);
   Risk_AfterBasket(net);
   PrintFormat("GSS: basket %s closed (%s) tickets=%d net=%.2f", IntegerToString(g_bk.id), reason, nFilled, net);
   U_Notify(StringFormat("GoldSweep basket closed %s net %.2f", reason, net));
   Basket_Reset();
  }
//+------------------------------------------------------------------+
//| per-tick (and per-second) management while a basket is open      |
//+------------------------------------------------------------------+
void Basket_Manage(const bool newBar)
  {
   int np = Basket_Sync();
   if(np == 0)
     {
      Basket_Finalize();
      return;
     }

   //--- already closing: keep retrying until the positions are gone
   if(g_bk.closeReason != "")
     {
      Basket_CloseAll(g_bk.closeReason);
      return;
     }

   double fl = U_FloatingPnL();
   if(fl > g_bk.mfe)
      g_bk.mfe = fl;
   if(fl < g_bk.mae)
      g_bk.mae = fl;

   string r = "";
   if(Risk_GuardBreached(r))
     {
      Risk_Lock(r);
      Basket_CloseAll(r);
      return;
     }
   if(InpMaxBasketLossUSD > 0.0 && fl <= -InpMaxBasketLossUSD)
     {
      Basket_CloseAll("MAX_LOSS");
      return;
     }
   Basket_CheckLock();

   if(!newBar)
      return;
   g_bk.barsOpen++;
   datetime now = TimeCurrent();
   if(U_CountPendings() > 0 && g_bk.addsExpire > 0 && now >= g_bk.addsExpire)
     {
      int d = Basket_DeletePending();
      Journal_Event("ADDS_EXPIRED", 0.0, 0.0, 0.0, "deleted=" + IntegerToString(d));
     }
   if(InpMaxHoldBars > 0 && g_bk.barsOpen >= InpMaxHoldBars)
     {
      Basket_CloseAll("TIME_STOP");
      return;
     }
   if(U_Dow(now) == 5 && g_fridayFlat >= 0 && U_MinutesOfDay(now) >= g_fridayFlat)
     {
      Basket_CloseAll("FRIDAY_FLATTEN");
      return;
     }
   if(News_Within(now, InpFlattenBeforeNewsMin))
     {
      Basket_CloseAll("NEWS_FLATTEN");
      return;
     }
  }
//+------------------------------------------------------------------+
//| adopt orders left over from an earlier run / terminal restart    |
//+------------------------------------------------------------------+
void Basket_Restore()
  {
   Basket_Reset();
   int np = U_CountPositions();
   if(np == 0)
     {
      int d = Basket_DeletePending();
      if(d > 0)
         Print("GSS: removed ", d, " orphan pending order(s)");
      return;
     }
   datetime tmin = 0;
   long id = 0;
   int dir = 0;
   double sl = 0.0;
   double tp = 0.0;
   double e1 = 0.0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!U_SelectMine(i))
         continue;
      int ty = OrderType();
      int tk = OrderTicket();
      int idx = Basket_CommentIdx(OrderComment());
      if(idx <= 0)
         idx = g_nTk + 1;
      Basket_Track(tk, idx, OrderOpenPrice(), U_IsPos(ty));
      if(!U_IsPos(ty))
         continue;
      datetime tt = OrderOpenTime();
      if(tmin == 0 || tt < tmin)
        {
         tmin = tt;
         dir  = (ty == OP_BUY) ? 1 : -1;
         sl   = OrderStopLoss();
         tp   = OrderTakeProfit();
         e1   = OrderOpenPrice();
         string p[];
         if(StringSplit(OrderComment(), '|', p) >= 3)
            id = StringToInteger(p[1]);
        }
     }
   double avg = 0.0;
   double vol = 0.0;
   U_AvgEntry(avg, vol);
   g_bk.active     = true;
   g_bk.id         = (id != 0) ? id : (long)tmin;
   g_bk.dir        = dir;
   g_bk.openTime   = tmin;
   g_bk.levelKind  = "RESTORED";
   g_bk.sl         = sl;
   g_bk.tp         = tp;
   g_bk.entry1     = e1;
   g_bk.planned    = g_nTk;
   g_bk.barsOpen   = (int)((TimeCurrent() - tmin) / 60);
   g_bk.addsExpire = tmin + InpAddWindowBars * 60;
   g_bk.locked     = (dir > 0) ? (sl >= avg && sl > 0.0) : (sl > 0.0 && sl <= avg);
   PrintFormat("GSS: adopted existing basket id=%s dir=%d positions=%d", IntegerToString(g_bk.id), dir, np);
  }
#endif
