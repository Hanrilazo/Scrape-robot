//+------------------------------------------------------------------+
//| Journal.mqh (MT4) - CSV trade journal + screenshots              |
//| Files: <Common>\Files\GoldSweep\live|tester\*.csv                |
//+------------------------------------------------------------------+
#ifndef GSS4_JOURNAL_MQH
#define GSS4_JOURNAL_MQH

bool   g_jOn  = false;
string g_jDir = "GoldSweep\\live\\";
string g_row  = "";
int    g_rowN = 0;

//+------------------------------------------------------------------+
void Rw_Begin()
  {
   g_row  = "";
   g_rowN = 0;
  }
//+------------------------------------------------------------------+
void Rw(const string v)
  {
   if(g_rowN > 0)
      g_row += g_sep;
   g_row += v;
   g_rowN++;
  }
//+------------------------------------------------------------------+
void RwS(string v)
  {
   StringReplace(v, g_sep, "_");
   StringReplace(v, "\n", " ");
   StringReplace(v, "\r", " ");
   Rw(v);
  }
//+------------------------------------------------------------------+
void RwD(const double v, const int digits = 2)
  {
   Rw(DoubleToString(v, digits));
  }
//+------------------------------------------------------------------+
void RwI(const long v)
  {
   Rw(IntegerToString(v));
  }
//+------------------------------------------------------------------+
void RwT(const datetime t)
  {
   if(t > 0)
      Rw(TimeToString(t, TIME_DATE | TIME_SECONDS));
   else
      Rw("");
  }
//+------------------------------------------------------------------+
void Journal_Init()
  {
   g_sep = InpCsvSep;
   if(StringLen(g_sep) == 0)
      g_sep = ",";
   g_jOn = InpJournal && !g_isOptim;
   if(!g_jOn)
      return;
   g_jDir = g_isTester ? "GoldSweep\\tester\\" : "GoldSweep\\live\\";
   FolderCreate("GoldSweep", FILE_COMMON);
   FolderCreate(g_isTester ? "GoldSweep\\tester" : "GoldSweep\\live", FILE_COMMON);
   FolderCreate("GoldSweep");
   FolderCreate("GoldSweep\\screens");
   if(g_isTester)
     {
      FileDelete(g_jDir + "signals.csv", FILE_COMMON);
      FileDelete(g_jDir + "events.csv", FILE_COMMON);
      FileDelete(g_jDir + "baskets.csv", FILE_COMMON);
     }
  }
//+------------------------------------------------------------------+
void Journal_Append(const string file, const string hdr, const string row)
  {
   int h = FileOpen(g_jDir + file, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
     {
      Print("GSS journal: cannot open ", g_jDir + file, " error ", GetLastError());
      return;
     }
   if(FileSize(h) == 0)
      FileWriteString(h, hdr + "\r\n");
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, row + "\r\n");
   FileClose(h);
  }
//+------------------------------------------------------------------+
//| every detected sweep, traded or skipped, with the reason         |
//+------------------------------------------------------------------+
void Journal_Signal(const SweepSignal &s, const string outcome)
  {
   if(!g_jOn)
      return;
   Rw_Begin();
   Rw("time"); Rw("hour"); Rw("dow"); Rw("dir"); Rw("kind"); Rw("level"); Rw("level_age_min");
   Rw("wick"); Rw("depth_atr"); Rw("run_len"); Rw("run_atr"); Rw("rej_pct"); Rw("body_ratio");
   Rw("tv_ratio"); Rw("atr_m1"); Rw("spread"); Rw("bias"); Rw("stop_dist"); Rw("adds_allowed"); Rw("outcome");
   string hdr = g_row;

   Rw_Begin();
   RwT(s.time + 60);
   RwI(U_MinutesOfDay(s.time + 60) / 60);
   RwI(U_Dow(s.time + 60));
   Rw(s.dir > 0 ? "BUY" : "SELL");
   RwS(s.kind);
   RwD(s.level, 2);
   RwD((double)((s.time + 60) - s.formed) / 60.0, 0);
   RwD(s.wick, 2);
   RwD(s.depthAtr, 2);
   RwI(s.runLen);
   RwD(s.runAtr, 2);
   RwD(s.rejPct, 0);
   RwD(s.bodyRatio, 2);
   RwD(s.tvRatio, 2);
   RwD(s.atr, 2);
   RwD(U_Spread(), 2);
   RwI(g_bias);
   RwD(g_lastStopDist, 2);
   RwI(g_lastAdds);
   RwS(outcome);
   Journal_Append("signals.csv", hdr, g_row);
  }
//+------------------------------------------------------------------+
//| basket life-cycle events (entry, adds, lock, close ...)          |
//+------------------------------------------------------------------+
void Journal_Event(const string ev, const double price, const double vol, const double slipPips, const string info)
  {
   if(!g_jOn)
      return;
   Rw_Begin();
   Rw("time"); Rw("basket_id"); Rw("event"); Rw("dir"); Rw("price"); Rw("volume"); Rw("slip_pips"); Rw("info");
   string hdr = g_row;

   Rw_Begin();
   RwT(TimeCurrent());
   RwI(g_bk.id);
   RwS(ev);
   Rw(g_bk.dir > 0 ? "BUY" : "SELL");
   RwD(price, 2);
   RwD(vol, 2);
   RwD(slipPips, 1);
   RwS(info);
   Journal_Append("events.csv", hdr, g_row);
  }
//+------------------------------------------------------------------+
//| screenshots land in <terminal data>\MQL4\Files\GoldSweep\screens |
//+------------------------------------------------------------------+
void Journal_Screenshot(const string tag)
  {
   if(!InpScreenshots || !g_jOn || g_isOptim || g_isTester)
      return;
   string fn = "GoldSweep\\screens\\l_" + IntegerToString(g_bk.id) + "_" + tag + ".png";
   WindowScreenShot(fn, 1280, 720);
  }
//+------------------------------------------------------------------+
void Stats_Add(const double net, const double t1Net, const double addsNet)
  {
   g_st.n++;
   g_st.net     += net;
   g_st.t1Net   += t1Net;
   g_st.addsNet += addsNet;
   if(net > 0.0)
     {
      g_st.wins++;
      g_st.grossWin += net;
     }
   else
     {
      g_st.losses++;
      g_st.grossLoss += net;
     }
  }
//+------------------------------------------------------------------+
void Stats_Print()
  {
   if(g_st.n == 0)
     {
      Print("GSS summary: no baskets closed.");
      return;
     }
   double wr   = 100.0 * g_st.wins / g_st.n;
   double aw   = (g_st.wins   > 0) ? g_st.grossWin  / g_st.wins   : 0.0;
   double al   = (g_st.losses > 0) ? g_st.grossLoss / g_st.losses : 0.0;
   double pf   = (g_st.grossLoss < 0.0) ? g_st.grossWin / MathAbs(g_st.grossLoss) : 0.0;
   double beWr = (aw - al > 0.0) ? 100.0 * MathAbs(al) / (aw + MathAbs(al)) : 0.0;
   PrintFormat("GSS summary: baskets=%d winRate=%.1f%% breakEvenWinRate=%.1f%% avgWin=%.2f avgLoss=%.2f PF=%.2f expectancy=%.2f net=%.2f ticket1Net=%.2f addsNet=%.2f",
               g_st.n, wr, beWr, aw, al, pf, g_st.net / g_st.n, g_st.net, g_st.t1Net, g_st.addsNet);
  }
#endif
