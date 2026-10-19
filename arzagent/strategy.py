"""Deterministic multi-indicator strategy agent (closed candles only).

This is NOT a pretrained language model, nor a TradingView API feed. It uses
locally computed public indicators and regime-adaptive scoring.
"""
from __future__ import annotations
from dataclasses import dataclass
from typing import Sequence
import math
import numpy as np

PROFILES = {
    "long": {"label": "بلندمدت", "tf": "1d", "stop_atr": 3.2, "take_atr": 6.4, "min_score": 72},
    "swing": {"label": "کوتاه‌مدت", "tf": "1h", "stop_atr": 2.4, "take_atr": 4.4, "min_score": 69},
    "scalp": {"label": "نوسان‌گیری", "tf": "5m", "stop_atr": 1.7, "take_atr": 2.9, "min_score": 75},
}

@dataclass(frozen=True)
class Signal:
    action: str           # BUY / SELL / HOLD
    score: int            # technical confluence (NOT win probability)
    price: float
    atr: float
    atr_percent: float
    rsi: float
    adx: float
    reason: str
    timestamp: int
    regime: str


def ema(x: np.ndarray, period: int) -> np.ndarray:
    arr = np.asarray(x, dtype=float)
    out = np.empty(len(arr))
    out.fill(np.nan)
    if len(arr) < period:
        return out
    out[period-1] = arr[:period].mean()
    alpha = 2 / (period + 1)
    for i in range(period, len(arr)):
        out[i] = alpha * arr[i] + (1 - alpha) * out[i-1]
    return out


def rsi(x: np.ndarray, period: int = 14) -> np.ndarray:
    arr = np.asarray(x, dtype=float)
    out = np.full(len(arr), np.nan)
    if len(arr) <= period:
        return out
    diff = np.diff(arr)
    gains = np.maximum(diff, 0)
    losses = np.maximum(-diff, 0)
    ag, al = gains[:period].mean(), losses[:period].mean()
    def score(g, l):
        if l == 0:
            return 100.0 if g > 0 else 50.0
        return 100 - 100 / (1 + g / l)
    out[period] = score(ag, al)
    for i in range(period + 1, len(arr)):
        ag = (ag * (period - 1) + gains[i - 1]) / period
        al = (al * (period - 1) + losses[i - 1]) / period
        out[i] = score(ag, al)
    return out


def atr(high: np.ndarray, low: np.ndarray, close: np.ndarray, period=14) -> np.ndarray:
    tr = np.empty(len(close), dtype=float)
    tr[0] = high[0] - low[0]
    tr[1:] = np.maximum.reduce([high[1:] - low[1:], abs(high[1:] - close[:-1]), abs(low[1:] - close[:-1])])
    result = np.full(len(close), np.nan)
    if len(close) < period:
        return result
    result[period - 1] = tr[:period].mean()
    for i in range(period, len(close)):
        result[i] = (result[i-1] * (period-1) + tr[i]) / period
    return result


def adx(high: np.ndarray, low: np.ndarray, close: np.ndarray, period=14) -> np.ndarray:
    n = len(close)
    ret = np.full(n, np.nan)
    if n < period * 3:
        return ret
    move_up = high[1:] - high[:-1]
    move_down = low[:-1] - low[1:]
    plus = np.where((move_up > move_down) & (move_up > 0), move_up, 0.)
    minus = np.where((move_down > move_up) & (move_down > 0), move_down, 0.)
    tr = np.maximum.reduce([high[1:] - low[1:], abs(high[1:] - close[:-1]), abs(low[1:] - close[:-1])])
    smooth_t, smooth_p, smooth_m = tr[:period].sum(), plus[:period].sum(), minus[:period].sum()
    dx = []
    for i in range(period, len(tr)):
        smooth_t = smooth_t - smooth_t / period + tr[i]
        smooth_p = smooth_p - smooth_p / period + plus[i]
        smooth_m = smooth_m - smooth_m / period + minus[i]
        pdi = 100 * smooth_p / smooth_t if smooth_t else 0
        mdi = 100 * smooth_m / smooth_t if smooth_t else 0
        dx.append(100 * abs(pdi-mdi) / (pdi+mdi) if pdi+mdi else 0)
    if len(dx) >= period:
        ret[period * 2] = float(np.mean(dx[:period]))
        for i in range(period * 2 + 1, n):
            index = i - period - 1
            if index < len(dx):
                ret[i] = (ret[i-1] * (period-1) + dx[index]) / period
    return ret


def analyze(candles: Sequence[Sequence[float]], profile: str, in_position: bool = False) -> Signal:
    if profile not in PROFILES:
        raise ValueError("Unknown profile")
    arr = np.asarray(candles, dtype=float)
    if arr.ndim != 2 or arr.shape[1] < 6 or len(arr) < 220:
        raise ValueError("At least 220 completed OHLCV candles are required")
    if not np.all(np.isfinite(arr[:, 1:6])) or np.any(arr[:, 4] <= 0):
        raise ValueError("Invalid candle data")
    high, low, close, vol = arr[:,2], arr[:,3], arr[:,4], arr[:,5]
    e9, e20, e21, e50, e200 = [ema(close, p) for p in (9,20,21,50,200)]
    rs = rsi(close)
    at = atr(high, low, close)
    ax = adx(high, low, close)
    macd = ema(close, 12) - ema(close, 26)
    # EMA of valid MACD samples, avoiding NaN initialization
    valid = np.nan_to_num(macd[25:], nan=0.0)
    sig_line = ema(valid, 9)
    hist = float(macd[-1] - sig_line[-1]) if np.isfinite(sig_line[-1]) else 0.0
    vma = float(np.mean(vol[-21:-1]))
    vr = float(vol[-1] / vma) if vma > 0 else 0.0
    p = float(close[-1])
    ap = float(at[-1] / p * 100)
    rv, av = float(rs[-1]), float(ax[-1])
    trend = e50[-1] > e200[-1]
    momentum = hist > 0
    regime = "رونددار" if av >= 22 else "خنثی / کم‌روند"
    if ap >= 7:
        regime = "پرنوسان"
    if profile == "long":
        checks = [(trend, 35), (p > e50[-1], 20), (momentum, 15), (49 < rv < 75, 15), (av > 18, 15)]
        exit_now = (p < e50[-1] and hist < 0) or rv < 38
        rtext = "EMA50/200، MACD، RSI، ADX"
    elif profile == "swing":
        checks = [(e20[-1] > e50[-1], 30), (p > e20[-1], 20), (momentum, 20), (44 < rv < 70, 15), (av >= 17, 15)]
        exit_now = (p < e20[-1] and hist < 0) or rv > 78
        rtext = "EMA20/50، MACD، RSI، ADX"
    else:
        # Volume and relative momentum: 5m signals, NOT high-frequency execution.
        checks = [(e9[-1] > e21[-1], 30), (p > e9[-1], 15), (momentum, 20), (48 < rv < 72, 15), (vr > 1.05, 10), (av > 20, 10)]
        exit_now = (p < e21[-1]) or (rv < 42)
        rtext = "EMA9/21، حجم، MACD، RSI، ADX"
    score = int(round(sum(w for ok, w in checks if bool(ok))))
    # Volatility / missing-liquidity filters; this confidence is NOT calibrated odds.
    unhealthy = not math.isfinite(ap) or ap < 0.03 or ap > (6 if profile == "scalp" else 13) or (profile == "scalp" and vr < .3)
    if unhealthy:
        score = min(score, 45)
    if in_position and exit_now:
        action, reason = "SELL", f"سیگنال خروج اندیکاتورها: {rtext}"
    elif not in_position and not unhealthy and score >= PROFILES[profile]["min_score"]:
        action, reason = "BUY", f"هم‌جهتی اندیکاتورها: {rtext}"
    else:
        action, reason = "HOLD", f"شرایط ورود/خروج کامل نیست؛ {rtext}"
    if unhealthy:
        reason += " | فیلتر نوسان/حجم فعال است"
    return Signal(action, score, p, float(at[-1]), ap, rv, av, reason, int(arr[-1,0]), regime)


def timeframe_ms(timeframe: str) -> int:
    return {"5m":300_000, "1h":3_600_000, "1d":86_400_000}[timeframe]


def closed_candles(candles: Sequence[Sequence[float]], timeframe: str, now_ms: int) -> list:
    """Disallow analysis of unfinished candle; excludes exchange's most recent unclosed OHLCV row."""
    msec = timeframe_ms(timeframe)
    return [list(c) for c in candles if int(c[0]) + msec <= now_ms - 1500]
