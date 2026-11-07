//+------------------------------------------------------------------+
//| ExportNewsCalendar.mq5                                           |
//| Writes high-impact USD calendar events to                        |
//| <Common>\Files\GoldSweep\news.csv so GoldSweepScalper can use    |
//| them in the Strategy Tester (the tester has no calendar).        |
//| Run it on a live/demo chart once, then again before each new     |
//| backtest period. Times are in the broker server time zone.       |
//+------------------------------------------------------------------+
#property copyright "scrape-robot"
#property version   "1.00"
#property script_show_inputs

input datetime InpFrom            = D'2024.01.01 00:00';
input datetime InpTo              = D'2026.12.31 00:00';
input string   InpCurrency        = "USD";
input bool     InpIncludeModerate = false;

//+------------------------------------------------------------------+
void OnStart()
  {
   FolderCreate("GoldSweep", FILE_COMMON);
   int h = FileOpen("GoldSweep\\news.csv", FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
     {
      Print("Cannot open news.csv, error ", GetLastError());
      return;
     }
   FileWriteString(h, "time,currency,importance,event\r\n");

   int written = 0;
   datetime cur = InpFrom;
   while(cur < InpTo)
     {
      datetime nxt = cur + 30 * 86400;
      if(nxt > InpTo)
         nxt = InpTo;
      MqlCalendarValue vals[];
      int n = 0;
      if(CalendarValueHistory(vals, cur, nxt, NULL, InpCurrency))
         n = ArraySize(vals);
      if(n > 0)
        {
         for(int i = 0; i < n; i++)
           {
            MqlCalendarEvent ev;
            if(!CalendarEventById(vals[i].event_id, ev))
               continue;
            string imp = "";
            if(ev.importance == CALENDAR_IMPORTANCE_HIGH)
               imp = "HIGH";
            else
               if(InpIncludeModerate && ev.importance == CALENDAR_IMPORTANCE_MODERATE)
                  imp = "MODERATE";
            if(imp == "")
               continue;
            string name = ev.name;
            StringReplace(name, ",", " ");
            FileWriteString(h, TimeToString(vals[i].time, TIME_DATE | TIME_MINUTES) + "," + InpCurrency + "," + imp + "," + name + "\r\n");
            written++;
           }
        }
      cur = nxt;
     }
   FileClose(h);
   PrintFormat("ExportNewsCalendar: %d events written to Common\\Files\\GoldSweep\\news.csv", written);
  }
