"""Exchange polling, strategy decision, paper/live spot trade routing.

Live order placement is deliberately behind explicit opt-in and journaled intents.
Unknown network outcomes freeze live trading rather than retrying.
"""
from __future__ import annotations
from dataclasses import asdict
import time, threading, traceback
from PySide6.QtCore import QThread, Signal as QtSignal
from . import storage
from .strategy import analyze, PROFILES, closed_candles, timeframe_ms, Signal
from .backtesting import backtest
from .exchanges import (make_exchange, favorites_for, supported_spot_symbols,
                        validate_live, account_name, market_qty)

POLL_SECONDS = 15
ANALYSIS_SECONDS = 50


def _redact_exception(error, auth=None):
    message = str(error)
    for candidate in (auth or {}).values():
        if candidate and isinstance(candidate, str):
            message = message.replace(candidate, "[REDACTED]")
    return message


def _f(x, default=0.0):
    try:
        return float(x) if x is not None else float(default)
    except (ValueError, TypeError):
        return float(default)




class MarketAgent(QThread):
    prices = QtSignal(object)          # {symbol: {price, change, volume}}
    markets_ready = QtSignal(object)   # list[symbol]
    analysis_ready = QtSignal(object)  # asdict(Signal)
    status = QtSignal(str)
    notice = QtSignal(str, str)        # severity, message
    trade = QtSignal(str)
    history_ready = QtSignal(object)   # candles
    backtest_ready = QtSignal(object)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._lock = threading.Lock()
        self._shutdown = threading.Event()
        self._settings = {
            "exchange":"kraken", "symbol":"BTC/USDT", "profile":"swing",
            "mode":"paper", "active":False, "budget":25.0,
            "max_daily_loss":30.0, "max_spread_pct":0.35,
        }
        self._bt_request=False

    def configure(self, **updates):
        with self._lock:
            self._settings.update(updates)

    def snapshot(self):
        with self._lock:
            return self._settings.copy()

    def backtest_request(self):
        with self._lock:
            self._bt_request=True

    def stop(self):
        self._shutdown.set()

    def run(self):
        exchange = None
        exchange_id = None
        symbols = []
        next_tickers = 0
        next_analysis = 0
        last_signal: Signal | None = None
        previous_profile = None
        active_live_verified = False
        last_seen_activation = False
        while not self._shutdown.is_set():
            config = self.snapshot()
            try:
                if exchange is None or config["exchange"] != exchange_id:
                    exchange_id = config["exchange"]
                    exchange = make_exchange(exchange_id)
                    symbols = supported_spot_symbols(exchange)
                    self.markets_ready.emit(symbols)
                    self.status.emit(f"متصل به داده‌های عمومی {exchange_id} | {len(symbols):,} بازار")
                    storage.log(f"Public markets loaded: {exchange_id}; count={len(symbols)}")
                    next_tickers=next_analysis=0
                    last_signal=None
                    active_live_verified=False
                symbol = config["symbol"]
                profile = config["profile"]
                tf=PROFILES[profile]["tf"]
                if symbol not in symbols:
                    candidates=favorites_for(symbols)
                    if candidates:
                        symbol=candidates[0]
                        self.status.emit(f"بازار انتخابی در صرافی موجود نیست؛ {symbol} را انتخاب کنید")
                    else:
                        raise ValueError("هیچ بازار دلاری/یورویی فعال پیدا نشد")
                now=time.monotonic()
                if previous_profile != (symbol,profile):
                    next_analysis=0
                    last_signal=None
                    previous_profile=(symbol,profile)
                if now >= next_tickers:
                    fav=favorites_for(symbols)
                    shortlist=list(dict.fromkeys(([symbol] + fav)[:13]))
                    ticks={}
                    if exchange.has.get("fetchTickers"):
                        try:
                            batch=exchange.fetch_tickers(shortlist)
                            ticks={k:v for k,v in batch.items() if k in shortlist}
                        except Exception:
                            ticks={}
                    if not ticks:
                        # Fallback is bounded to avoid exchange rate limiting.
                        for code in shortlist[:6]:
                            if self._shutdown.is_set(): break
                            try: ticks[code]=exchange.fetch_ticker(code)
                            except Exception: continue
                    cleaned={}
                    for k,v in ticks.items():
                        px = _f(v.get("last"))
                        if px > 0:
                            cleaned[k]={"price":px, "change":_f(v.get("percentage")),
                                        "volume":_f(v.get("quoteVolume")),
                                        "bid":_f(v.get("bid")), "ask":_f(v.get("ask"))}
                    if cleaned:
                        self.prices.emit(cleaned)
                        if config["active"] and symbol in cleaned and last_signal:
                            self._maybe_exit_on_tick(exchange, config, symbol, tf, last_signal, cleaned[symbol])
                    next_tickers=time.monotonic()+POLL_SECONDS
                active_now=bool(config["active"])
                if active_now and config["mode"] == "live" and not active_live_verified:
                    from .storage import credentials_get
                    auth=credentials_get(exchange_id)
                    if not auth:
                        raise ValueError("کلید API برای معاملات واقعی ذخیره نشده است")
                    authenticated=make_exchange(exchange_id, auth)
                    authenticated.load_markets()
                    validate_live(authenticated, symbol)
                    if storage.has_pending(account_name(exchange_id,auth,"live"), "live"):
                        raise RuntimeError("سفارش نامعلوم در دفتر ثبت موجود است؛ معاملات واقعی قفل شدند")
                    active_live_verified=True
                    self.status.emit("اتصال خصوصی تأیید شد | معاملات واقعی فعال هستند")
                    # Use authenticated client for orders, not for bulk public ticker fetching.
                    self._auth_exchange=authenticated
                    self._auth_data=auth
                if not active_now or config["mode"] != "live":
                    active_live_verified=False
                with self._lock:
                    bt=self._bt_request
                    if bt: self._bt_request=False
                if time.monotonic() >= next_analysis or bt:
                    limit = 780 if bt else 310
                    raw=exchange.fetch_ohlcv(symbol, tf, limit=limit)
                    completed=closed_candles(raw, tf, int(time.time()*1000))
                    if len(completed) < 220:
                        raise ValueError(f"داده تاریخی کافی برای {symbol} در بازه {tf} موجود نیست ({len(completed)} کندل)")
                    self.history_ready.emit(completed[-180:])
                    auth=self._auth_data if (active_now and config["mode"]=="live" and active_live_verified) else None
                    account=account_name(exchange_id,auth,config["mode"] if active_now else "paper")
                    pos=storage.get_position(account, config["mode"] if active_now else "paper", symbol)
                    signal=analyze(completed,profile, pos["qty"]>0)
                    last_signal=signal
                    self.analysis_ready.emit(asdict(signal) | {"symbol":symbol,"tf":tf})
                    if bt:
                        result=backtest(completed, profile)
                        self.backtest_ready.emit(result)
                    if active_now and self.snapshot().get("active") and not self._shutdown.is_set():
                        self._execute_signal(exchange,config,symbol,tf,signal,account,auth)
                    next_analysis=time.monotonic()+ANALYSIS_SECONDS
                if active_now != last_seen_activation:
                    storage.log(f"Bot {'START' if active_now else 'STOP'}; {exchange_id}; {symbol}; {profile}; {config['mode']}")
                    last_seen_activation=active_now
            except Exception as err:
                # Do NOT accidentally print raw credentials or exception stack with HTTP headers.
                safe = _redact_exception(err, getattr(self, "_auth_data", None))
                self.notice.emit("error", f"{type(err).__name__}: {safe[:240]}")
                storage.log(f"Agent error ({type(err).__name__}): {safe[:230]}", "ERROR")
                next_tickers=time.monotonic()+15
                next_analysis=time.monotonic()+30
                if config.get("active") and config.get("mode")=="live":
                    self.configure(active=False)  # Fail closed; GUI updated through notice.
                    self.status.emit("معاملات واقعی به علت خطا متوقف شدند")
                    self.notice.emit("halt", "اجرای زنده متوقف شد؛ قبل از فعال‌سازی دوباره وضعیت سفارش‌ها و موجودی را بررسی کنید")
                elif exchange is None:
                    exchange_id=None
            self._shutdown.wait(1)

    def _maybe_exit_on_tick(self, exchange, cfg, symbol, tf, sig, quote):
        if not cfg["active"]:
            return
        auth=self._auth_data if cfg["mode"]=="live" and getattr(self,"_auth_data",None) else None
        account=account_name(cfg["exchange"],auth,cfg["mode"])
        pos=storage.get_position(account,cfg["mode"],symbol)
        if pos["qty"] <= 0:
            return
        px=quote["price"]
        if px<=0: return
        high=max(px,pos["high"])
        storage.update_high(account,cfg["mode"],symbol,high)
        mult=PROFILES[cfg["profile"]]
        stop=max(pos["entry"] - mult["stop_atr"] * sig.atr,
                 high - mult["stop_atr"] * sig.atr)
        take=pos["entry"] + mult["take_atr"] * sig.atr
        if px <= stop or px >= take:
            reason="حد ضرر/تریلینگ" if px <= stop else "حد سود"
            # Use the most recently closed candle ID, with a separate trailing risk slot;
            # idempotent and never create repeat orders on fast quote poll.
            self._place(exchange,cfg,symbol,tf,sig.timestamp, "sell",px,account,auth,reason, risk_exit=True)

    def _execute_signal(self, exchange, cfg, symbol, tf, sig, account, auth):
        pos=storage.get_position(account,cfg["mode"],symbol)
        if sig.action == "BUY" and pos["qty"]<=0:
            self._place(exchange,cfg,symbol,tf,sig.timestamp,"buy",sig.price,account,auth,sig.reason)
        elif sig.action == "SELL" and pos["qty"]>0:
            self._place(exchange,cfg,symbol,tf,sig.timestamp,"sell",sig.price,account,auth,sig.reason)

    def _place(self, pub_exchange, cfg, symbol, tf, candle_ts, side, price, account, auth, reason, risk_exit=False):
        if not cfg["active"] or not self.snapshot().get("active") or self._shutdown.is_set():
            return
        mode=cfg["mode"]
        pos=storage.get_position(account,mode,symbol)
        if side=="buy":
            if pos["qty"]>0: return
            if storage.realized_today(account,mode,symbol) <= -float(cfg["max_daily_loss"]):
                self.notice.emit("warn", "سقف زیان تحقق‌یافته ۲۴ساعته رسیده؛ خرید متوقف است")
                return
        else:
            if pos["qty"]<=0: return
        quote_budget = float(cfg["budget"])
        # Unlike buy, sell the bot-tracked inventory up to budget; in general
        # sell complete tracked inventory to avoid tiny dust leftovers.
        if side=="sell":
            quote_budget=max(quote_budget, pos["qty"]*price*1.01)
        if mode == "paper":
            if side=="buy" and storage.paper_cash(account,symbol=symbol) < quote_budget:
                self.notice.emit("warn", "موجودی آزمایشی کافی نیست")
                return
            qty=quote_budget / price * (0.998 if side=="buy" else 1.)
            if side=="sell": qty=pos["qty"]
            # Make price a little worse than quote in paper execution.
            fill_price=price*(1.0007 if side=="buy" else 0.9993)
            fee=qty*fill_price*0.001
            intent=storage.begin_intent(account,cfg["exchange"],mode,symbol,tf,candle_ts,side.upper())
            if intent is None: return
            pnl=storage.record_fill(account,mode,symbol,side,qty,fill_price,fee,intent,"PAPER")
            msg=f"آزمایشی: {side.upper()} {qty:.7g} {symbol} @ {fill_price:,.7g} | P&L {pnl:+.2f}"
            storage.log(msg)
            self.trade.emit(msg)
            return
        if not auth:
            raise ValueError("Live authentication missing")
        live=self._auth_exchange
        if side=="buy":
            # Require a fresh public bid/ask to constrain excessive spreads.
            ticker=pub_exchange.fetch_ticker(symbol)
            bid,ask=_f(ticker.get("bid")),_f(ticker.get("ask"))
            if bid<=0 or ask<=0 or ask<bid:
                self.notice.emit("warn", "قیمت bid/ask معتبر نیست؛ سفارش انجام نشد")
                return
            spread=(ask-bid)/ask*100
            if spread>float(cfg["max_spread_pct"]):
                self.notice.emit("warn", f"اسپرد {spread:.2f}% بیش از سقف است؛ خرید لغو شد")
                return
        # Do not use the previous candle close as execution sizing price.
        # Always refresh the current ticker before sending a market order.
        if side == "buy":
            price = ask
        else:
            latest=pub_exchange.fetch_ticker(symbol)
            price=_f(latest.get("bid")) or _f(latest.get("last"))
            if price <= 0:
                raise ValueError("No current sell-side market quote")
        balance=live.fetch_balance()
        market=live.market(symbol)
        base,quote=market["base"],market["quote"]
        if side=="buy":
            available=_f((balance.get("free") or {}).get(quote))
            if available < float(cfg["budget"]) * 1.01:
                self.notice.emit("warn", f"موجودی آزاد {quote} کافی نیست؛ سفارش ارسال نشد")
                return
            qty=market_qty(live,symbol,quote_budget,price,side)
        else:
            free_base=_f((balance.get("free") or {}).get(base))
            if free_base<=0:
                self.notice.emit("warn", "موجودی قابل فروش در صرافی صفر است")
                return
            # Never sell more than bot-acquired assets, and round down to precision.
            available = min(pos["qty"], free_base if free_base >= pos["qty"] else free_base*0.999)
            qty=market_qty(live,symbol,quote_budget,price,side,available)
        # If STOP was pressed during authentication / ticker / balance calls,
        # skip sending the order. The lock and journal minimize replay risk.
        snap=self.snapshot()
        if self._shutdown.is_set() or not snap.get("active") or snap.get("mode") != "live" or snap.get("symbol") != symbol or snap.get("exchange") != cfg["exchange"]:
            return
        intent=storage.begin_intent(account,cfg["exchange"],mode,symbol,tf,candle_ts,side.upper())
        if intent is None: return
        self.notice.emit("info", f"در حال ارسال سفارش واقعی {side.upper()} {symbol}")
        # Market orders only; some exchanges require price to calculate buy COST.
        # Never auto-retry after network timeouts (order may have reached exchange).
        try:
            if self._shutdown.is_set() or not self.snapshot().get("active"):
                storage.mark_intent(intent,"cancelled","Stopped before order submission")
                return
            if side=="buy" and live.has.get("createMarketBuyOrderWithCost"):
                # Limit total quote spend using CCXT's unified cost method.
                order=live.create_market_buy_order_with_cost(symbol, float(cfg["budget"])*0.99)
            else:
                order=live.create_order(symbol,"market",side,qty,price if side=="buy" else None)
            oid=str(order.get("id") or "")
            if (order.get("status") != "closed" or not _f(order.get("filled"))) and oid and live.has.get("fetchOrder"):
                time.sleep(1.5)
                order=live.fetch_order(oid,symbol)
            filled=_f(order.get("filled"))
            remaining=_f(order.get("remaining"))
            if not filled or remaining>max(1e-12,filled*1e-5) or order.get("status") not in ("closed", "filled"):
                storage.mark_intent(intent,"uncertain",f"Order ID: {oid} | state: {order.get('status')} | filled: {filled}")
                raise RuntimeError("سفارش ارسال شد، اما تکمیل آن قطعی نیست؛ معاملات قفل شدند")
            actual_price=_f(order.get("average")) or (_f(order.get("cost"))/filled if _f(order.get("cost")) else price)
            fees=order.get("fees") or ([order["fee"]] if order.get("fee") else [])
            fee_quote=0.
            net_filled=filled
            for fee in fees:
                if not isinstance(fee,dict): continue
                cost=_f(fee.get("cost"))
                if fee.get("currency")==quote: fee_quote+=cost
                elif fee.get("currency")==base:
                    if side=="buy": net_filled=max(0.,net_filled-cost)
                    else: fee_quote+=cost*actual_price
            pnl=storage.record_fill(account,mode,symbol,side,net_filled if side=="buy" else filled,actual_price,fee_quote,intent,oid)
            msg=f"واقعی: {side.upper()} {filled:.7g} {symbol} @ {actual_price:.7g} | P&L {pnl:+.2f} | {oid}"
            storage.log(msg)
            self.trade.emit(msg)
        except Exception as error:
            storage.mark_intent(intent,"uncertain",f"Check exchange order history. {type(error).__name__}: {str(error)[:100]}")
            raise RuntimeError("سرنوشت سفارش قطعی نیست؛ معاملات واقعی قفل شده‌اند. تاریخچه سفارش‌های صرافی را بررسی کنید") from error
