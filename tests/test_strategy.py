import numpy as np
import pytest
from arzagent.strategy import ema, rsi, atr, analyze, closed_candles, PROFILES
from arzagent.backtesting import backtest


def candles(n=330, trend=0.0013):
    rng=np.random.default_rng(22)
    last=100.
    out=[]
    for i in range(n):
        close=max(.01,last*(1+trend+rng.normal(0,.004)))
        high=max(close,last)*1.002
        low=min(close,last)*.998
        out.append([i*300_000,last,high,low,close,1000+(i%7)*30])
        last=close
    return out


def test_ema_momentum():
    x=np.arange(40,dtype=float)
    assert np.isnan(ema(x,20)[0])
    assert ema(x,10)[-1]>ema(x,20)[-1]


def test_rsi_constant_price():
    vals=np.full(40,10.)
    assert rsi(vals)[-1]==50.


def test_signals_are_bounded_and_use_closed_candle():
    x=candles()
    for key in PROFILES:
        s=analyze(x,key)
        assert s.action in ("BUY","SELL","HOLD")
        assert 0<=s.score<=100
        assert s.price>0
        assert s.timestamp==x[-1][0]
        assert s.atr>0


def test_partial_candle_excluded():
    x=candles(2)
    a=closed_candles(x,"5m",300_000+20_000)
    assert len(a)==1


def test_minimum_candles():
    with pytest.raises(ValueError):
        analyze(candles(50),"long")


def test_backtest_no_future_and_bounded():
    x=candles(300)
    r=backtest(x,"swing")
    assert -100<=r["return_pct"]<1e5
    assert r["round_trips"]>=0
    assert 0<=r["win_pct"]<=100
