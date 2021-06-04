import brownie, math, time
from brownie import Contract
import time


def test_operation(zap, accounts, crv, yveCrv, yvBoost, sushiswap, chain,user):
    chain.snapshot()
    yveCrv.approve(zap, 1e30, {"from": user})
    crv.approve(zap, 1e30, {"from": user})

    zap.depositEth(1e18, user, {'from':user,'value':1e18})
    zap.depositYveCrv(1e21, user, {'from':user})
    zap.depositCrv(1e21, user, {'from':user})
    assert False