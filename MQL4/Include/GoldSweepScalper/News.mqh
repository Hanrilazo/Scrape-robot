//+------------------------------------------------------------------+
//| News.mqh (MT4) - high impact news blackout from a CSV file       |
//| MT4 has no calendar API. The file is produced by the MT5 script  |
//| ExportNewsCalendar (MQL5 folder) into the shared Common folder,  |
//| which MT4 and MT5 on the same PC both read.                      |
//| Format: time,currency,importance,event  (broker server time)     |
//+------------------------------------------------------------------+
#ifndef GSS4_NEWS_MQH
#define GSS4_NEWS_MQH

datetime g_news[];
int      g_nNews        = 0;
datetime g_newsLoadedAt = 0;
bool     g_newsWarned   = false;

//+------------------------------------------------------------------+
int News_LowerBound(const datetime x)
  {
   int lo = 0;
   int hi = g_nNews;
   while(lo < hi)
     {
      int mid = (lo + hi) / 2;
      if(g_news[mid] < x)
         lo = mid + 1;
      else
         hi = mid;
     }
   return lo;
  }
//+------------------------------------------------------------------+
bool News_Load()
  {
   g_newsLoadedAt = TimeCurrent();
   int h = FileOpen("GoldSweep\\news.csv", FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(h == INVALID_HANDLE)
     {
      if(!g_newsWarned)
         Print("GSS: GoldSweep\\news.csv not found in the Common\\Files folder - news filter inactive. Run the MT5 script ExportNewsCalendar first.");
      g_newsWarned = true;
      return false;
     }
   ArrayResize(g_news, 0);
   g_nNews = 0;
   while(!FileIsEnding(h))
     {
      string line = FileReadString(h);
      if(StringLen(line) < 10)
         continue;
      string p[];
      if(StringSplit(line, ',', p) < 1)
         continue;
      datetime t = StringToTime(p[0]);
      if(t <= 0)
         continue;
      ArrayResize(g_news, g_nNews + 1, 4096);
      g_news[g_nNews] = t;
      g_nNews++;
     }
   FileClose(h);
   if(g_nNews > 1)
      ArraySort(g_news);
   if(!g_isOptim)
      PrintFormat("GSS: %d news events loaded", g_nNews);
   return g_nNews > 0;
  }
//+------------------------------------------------------------------+
void News_Init()
  {
   if(InpUseNewsFilter)
      News_Load();
  }
//+------------------------------------------------------------------+
void News_OnBar()
  {
   if(!InpUseNewsFilter || g_isTester)
      return;
   if(TimeCurrent() - g_newsLoadedAt >= 3600)
      News_Load();
  }
//+------------------------------------------------------------------+
//| inside [event - before, event + after] ?                         |
//+------------------------------------------------------------------+
bool News_Blocked(const datetime t)
  {
   if(!InpUseNewsFilter || g_nNews == 0)
      return false;
   int i = News_LowerBound(t - InpNewsAfterMin * 60);
   if(i < g_nNews && g_news[i] <= t + InpNewsBeforeMin * 60)
      return true;
   return false;
  }
//+------------------------------------------------------------------+
//| is a news event due within the next 'minutes' ?                  |
//+------------------------------------------------------------------+
bool News_Within(const datetime t, const int minutes)
  {
   if(!InpUseNewsFilter || g_nNews == 0 || minutes <= 0)
      return false;
   int i = News_LowerBound(t);
   if(i < g_nNews && g_news[i] <= t + minutes * 60)
      return true;
   return false;
  }
#endif
