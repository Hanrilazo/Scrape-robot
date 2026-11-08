GoldSweepScalper - automated MT4 backtests
==========================================

What it does: runs four backtests one after another with fixed settings and writes the
"GSS started" and "GSS summary" lines of each run to results.txt.

Runs
  C  check run: same settings/dates as the manual 1-ticket run (expect 27 baskets, net +3.19)
  A  1 ticket, 12 pips, 2025.03.01-2026.02.28, spread 30 (unseen months)
  B  same as A with spread 50 (stress)
  D  as A but with the original filters (M15 bias on, sessions 10:00-13:00 and 15:30-19:00)

Steps
  1. Download the repo ZIP, unzip, open tools\mt4-backtests.
  2. Close MetaTrader 4 completely.
  3. Open run_tests.bat in Notepad, set TERMINAL (path to terminal.exe) and DATA
     (MT4: File - Open Data Folder, copy the path).
  4. Double-click run_tests.bat. Each run takes about a minute; do not use MT4 meanwhile.
  5. Send results.txt content.

Notes
  * The tester deposit is not part of the config: it is the value saved in the EA's
    tester properties (set it to 100 once manually: Expert properties - Testing tab).
  * If run C does not reproduce 27 baskets / +3.19, the automation is not reading the
    settings correctly - tell me before trusting runs A, B, D.
  * If a run starts later than its From date, MT4 has no M1 history for that period.
