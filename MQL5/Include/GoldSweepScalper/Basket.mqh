//+------------------------------------------------------------------+
//| Basket.mqh - scale-in basket: entry, adds, lock, close, journal  |
//| Every ticket carries the same server-side SL and TP.             |
//+------------------------------------------------------------------+
#ifndef GSS_BASKET_MQH
#define GSS_BASKET_MQH

int g_fillIdx = 0;

//+------------------------------------------------------------------+
void Exec_NextFilling()
  {
   g_fillIdx = (g_fillIdx + 1) % 3;
   if(g_fillIdx == 0)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      if(g_fillIdx == 1)
         g_trade.SetTypeFilling(ORDER_FILLING_IOC);
      else
         g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
  }
//+------------------------------------------------------------------+
bool Exec_Market(const int dir, const double lot, const double sl, const double tp, const string cmt, uint &rc)
  {
   rc = 0;
   for(int attempt = 0; attempt < 4; attempt++)
     {
      bool ok;
      if(dir > 0)
         ok = g_trade.Buy(lot, _Symbol, 0.0, sl, tp, cmt);
      else
         ok = g_trade.Sell(lot, _Symbol, 0.0, sl, tp, cmt);
      rc = g_trade.ResultRetcode();
      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL))
         return true;
      if(rc == TRADE_RETCODE_INVALID_FILL)
        {
         Exec_NextFilling();
         continue;
        }
      if(rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED || rc == TRADE_RETCODE_PRICE_OFF)
        {
         if(!g_isTester)
            Sleep(100);
         continue;
        }
      break;
     }
   return false;
  }
//+------------------------------------------------------------------+
bool Exec_Pending(const int dir, const double lot, const double price, const double sl, const double tp,
                  const datetime expiration, const string cmt, uint &rc)
  {
   rc = 0;
   datetime expiry = expiration;
   ENUM_ORDER_TYPE_TIME tt = (expiry > 0) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;
   for(int attempt = 0; attempt < 4; attempt++)
     {
      bool ok;
      if(dir > 0)
         ok = g_trade.BuyLimit(lot, price, _Symbol, sl, tp, tt, expiry, cmt);
      else
         ok = g_trade.SellLimit(lot, price, _Symbol, sl, tp, tt, expiry, cmt);
      rc = g_trade.ResultRetcode();
      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED))
         return true;
      if(rc == TRADE_RETCODE_INVALID_FILL)
        {
         Exec_NextFilling();
         continue;
        }
      if(rc == TRADE_RETCODE_INVALID_EXPIRATION)
        {
         tt = ORDER_TIME_GTC;
         expiry = 0;
         continue;
        }
      if(rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED)
        {
         if(!g_isTester)
            Sleep(100);
         continue;
        }
      break;
     }
   return false;
  }
//+------------------------------------------------------------------+
//| actual open price of the first position of the basket            |
//+------------------------------------------------------------------+
double Exec_FillPrice(const double fallback)
  {
   ulong t = U_FirstPositionTicket();
   if(t != 0 && PositionSelectByTicket(t))
     {
      double p = PositionGetDouble(POSITION_PRICE_OPEN);
      if(p > 0.0)
         return p;
     }
   ulong deal = g_trade.ResultDeal();
   if(deal > 0 && HistoryDealSelect(deal))
     {
      double p2 = HistoryDealGetDouble(deal, DEAL_PRICE);
      if(p2 > 0.0)
         return p2;
     }
   double p3 = g_trade.ResultPrice();
   if(p3 > 0.0)
      return p3;
   return fallback;
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
   g_bk.finalizeFlag = false;
   g_bk.noPosSince   = 0;
   g_bk.lastLockTry  = 0;
   g_bk.runLen       = 0;
   g_bk.rejPct       = 0.0;
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
      ulong t = OrderGetTicket(i);
      if(t == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      if(g_trade.OrderDelete(t))
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
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      for(int a = 0; a < 3; a++)
        {
         if(g_trade.PositionClose(t, (ulong)InpDeviationPoints))
            break;
         if(!g_isTester)
            Sleep(100);
        }
     }
   if(first)
      Journal_Event("CLOSE_REQUEST", (g_bk.dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK),
                    0.0, 0.0, reason);
  }
//+------------------------------------------------------------------+
//| place the first ticket + limit-order adds. returns "" on success |
//| or a short reason why the signal was not traded                  |
//+------------------------------------------------------------------+
string Basket_TryOpen(const SweepSignal &sig)
  {
   const int    dir    = sig.dir;
   const double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   g_lastStopDist = 0.0;
   g_lastAdds     = 0;
   if(bid <= 0.0 || ask <= 0.0)
      return "NO_QUOTE";

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
   int byStep = (int)MathFloor(span / U_Pip(InpMinAddStepPips)) - 1;
   A = MathMax(0, MathMin(A, byStep));

   double budget = AccountInfoDouble(ACCOUNT_EQUITY) * InpMaxRiskPerBasketPct / 100.0;
   double px[];
   while(true)
     {
      ArrayResize(px, A + 1);
      px[0] = ref;
      double step = (A > 0) ? span / (A + 1) : 0.0;
      for(int k = 1; k <= A; k++)
         px[k] = (dir > 0) ? ref - k * step : ref + k * step;
      double worst  = Risk_WorstCase(dir, px, A + 1, sl);
      double margin = Risk_MarginNeeded(dir, A + 1, ref);
      bool riskOk   = (InpMaxRiskPerBasketPct <= 0.0) || (worst <= budget);
      bool marginOk = (margin <= AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.6);
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
   uint rc = 0;
   if(!Exec_Market(dir, g_lot, sl, tp1, cmt, rc))
     {
      PrintFormat("GSS: market order failed, retcode %d (%s)", (int)rc, g_trade.ResultRetcodeDescription());
      Journal_Event("ORDER_FAILED", ref, g_lot, 0.0, "retcode=" + IntegerToString((int)rc));
      Basket_Reset();
      return "ORDER_FAIL_" + IntegerToString((int)rc);
     }

   double fill = Exec_FillPrice(ref);
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
   ulong pt = U_FirstPositionTicket();
   if(pt != 0 && MathAbs(tpReal - tp1) > g_tick * 0.5)
      g_trade.PositionModify(pt, sl, tpReal);

   //--- scale-in limit orders between the fill and the wick
   datetime addExpiry = 0;
   if((SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE) & SYMBOL_EXPIRATION_SPECIFIED) != 0)
      addExpiry = TimeCurrent() + InpAddWindowBars * 60;
   g_bk.addsExpire = TimeCurrent() + InpAddWindowBars * 60;

   double span2 = MathAbs(sig.wick - fill);
   double step2 = (A > 0) ? span2 / (A + 1) : 0.0;
   int placed = 0;
   for(int k = 1; k <= A; k++)
     {
      double p = U_RoundTick((dir > 0) ? fill - k * step2 : fill + k * step2);
      double mkt = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double dist = (dir > 0) ? (mkt - p) : (p - mkt);
      if(dist <= 0.0 || dist < minDist)
        {
         Journal_Event("ADD_SKIPPED", p, g_lot, 0.0, "too_close_to_market");
         continue;
        }
      string c2 = "GSS|" + IntegerToString(g_bk.id) + "|" + IntegerToString(k + 1);
      uint rc2 = 0;
      if(Exec_Pending(dir, g_lot, p, sl, tpReal, addExpiry, c2, rc2))
        {
         placed++;
         Journal_Event("ADD_PLACED", p, g_lot, 0.0, "n=" + IntegerToString(k + 1));
        }
      else
         Journal_Event("ADD_FAILED", p, g_lot, 0.0, "retcode=" + IntegerToString((int)rc2));
     }
   g_bk.planned = 1 + placed;

   Journal_Screenshot("entry");
   U_Notify(StringFormat("GoldSweep %s basket %s @%.2f SL %.2f TP %.2f (%d tickets max)",
                         dir > 0 ? "BUY" : "SELL", sig.kind, fill, sl, tpReal, g_bk.planned));
   return "";
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
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
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
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      double curSl = PositionGetDouble(POSITION_SL);
      double curTp = PositionGetDouble(POSITION_TP);
      bool better = buy ? (curSl < newSl - g_tick * 0.5) : (curSl <= 0.0 || curSl > newSl + g_tick * 0.5);
      if(!better)
         continue;
      if(!g_trade.PositionModify(t, newSl, curTp))
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

   ulong    pid[];
   int      pidx[];
   double   pnet[];
   int      np = 0;
   double   entVol = 0.0, entW = 0.0, exVol = 0.0, exW = 0.0;
   double   gross = 0.0, comm = 0.0, swap = 0.0;
   datetime closeT = 0;
   ENUM_DEAL_REASON lastReason = DEAL_REASON_EXPERT;
   string   tag = "|" + IntegerToString(g_bk.id) + "|";

   if(HistorySelect(g_bk.openTime - 300, TimeCurrent() + 300))
     {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0)
            continue;
         if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic)
            continue;
         if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol)
            continue;
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN)
            continue;
         string cm = HistoryDealGetString(d, DEAL_COMMENT);
         if(StringFind(cm, tag) < 0)
            continue;
         ArrayResize(pid, np + 1);
         ArrayResize(pidx, np + 1);
         ArrayResize(pnet, np + 1);
         pid[np]  = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
         pidx[np] = Basket_CommentIdx(cm);
         pnet[np] = 0.0;
         double v = HistoryDealGetDouble(d, DEAL_VOLUME);
         entVol += v;
         entW   += v * HistoryDealGetDouble(d, DEAL_PRICE);
         np++;
        }
      for(int i = 0; i < total; i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0)
            continue;
         if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic)
            continue;
         ENUM_DEAL_TYPE ty = (ENUM_DEAL_TYPE)HistoryDealGetInteger(d, DEAL_TYPE);
         if(ty != DEAL_TYPE_BUY && ty != DEAL_TYPE_SELL)
            continue;
         ulong p = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
         int k = -1;
         for(int j = 0; j < np; j++)
            if(pid[j] == p)
               k = j;
         if(k < 0)
            continue;
         double pr = HistoryDealGetDouble(d, DEAL_PROFIT);
         double cm2 = HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
         double sw = HistoryDealGetDouble(d, DEAL_SWAP);
         pnet[k] += pr + cm2 + sw;
         gross += pr;
         comm  += cm2;
         swap  += sw;
         ENUM_DEAL_ENTRY en = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY);
         if(en == DEAL_ENTRY_OUT || en == DEAL_ENTRY_OUT_BY || en == DEAL_ENTRY_INOUT)
           {
            double v = HistoryDealGetDouble(d, DEAL_VOLUME);
            exVol += v;
            exW   += v * HistoryDealGetDouble(d, DEAL_PRICE);
            datetime dt = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
            if(dt >= closeT)
              {
               closeT = dt;
               lastReason = (ENUM_DEAL_REASON)HistoryDealGetInteger(d, DEAL_REASON);
              }
           }
        }
     }

   double net = 0.0;
   double t1Net = 0.0;
   for(int j = 0; j < np; j++)
     {
      net += pnet[j];
      if(pidx[j] <= 1)
         t1Net += pnet[j];
     }
   double addsNet = net - t1Net;
   double avgEntry = (entVol > 0.0) ? entW / entVol : 0.0;
   double exitAvg  = (exVol > 0.0) ? exW / exVol : 0.0;

   string reason = g_bk.closeReason;
   if(reason == "")
     {
      switch(lastReason)
        {
         case DEAL_REASON_TP:
            reason = "TP";
            break;
         case DEAL_REASON_SL:
            reason = g_bk.locked ? "LOCK_SL" : "SL";
            break;
         case DEAL_REASON_SO:
            reason = "STOP_OUT";
            break;
         case DEAL_REASON_CLIENT:
         case DEAL_REASON_MOBILE:
         case DEAL_REASON_WEB:
            reason = "MANUAL";
            break;
         default:
            reason = "OTHER";
        }
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
      RwI(np);
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
      RwD(AccountInfoDouble(ACCOUNT_BALANCE), 2);
      RwD(g_bk.atr, 2);
      RwI(g_bk.runLen);
      RwD(g_bk.rejPct, 0);
      Journal_Append("baskets.csv", hdr, g_row);
     }
   Journal_Event("BASKET_CLOSED", exitAvg, entVol, 0.0,
                 StringFormat("reason=%s net=%.2f tickets=%d", reason, net, np));
   Journal_Screenshot("exit");

   Stats_Add(net, t1Net, addsNet);
   Risk_AfterBasket(net);
   PrintFormat("GSS: basket %s closed (%s) tickets=%d net=%.2f", IntegerToString(g_bk.id), reason, np, net);
   U_Notify(StringFormat("GoldSweep basket closed %s net %.2f", reason, net));
   Basket_Reset();
  }
//+------------------------------------------------------------------+
//| per-tick management while a basket is open                       |
//+------------------------------------------------------------------+
void Basket_Manage(const bool newBar)
  {
   int np = U_CountPositions();
   if(np == 0)
     {
      if(g_bk.noPosSince == 0)
         g_bk.noPosSince = TimeCurrent();
      if(g_bk.finalizeFlag || TimeCurrent() - g_bk.noPosSince >= 3)
         Basket_Finalize();
      return;
     }
   g_bk.noPosSince = 0;

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
   if(U_CountOrders() > 0 && g_bk.addsExpire > 0 && now >= g_bk.addsExpire)
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
//| trade transaction hooks                                          |
//+------------------------------------------------------------------+
void Basket_OnEntryDeal(const ulong deal)
  {
   if(!g_bk.active)
      return;
   string cm = HistoryDealGetString(deal, DEAL_COMMENT);
   if(StringFind(cm, "|" + IntegerToString(g_bk.id) + "|") < 0)
      return;
   int idx = Basket_CommentIdx(cm);
   if(idx <= 1)
      return;
   double fill = HistoryDealGetDouble(deal, DEAL_PRICE);
   double vol  = HistoryDealGetDouble(deal, DEAL_VOLUME);
   double req  = fill;
   ulong ord = (ulong)HistoryDealGetInteger(deal, DEAL_ORDER);
   if(HistoryOrderSelect(ord))
      req = HistoryOrderGetDouble(ord, ORDER_PRICE_OPEN);
   double slip = (g_bk.dir > 0) ? (fill - req) : (req - fill);
   Journal_Event("ADD_FILLED", fill, vol, slip / g_pip, "n=" + IntegerToString(idx));
  }
//+------------------------------------------------------------------+
void Basket_OnExitDeal(const ulong deal)
  {
   if(!g_bk.active)
      return;
   g_bk.finalizeFlag = true;
   Basket_DeletePending();
  }
//+------------------------------------------------------------------+
//| adopt positions left over from an earlier run / restart          |
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
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      datetime tt = (datetime)PositionGetInteger(POSITION_TIME);
      if(tmin == 0 || tt < tmin)
        {
         tmin = tt;
         dir  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         sl   = PositionGetDouble(POSITION_SL);
         tp   = PositionGetDouble(POSITION_TP);
         e1   = PositionGetDouble(POSITION_PRICE_OPEN);
         string p[];
         if(StringSplit(PositionGetString(POSITION_COMMENT), '|', p) >= 3)
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
   g_bk.planned    = np;
   g_bk.barsOpen   = (int)((TimeCurrent() - tmin) / 60);
   g_bk.addsExpire = tmin + InpAddWindowBars * 60;
   g_bk.locked     = (dir > 0) ? (sl >= avg && sl > 0.0) : (sl > 0.0 && sl <= avg);
   PrintFormat("GSS: adopted existing basket id=%s dir=%d positions=%d", IntegerToString(g_bk.id), dir, np);
  }
#endif
