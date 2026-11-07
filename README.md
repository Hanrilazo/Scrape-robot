# Scrape-robot — GoldSweepScalper (MT5)

XAUUSD **M1 liquidity-sweep scalper** with a **scale-in basket** of 0.01-lot tickets.
Written in MQL5 for **hedging accounts only**. It has not been compiled or run against a broker
from the environment it was written in — compile it, then backtest and demo-trade it before risking money.

## Strategy in one paragraph

Price pushes into a liquidity level (M15 swing high/low, equal highs/lows, previous-day high/low, Asian range)
with **3+ consecutive push candles**. A candle then **wicks through** the untouched level and **closes back inside**
with a long rejection wick and a small body (the slowdown). The EA enters against the push:
ticket #1 at market, up to 4–5 more as **limit orders** spaced between the entry and the sweep wick
(never beyond it). Every ticket shares the same stop (behind the wick) and the same take-profit:
**all tickets close together when the worst (first) entry is +`InpTargetPips` (default 12 pips = $1.20)**.

## Rules in detail

| Step | Rule (defaults) |
|---|---|
| Levels | M15 fractal swings (24 h), equal highs/lows (within 0.15 × M15 ATR), previous-day H/L, Asian range 01:00–09:00 server. A level must be ≥ 15 min old and **untouched** since it formed — a swept level is never traded twice. |
| Run | ≥ 3 consecutive push candles ending on the bar **before** the breach, net move ≥ 1.0 × ATR(M1). `InpMinRunCandles = 0` disables it (for A/B tests). |
| Sweep | Breach depth between 0.25 and 1.5 × ATR (deeper = breakout, skipped). The sweep bar must close back inside the level. `InpSweepWindowBars = 2` also allows a two-bar sweep. |
| Slowdown | Rejection wick ≥ 40 % of the bar's range **and** body ≤ 0.6 × the average run body. |
| Entry | `Aggressive`: market at the open after the sweep bar. `Confirmed`: wait up to 5 bars for a close beyond the sweep candle's low/high; cancelled if the wick extreme is exceeded. |
| Stop | Wick extreme + 0.3 × ATR + spread, **server-side on every ticket**. Skipped if stop distance > `InpMaxStopToTarget` (3×) the target. |
| Adds | Evenly spaced limit orders between entry and wick, at least `InpMinAddStepPips` (4) apart, expire after 15 bars. |
| Target | Every ticket's TP = first entry ± 12 pips. Later tickets are at better prices, so the basket closes in profit. |
| Lock | When price is ≥ 8 pips beyond the basket break-even, all SLs move to break-even + 2 pips and the remaining pending adds are deleted. |
| Risk budget | Tickets are removed from the plan until the worst case (every ticket filled, stop hit, commission included) ≤ 1.5 % of equity. |
| Exits | Time stop 45 bars, flatten before high-impact news and on Friday, daily-loss lock, equity kill switch. |

**1 pip = $0.10** on gold (`InpPipSizeUSD`). All sizes are price distances, so they do not depend on your broker's digits.

## Install

1. In MT5: *File → Open Data Folder*, then copy this repo's `MQL5` folder contents into that `MQL5` folder
   (`Experts`, `Include`, `Scripts` keep their sub-folders).
2. Open `MQL5/Experts/GoldSweepScalper/GoldSweepScalper.mq5` in MetaEditor and press **F7**.
   Expect 0 errors. If the compiler reports anything, paste the messages back and they will be fixed.
3. Use a **hedging** account (the EA refuses to start on netting accounts) and the exact gold symbol of your broker.
4. Attach to an **XAUUSD M1** chart, enable Algo Trading.

### Server time

All session inputs are **broker server time**. Defaults (London 10:00–13:00, New York 15:30–19:00, rollover block
23:30–01:30) assume the common GMT+2 / GMT+3 "New-York-close" server. If your broker differs, shift every
time input (`InpSessions`, `InpRolloverBlock`, `InpFridayNoNewAfter`, `InpFridayFlatten`, Asian hours).

## News filter and backtests

The Strategy Tester has no economic calendar. Run the script
`Scripts/GoldSweepScalper/ExportNewsCalendar` once on a live/demo chart (set the date range to cover your backtest);
it writes `Common\Files\GoldSweep\news.csv`, which the EA reads in the tester. Live, the EA reads the
MQL5 calendar directly. The calendar timestamps are assumed to be in broker server time — verify one event
(e.g. NFP) against your platform before trusting the filter.

## Journal (the point of the first version)

Files are written to `Terminal\Common\Files\GoldSweep\live\` (live) or `...\tester\` (backtests, recreated each run):

* `signals.csv` — **every** detected sweep, traded or skipped, with the reason (`SESSION`, `SPREAD`, `NEWS`, `BIAS`,
  `STOP_TOO_WIDE`, `RISK_TOO_BIG`, ...) and its features: level type, depth/ATR, run length, wick %, body ratio,
  tick-volume ratio, ATR, spread, bias. Use it to see which rules actually carry the edge.
* `events.csv` — basket life-cycle: `ENTRY`, `ADD_PLACED`, `ADD_FILLED` (with slippage), `LOCK`, `ADDS_EXPIRED`,
  `CLOSE_REQUEST`, `BASKET_CLOSED`, guard events.
* `baskets.csv` — one row per basket: entries filled, average entry, exit, duration, MFE/MAE, gross, commission, swap,
  net, close reason, plus **`ticket1_net` and `adds_net`** — the net result of the first ticket alone versus all
  the scale-in tickets. After 100+ baskets this tells you whether scaling in earns or costs money.
* Chart screenshots (live and visual tester) go to `Terminal\<id>\MQL5\Files\GoldSweep\screens\`
  (MT5 cannot write screenshots to the common folder).

`InpCsvSep` can be set to `;` for Excel locales that use a decimal comma.

## Read this before you run it live

* **The maths is against you unless the win rate is high.** Break-even win rate (before costs) is
  `stop / (stop + target)`. With the first-entry stop at 1.2 x the target that is about 55 %; at the
  `InpMaxStopToTarget = 3` limit it is 75 %. Costs push it higher, and a scale-in basket that is stopped out loses
  on every filled ticket, so the real figure is higher still. The EA prints `breakEvenWinRate` next to the
  real win rate when it stops; if the real one is not clearly above it, the strategy has no edge on your data.
* **Scale-in means every losing basket is full size**, because price passes every add level on its way to the stop,
  while winners may only have filled one or two tickets. That is why `adds_net` is journaled separately and why
  the risk budget caps the worst case. Compare `InpMaxTickets = 1` against `5` on out-of-sample data.
* The number of tickets is limited by geometry: tickets must be ≥ 4 pips apart and stay inside the sweep.
  A small sweep gives 1–2 tickets; lower `InpMinAddStepPips` to allow more (and accept more risk per basket).
* Gold spread plus commission on M1 can be $0.20–0.40 per round trip. A $1.20 target is mostly cost-sensitive —
  set `InpCommissionPerLotRT` to your broker's real figure.
* Backtest with **"Every tick based on real ticks"** and your broker's data, 12 months, with realistic spread.
  Then run on demo for 4+ weeks (100+ baskets) and compare live spread/slippage in `events.csv` with the tester.
  Only go live if live expectancy is at least half of the tester's.
* Optimise at most 4 inputs (sweep depth, SL buffer, target, max stop-to-target), keep a forward period, and
  trust `OnTester`'s score only with 100+ baskets.
* Restarts: stops and targets live on the broker's server. Daily loss, kill switch and counters are stored in
  terminal global variables, so a restart does not reset them. Set `InpResetKillSwitch = true` for one start to clear
  the kill switch, then set it back to `false`.

This is trading software, not financial advice. Past results do not predict future results.

## Repository layout

```
MQL5/Experts/GoldSweepScalper/GoldSweepScalper.mq5   inputs + event handlers
MQL5/Include/GoldSweepScalper/                       Utils, State, Journal, News, Levels, Filters,
                                                     Risk, Panel, Basket, Signal
MQL5/Scripts/GoldSweepScalper/ExportNewsCalendar.mq5 calendar -> news.csv for the tester
```
