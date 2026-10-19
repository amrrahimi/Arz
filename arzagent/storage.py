"""SQLite journal and OS-keychain credential storage. Never persist plaintext API keys."""
from __future__ import annotations
import json, sqlite3, time
from pathlib import Path
from platformdirs import user_data_dir

BASE_DIR = Path(user_data_dir("ArzAgent", "ArzAgent"))
BASE_DIR.mkdir(parents=True, exist_ok=True)
DB_PATH = BASE_DIR / "agent.sqlite3"
SETTINGS = BASE_DIR / "settings.json"

DEFAULT_SETTINGS = {
    "exchange": "kraken", "profile": "swing", "symbol": "BTC/USDT",
    "quote_per_trade": 25.0, "max_daily_loss": 30.0,
    "max_spread_pct": 0.35,
    "paper_cash": 10000.0,
}


def read_settings() -> dict:
    data = DEFAULT_SETTINGS.copy()
    if SETTINGS.exists():
        try:
            raw = json.loads(SETTINGS.read_text(encoding="utf8"))
            # Strictly whitelisted non-secret settings.
            data.update({k:v for k,v in raw.items() if k in DEFAULT_SETTINGS})
        except (ValueError, OSError):
            pass
    return data


def save_settings(values: dict) -> None:
    safe = {k: v for k, v in values.items() if k in DEFAULT_SETTINGS}
    path = SETTINGS.with_suffix(".tmp")
    path.write_text(json.dumps(safe, ensure_ascii=False, indent=2), encoding="utf8")
    path.replace(SETTINGS)


def credentials_set(exchange_id: str, api_key: str, secret: str, password: str = "") -> None:
    import keyring
    if not api_key.strip() or not secret.strip():
        raise ValueError("API key and secret required")
    obj = json.dumps({"key":api_key.strip(), "secret":secret.strip(), "password":password.strip()})
    keyring.set_password("ArzAgent Desktop", exchange_id, obj)
    # Keyring errors propagate; we never fall back to a plaintext file.


def credentials_get(exchange_id: str) -> dict | None:
    import keyring
    raw = keyring.get_password("ArzAgent Desktop", exchange_id)
    return json.loads(raw) if raw else None


def credentials_delete(exchange_id: str) -> None:
    import keyring
    try:
        keyring.delete_password("ArzAgent Desktop", exchange_id)
    except keyring.errors.PasswordDeleteError:
        pass


def _db():
    db = sqlite3.connect(DB_PATH, timeout=12)
    db.execute("PRAGMA busy_timeout=12000")
    db.execute("PRAGMA journal_mode=WAL")
    return db


def init_db():
    with _db() as db:
        db.executescript("""
        CREATE TABLE IF NOT EXISTS intents (
            id INTEGER PRIMARY KEY,
            created_at REAL NOT NULL,
            account TEXT NOT NULL,
            exchange_id TEXT NOT NULL,
            mode TEXT NOT NULL,
            symbol TEXT NOT NULL,
            timeframe TEXT NOT NULL,
            candle_ts INTEGER NOT NULL,
            action TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            details TEXT DEFAULT '',
            UNIQUE(account,mode,symbol,timeframe,candle_ts,action)
        );
        CREATE TABLE IF NOT EXISTS positions (
            account TEXT NOT NULL, mode TEXT NOT NULL, symbol TEXT NOT NULL,
            qty REAL NOT NULL DEFAULT 0, avg_entry REAL NOT NULL DEFAULT 0,
            highest REAL NOT NULL DEFAULT 0,
            PRIMARY KEY(account,mode,symbol)
        );
        CREATE TABLE IF NOT EXISTS fills (
            id INTEGER PRIMARY KEY, ts REAL NOT NULL,
            account TEXT NOT NULL, mode TEXT NOT NULL, symbol TEXT NOT NULL,
            side TEXT NOT NULL, qty REAL NOT NULL, price REAL NOT NULL,
            fee_quote REAL NOT NULL, pnl REAL NOT NULL,
            order_id TEXT DEFAULT '', intent_id INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY, ts REAL NOT NULL, severity TEXT NOT NULL,
            message TEXT NOT NULL
        );
        """)


def log(message: str, severity: str = "INFO"):
    with _db() as db:
        db.execute("INSERT INTO events(ts,severity,message) VALUES (?,?,?)", (time.time(), severity, str(message)[:800]))


def events(limit: int = 80):
    with _db() as db:
        return db.execute("SELECT ts,severity,message FROM events ORDER BY id DESC LIMIT ?", (limit,)).fetchall()


def get_position(account: str, mode: str, symbol: str) -> dict:
    with _db() as db:
        r = db.execute("SELECT qty,avg_entry,highest FROM positions WHERE account=? AND mode=? AND symbol=?", (account,mode,symbol)).fetchone()
    return {"qty":r[0], "entry":r[1], "high":r[2]} if r else {"qty":0., "entry":0., "high":0.}


def update_high(account: str, mode: str, symbol: str, new_high: float) -> None:
    with _db() as db:
        db.execute("UPDATE positions SET highest=MAX(highest,?) WHERE account=? AND mode=? AND symbol=?", (new_high, account, mode, symbol))


def has_pending(account: str, mode: str) -> bool:
    with _db() as db:
        r = db.execute("SELECT 1 FROM intents WHERE account=? AND mode=? AND status IN ('pending','uncertain') LIMIT 1", (account,mode)).fetchone()
    return bool(r)


def pending_details(account: str, mode: str) -> list:
    with _db() as db:
        return db.execute("SELECT id,symbol,action,status,created_at FROM intents WHERE account=? AND mode=? AND status IN ('pending','uncertain') ORDER BY id DESC", (account,mode)).fetchall()


def begin_intent(account: str, exchange_id: str, mode: str, symbol: str, tf: str, candle_ts: int, action: str) -> int | None:
    with _db() as db:
        db.execute("BEGIN IMMEDIATE")
        if mode == "live" and db.execute("SELECT 1 FROM intents WHERE account=? AND mode=? AND status IN ('pending','uncertain')", (account,mode)).fetchone():
            raise RuntimeError("یک سفارش نامشخص قبلی وجود دارد؛ معامله متوقف شد")
        try:
            cur = db.execute("INSERT INTO intents(created_at,account,exchange_id,mode,symbol,timeframe,candle_ts,action) VALUES (?,?,?,?,?,?,?,?)",
                             (time.time(),account,exchange_id,mode,symbol,tf,candle_ts,action))
            return cur.lastrowid
        except sqlite3.IntegrityError:
            return None  # idempotency; never replay candle after restart


def mark_intent(intent_id: int, status: str, details: str = ""):
    if status not in ("failed", "uncertain", "filled", "cancelled"):
        raise ValueError("invalid status")
    with _db() as db:
        db.execute("UPDATE intents SET status=?,details=? WHERE id=?", (status,details[:1500],intent_id))


def record_fill(account: str, mode: str, symbol: str, side: str, qty: float,
                price: float, fee_quote: float, intent_id: int, order_id: str = "") -> float:
    """Apply a confirmed fill atomically. pnl is quote-denominated realized net PnL."""
    if qty <= 0 or price <= 0 or fee_quote < 0:
        raise ValueError("Invalid fill")
    with _db() as db:
        db.execute("BEGIN IMMEDIATE")
        if db.execute("SELECT 1 FROM fills WHERE intent_id=?", (intent_id,)).fetchone():
            raise RuntimeError("Fill already processed")
        r = db.execute("SELECT qty,avg_entry,highest FROM positions WHERE account=? AND mode=? AND symbol=?",
                       (account,mode,symbol)).fetchone()
        old_qty, old_entry, old_high = r if r else (0.,0.,0.)
        if side == "buy":
            new_qty = old_qty + qty
            entry = ((old_qty * old_entry) + (qty * price) + fee_quote) / new_qty
            high = max(old_high, price)
            pnl = 0.
        elif side == "sell":
            if qty > old_qty * (1 + 1e-8):
                raise ValueError("Cannot sell more than bot-tracked inventory")
            new_qty = max(0, old_qty - qty)
            entry = old_entry if new_qty > 1e-12 else 0.
            high = old_high if new_qty > 1e-12 else 0.
            pnl = (price - old_entry) * qty - fee_quote
        else:
            raise ValueError("Invalid side")
        db.execute("INSERT INTO positions(account,mode,symbol,qty,avg_entry,highest) VALUES(?,?,?,?,?,?) ON CONFLICT(account,mode,symbol) DO UPDATE SET qty=excluded.qty,avg_entry=excluded.avg_entry,highest=excluded.highest",
                   (account,mode,symbol,new_qty,entry,high))
        db.execute("INSERT INTO fills(ts,account,mode,symbol,side,qty,price,fee_quote,pnl,order_id,intent_id) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                   (time.time(),account,mode,symbol,side,qty,price,fee_quote,pnl,order_id,intent_id))
        db.execute("UPDATE intents SET status='filled',details=? WHERE id=?", (f"{qty:g} @ {price:g}",intent_id))
    return pnl


def realized_today(account: str, mode: str, symbol: str = "") -> float:
    # User-facing limit uses rolling 24h, instead of calendar-day timezone ambiguities.
    with _db() as db:
        quote = symbol.split("/")[-1] if "/" in symbol else None
        if quote:
            r = db.execute("SELECT COALESCE(SUM(pnl),0) FROM fills WHERE account=? AND mode=? AND symbol LIKE ? AND ts>=?", (account,mode,"%/"+quote,time.time()-86400)).fetchone()
        else:
            r = db.execute("SELECT COALESCE(SUM(pnl),0) FROM fills WHERE account=? AND mode=? AND ts>=?", (account,mode,time.time()-86400)).fetchone()
    return float(r[0])


def paper_cash(account: str, starting: float = 10000.0, symbol: str = "") -> float:
    with _db() as db:
        suffix="%/"+symbol.split("/")[-1] if "/" in symbol else "%"
        r = db.execute("SELECT COALESCE(SUM(CASE WHEN side='buy' THEN -(qty*price+fee_quote) ELSE qty*price-fee_quote END),0) FROM fills WHERE account=? AND mode='paper' AND symbol LIKE ?", (account,suffix)).fetchone()
    return starting + float(r[0])


def latest_fills(limit: int = 30):
    with _db() as db:
        return db.execute("SELECT ts,mode,symbol,side,qty,price,pnl FROM fills ORDER BY id DESC LIMIT ?", (limit,)).fetchall()


def reconcile_intent_manually(intent_id: int, account: str, explanation: str):
    """Dangerous: only after a human has reconciled balances and position.

    No UI call by default. We explicitly do NOT offer one-click reset of uncertain
    orders: would make a repeat buy possible following a lost network response.
    """
    raise NotImplementedError("Only a new audited reconciliation workflow may unblock unknown live orders")
