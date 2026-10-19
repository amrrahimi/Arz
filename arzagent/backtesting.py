"""Historical testing using only previously closed bars."""
from __future__ import annotations
from .strategy import analyze, PROFILES

def backtest(candles, profile: str, fee_fraction=0.0015, starting=1000.0):
    """A conservative, illustrative long-only historical test; no forward-looking data.

    Enter next candle OPEN after signal on preceding closed candle.
    Fees+slippage modeled as fee_fraction per side. No funding, spread or network delay.
    """
    if len(candles) < 280:
        raise ValueError("برای بک‌تست حداقل ۲۸۰ کندل نیاز است")
    cash = starting
    qty, entry = 0., 0.
    high_price, stop, take = 0., 0., 0.
    wins, losses, trades = 0, 0, 0
    peak, worst_dd = cash, 0.
    last_entry_cost=0.
    for i in range(220, len(candles)-1):
        signal = analyze(candles[:i+1], profile, in_position=qty>0)
        next_open = float(candles[i+1][1]); next_high = float(candles[i+1][2]); next_low = float(candles[i+1][3])
        if next_open <= 0:
            continue
        if qty > 0:
            high_price = max(high_price, float(candles[i][2]))
            stop = max(stop, high_price - PROFILES[profile]["stop_atr"] * signal.atr)
            forced = next_open <= stop or next_open >= take or next_low <= stop or next_high >= take
            if signal.action == "SELL" or forced:
                # Gap/slippage adverse: use market open for exit, stop when intrabar hit.
                exit_price = min(next_open, stop) if next_low <= stop else (max(next_open, take) if next_high >= take else next_open)
                exit_price = max(0.000000001, exit_price)
                proceeds = qty * exit_price * (1-fee_fraction)
                pnl = proceeds - last_entry_cost
                cash += proceeds
                wins += int(pnl>0); losses += int(pnl<=0)
                trades += 1
                qty=0; entry=stop=take=0.
        elif signal.action == "BUY" and cash > 10:
            # Spend 20% of available test cash per trade to limit exposure.
            allocation = cash * .20
            qty = allocation / (next_open * (1 + fee_fraction))
            cash -= allocation
            last_entry_cost = allocation
            entry=next_open
            high_price=next_open
            stop=entry - PROFILES[profile]["stop_atr"] * signal.atr
            take=entry + PROFILES[profile]["take_atr"] * signal.atr
        equity = cash + qty * next_open
        peak = max(peak, equity)
        worst_dd = max(worst_dd, (peak-equity)/peak*100 if peak else 0)
    last_price=float(candles[-1][4])
    equity=cash+qty*last_price
    return {"return_pct": round((equity/starting-1)*100,2),
            "max_dd_pct":round(worst_dd,2), "round_trips":trades,
            "win_pct":round(wins/max(1,trades)*100,1), "open_position":bool(qty),
            "candles":len(candles), "cost_assumption":fee_fraction}

