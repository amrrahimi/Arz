import pytest
from arzagent import storage

@pytest.fixture
def isolated(tmp_path,monkeypatch):
    monkeypatch.setattr(storage,'DB_PATH',tmp_path/'db.sqlite')
    storage.init_db()


def test_journal_no_duplicate(isolated):
    a=storage.begin_intent('acct','kraken','paper','BTC/USDT','5m',123,'BUY')
    assert a is not None
    assert storage.begin_intent('acct','kraken','paper','BTC/USDT','5m',123,'BUY') is None
    storage.record_fill('acct','paper','BTC/USDT','buy',.1,100, .01,a,'PAPER')
    pos=storage.get_position('acct','paper','BTC/USDT')
    assert pos['qty']==pytest.approx(.1)
    assert pos['entry']==pytest.approx(100.1)
    assert storage.paper_cash('acct') == pytest.approx(9989.99)


def test_cannot_sell_untracked_inventory(isolated):
    intent=storage.begin_intent('a','kraken','paper','BTC/USDT','1h',1,'SELL')
    with pytest.raises(ValueError):
        storage.record_fill('a','paper','BTC/USDT','sell',1,100,.1,intent)


def test_pnl_and_daily_loss(isolated):
    bid=storage.begin_intent('a','kraken','paper','BTC/USDT','1h',1,'BUY')
    storage.record_fill('a','paper','BTC/USDT','buy',1,100,.1,bid)
    sid=storage.begin_intent('a','kraken','paper','BTC/USDT','1h',2,'SELL')
    pnl=storage.record_fill('a','paper','BTC/USDT','sell',1,90,.1,sid)
    assert pnl==pytest.approx(-10.2)
    assert storage.realized_today('a','paper')==pytest.approx(-10.2)


def test_unknown_live_intent_blocks_repeated_orders(isolated):
    a=storage.begin_intent('acct','kraken','live','BTC/USDT','5m',123,'BUY')
    assert storage.has_pending('acct','live')
    with pytest.raises(RuntimeError):
        storage.begin_intent('acct','kraken','live','ETH/USDT','5m',124,'BUY')


def test_stop_loss_can_sell_same_closed_candle_as_buy(isolated):
    buy=storage.begin_intent('acct','kraken','paper','BTC/USDT','1d',999,'BUY')
    storage.record_fill('acct','paper','BTC/USDT','buy',1,100,.1,buy)
    sell=storage.begin_intent('acct','kraken','paper','BTC/USDT','1d',999,'SELL')
    assert sell is not None and sell != buy
    storage.record_fill('acct','paper','BTC/USDT','sell',1,93,.1,sell)
    assert storage.get_position('acct','paper','BTC/USDT')['qty']==0
    assert storage.begin_intent('acct','kraken','paper','BTC/USDT','1d',999,'SELL') is None
