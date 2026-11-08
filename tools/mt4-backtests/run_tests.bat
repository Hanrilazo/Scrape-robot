@echo off
setlocal
rem ====================================================================
rem  GoldSweepScalper - run 4 backtests in a row and collect the results
rem  1) Close MetaTrader 4 completely.  2) Edit the two lines below.
rem  3) Double-click this file.  Results: results.txt in this folder.
rem ====================================================================
set "TERMINAL=C:\Program Files (x86)\Axi MetaTrader 4\terminal.exe"
set "DATA=%APPDATA%\MetaQuotes\Terminal\PASTE_YOUR_LONG_CODE_HERE"
rem ====================================================================

if not exist "%TERMINAL%" (
  echo terminal.exe not found at: %TERMINAL%
  echo Edit the TERMINAL line in this file.
  pause
  exit /b 1
)
if not exist "%DATA%\MQL4" (
  echo MT4 data folder not found at: %DATA%
  echo In MT4: File - Open Data Folder, copy the path, and put it in the DATA line.
  pause
  exit /b 1
)
tasklist /FI "IMAGENAME eq terminal.exe" 2>nul | find /I "terminal.exe" >nul
if not errorlevel 1 (
  echo MetaTrader 4 is still running. Close it completely, then run this again.
  pause
  exit /b 1
)

if not exist "%DATA%\tester" mkdir "%DATA%\tester"
if not exist "%DATA%\MQL4\Presets" mkdir "%DATA%\MQL4\Presets"
copy /Y "%~dp0*.set" "%DATA%\tester\" >nul
copy /Y "%~dp0*.set" "%DATA%\MQL4\Presets\" >nul

set "OUT=%~dp0results.txt"
echo GoldSweepScalper automated tests - %date% %time%> "%OUT%"
echo.>> "%OUT%"

call :run C "CHECK: 1 ticket, 12 pips, Mar-Aug 2026, spread 30 (manual run gave 27 baskets, net +3.19)"
call :run A "OUT-OF-SAMPLE: 1 ticket, 12 pips, Mar 2025-Feb 2026, spread 30"
call :run B "OUT-OF-SAMPLE STRESS: same as A but spread 50"
call :run D "OUT-OF-SAMPLE DESIGNED FILTERS: bias on, sessions on, spread 30"

echo.
echo ================ RESULTS ================
type "%OUT%"
echo.
echo Saved to %OUT%
pause
exit /b 0

:run
echo Running test %~1 ...
echo ===== RUN %~1 : %~2 =====>> "%OUT%"
start "" /wait "%TERMINAL%" "%~dp0cfg_%~1.ini"
powershell -NoProfile -Command "Select-String -Path '%DATA%\tester\logs\*.log' -Pattern 'GSS: started on' | Select-Object -Last 1 | ForEach-Object { $_.Line }" >> "%OUT%"
powershell -NoProfile -Command "Select-String -Path '%DATA%\tester\logs\*.log' -Pattern 'GSS summary' | Select-Object -Last 1 | ForEach-Object { $_.Line }" >> "%OUT%"
echo.>> "%OUT%"
exit /b 0
