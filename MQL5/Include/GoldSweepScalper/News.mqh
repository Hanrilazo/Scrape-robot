//+------------------------------------------------------------------+
//| News.mqh - high impact USD news blackout                         |
//| Live: MQL5 economic calendar. Tester: GoldSweep\news.csv written |
//| by Scripts\GoldSweepScalper\ExportNewsCalendar.mq5               |
//+------------------------------------------------------------------+
#ifndef GSS_NEWS_MQH
#define GSS_NEWS_MQH

datetime g_news[];
int      g_nNews        = 0;
datetime g_newsLoadedAt = 0;
bool     g_newsReady    = false;

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
bool News_LoadFile()
  {
   int h = FileOpen("GoldSweep\\news.csv", FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(h == INVALID_HANDLE)
     {
      Print("GSS: news.csv not found in Common\\Files\\GoldSweep - news filter inactive in this test. Run the ExportNewsCalendar script first.");
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
   PrintFormat("GSS: %d news events loaded from news.csv", g_nNews);
   return g_nNews > 0;
  }
//+------------------------------------------------------------------+
bool News_RefreshLive()
  {
   MqlCalendarValue vals[];
   datetime from = TimeCurrent() - 4 * 3600;
   datetime to   = TimeCurrent() + 7 * 86400;
   if(!CalendarValueHistory(vals, from, to, NULL, "USD"))
     {
      Print("GSS: calendar read failed or empty, error ", GetLastError());
      return false;
     }
   int n = ArraySize(vals);
   ArrayResize(g_news, 0);
   g_nNews = 0;
   for(int i = 0; i < n; i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev))
         continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;
      ArrayResize(g_news, g_nNews + 1, 256);
      g_news[g_nNews] = vals[i].time;
      g_nNews++;
     }
   if(g_nNews > 1)
      ArraySort(g_news);
   g_newsLoadedAt = TimeCurrent();
   return true;
  }
//+------------------------------------------------------------------+
void News_Init()
  {
   g_newsReady = false;
   if(!InpUseNewsFilter)
      return;
   if(g_isTester)
      g_newsReady = News_LoadFile();
   else
      g_newsReady = News_RefreshLive();
  }
//+------------------------------------------------------------------+
void News_OnBar()
  {
   if(!InpUseNewsFilter || g_isTester)
      return;
   if(TimeCurrent() - g_newsLoadedAt >= 1800)
      g_newsReady = News_RefreshLive();
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
