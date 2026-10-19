"""CCXT spot markets with secure credential lookup and explicit capability checks."""
from __future__ import annotations
import hashlib
from dataclasses import dataclass

EXCHANGES = {"kraken":"Kraken", "coinbase":"Coinbase", "binance":"Binance", "okx":"OKX", "bybit":"Bybit", "bitget":"Bitget"}
FAVORITES = ["BTC", "ETH", "SOL", "XRP", "BNB", "DOGE", "ADA", "AVAX", "LINK", "DOT", "LTC", "TRX"]


def make_exchange(exchange_id: str, auth: dict | None = None):
    import ccxt
    if exchange_id not in EXCHANGES:
        raise ValueError("Unsupported exchange")
    kwargs = {"enableRateLimit": True, "timeout": 12000, "options": {"defaultType":"spot"}}
    if auth:
        kwargs.update({"apiKey":auth["key"], "secret":auth["secret"]})
        if auth.get("password"):
            kwargs["password"] = auth["password"]
    exchange = getattr(ccxt, exchange_id)(kwargs)
    return exchange


def account_name(exchange_id: str, auth: dict | None, mode: str) -> str:
    if mode == "paper":
        return f"paper:{exchange_id}"
    if not auth or not auth.get("key"):
        raise ValueError("Missing authenticated account")
    # Only a one-way fingerprint, NEVER the raw API key.
    return f"live:{exchange_id}:{hashlib.sha256(auth['key'].encode()).hexdigest()[:20]}"


def supported_spot_symbols(exchange) -> list[str]:
    exchange.load_markets()
    return sorted([
        name for name, market in exchange.markets.items()
        if market.get("spot", False) and market.get("active") is not False
        and "/" in name and ":" not in name
        and market.get("quote") in ("USDT","USD","EUR","USDC")
    ])


def favorites_for(symbols: list[str]) -> list[str]:
    available = set(symbols)
    result=[]
    for base in FAVORITES:
        for quote in ("USDT","USD","EUR","USDC"):
            symbol=f"{base}/{quote}"
            if symbol in available:
                result.append(symbol)
                break
    return result


def validate_live(exchange, symbol: str) -> dict:
    """Private endpoint validation; order permission cannot be verified without placing an order."""
    market = exchange.market(symbol)
    if not market.get("spot") or market.get("active") is False:
        raise ValueError("Only active spot markets are supported")
    if not exchange.has.get("createMarketOrder"):
        raise ValueError("Exchange does not expose unified spot market order support")
    if not exchange.has.get("fetchBalance"):
        raise ValueError("Exchange does not expose balance retrieval")
    return exchange.fetch_balance()


def market_qty(exchange, symbol: str, quote_budget: float, price: float, side: str, available_base: float | None = None) -> float:
    market = exchange.market(symbol)
    if price <= 0 or quote_budget <= 0:
        raise ValueError("Invalid order parameters")
    # Buy sizes carry 1% price buffer to reduce overspending on market slippage.
    raw = quote_budget / price * (0.99 if side == "buy" else 1.0)
    if side == "sell" and available_base is not None:
        raw = min(raw, available_base)
    qty = float(exchange.amount_to_precision(symbol, raw))
    if qty <= 0:
        raise ValueError("Order below exchange amount precision")
    mn_amount = ((market.get("limits") or {}).get("amount") or {}).get("min")
    mn_cost = ((market.get("limits") or {}).get("cost") or {}).get("min")
    if mn_amount is not None and qty < float(mn_amount):
        raise ValueError(f"Minimum base amount: {mn_amount}")
    if mn_cost is not None and qty * price < float(mn_cost):
        raise ValueError(f"Minimum order cost: {mn_cost}")
    return qty
