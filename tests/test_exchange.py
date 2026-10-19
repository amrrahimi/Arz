from arzagent.exchanges import account_name, favorites_for


def test_paper_account_stable_and_key_hidden():
    assert account_name('kraken',None,'paper')=='paper:kraken'
    cred={'key':'secretkey','secret':'topsecret'}
    acct=account_name('kraken',cred,'live')
    assert 'secretkey' not in acct
    assert acct.startswith('live:kraken:')


def test_favorite_by_available_quote():
    assert favorites_for(['BTC/USD','BTC/EUR','ETH/USDT','XRP/EUR']) == ['BTC/USD','ETH/USDT','XRP/EUR']


def test_precision_and_exchange_minimum():
    from arzagent.exchanges import market_qty
    class Fake:
        def market(self,s):
            return {"limits":{"amount":{"min":0.0001},"cost":{"min":10}}}
        def amount_to_precision(self,s,q):
            return f"{q:.4f}"
    assert market_qty(Fake(),"BTC/USDT",20,100,"buy") == 0.198
    import pytest
    with pytest.raises(ValueError):
        market_qty(Fake(),"BTC/USDT",1,100,"buy")
