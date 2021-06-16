import brownie, math, time
from brownie import Contract
import time


def test_in_and_out(zap, accounts, crv, yveCrv, yvBoost, sushiswap, chain, user, weth):
    chain.snapshot()
    yveCrv.approve(zap, 1e30, {"from": user})
    crv.approve(zap, 1e30, {"from": user})

    balance0 = yvBoost.balanceOf(user)
    tx1 = zap.depositEth(1e18, user, {'from':user,'value':1e18})
    balance1 = yvBoost.balanceOf(user)
    print(tx1.events['DepositEth'])
    assert balance1 > balance0
    assert yveCrv.balanceOf(zap) == 0
    assert crv.balanceOf(zap) == 0
    assert yvBoost.balanceOf(zap) == 0
    assert weth.balanceOf(zap) == 0
    assert zap.balance() == 0

    tx2 = zap.depositYveCrv(1e21, user, {'from':user})
    balance2 = yvBoost.balanceOf(user)
    print(tx2.events['DepositYveCrv'])
    assert balance2 > balance1
    assert yveCrv.balanceOf(zap) == 0
    assert crv.balanceOf(zap) == 0
    assert yvBoost.balanceOf(zap) == 0
    assert weth.balanceOf(zap) == 0

    tx3 = zap.depositCrv(1e21, user, {'from':user})
    balance3 = yvBoost.balanceOf(user)
    print(tx3.events['DepositCrv'])
    assert balance3 > balance2
    assert yveCrv.balanceOf(zap) == 0
    assert crv.balanceOf(zap) == 0
    assert yvBoost.balanceOf(zap) == 0
    assert weth.balanceOf(zap) == 0
    chain.revert()

def test_deposit_eth_path(zap, accounts, crv, yveCrv, yvBoost, sushiswap, chain, user, weth):
    chain.snapshot()

    # MAKE CRV EXPENSIVE
    sushiswap.swapExactETHForTokens(
        0, [weth,crv], user, 2 ** 256 - 1, {'from':user,'value':1e22}
    )
    balance1 = yvBoost.balanceOf(user)
    tx1 = zap.depositEth(1e18, user, {'from':user,'value':1e18})
    balance2 = yvBoost.balanceOf(user)

    print(tx1.events['DepositEth'])
    assert tx1.events['DepositEth']['toCrv'] == False
    assert balance1 < balance2
    assert yveCrv.balanceOf(zap) == 0
    assert crv.balanceOf(zap) == 0
    assert yvBoost.balanceOf(zap) == 0
    assert weth.balanceOf(zap) == 0
    assert zap.balance() == 0

    chain.revert()
    
    # MAKE YVBOOST EXPENSIVE
    sushiswap.swapExactETHForTokens(
        0, [weth,yvBoost], user, 2 ** 256 - 1, {'from':user,'value':1e22}
    )
    balance1 = yvBoost.balanceOf(user)
    tx1 = zap.depositEth(1e18, user, {'from':user,'value':1e18})
    balance2 = yvBoost.balanceOf(user)
    print(tx1.events['DepositEth'])
    assert tx1.events['DepositEth']['toCrv'] == True
    assert balance1 < balance2
    assert yveCrv.balanceOf(zap) == 0
    assert crv.balanceOf(zap) == 0
    assert yvBoost.balanceOf(zap) == 0
    assert weth.balanceOf(zap) == 0
    assert zap.balance() == 0

    chain.revert()

def test_deposit_crv_path(zap, accounts, crv, yveCrv, yvBoost, sushiswap, chain, user, weth):
    balance1 = yvBoost.balanceOf(user)
    crv.approve(zap, 1e30, {"from": user})
    chain.snapshot()

    # MAKE CRV EXPENSIVE
    sushiswap.swapExactETHForTokens(
        0, [weth,crv], user, 2 ** 256 - 1, {'from':user,'value':1e22}
    )
    tx1 = zap.depositCrv(1e18, user, {'from':user})
    balance2 = yvBoost.balanceOf(user)
    print(tx1.events['DepositCrv'])
    assert tx1.events['DepositCrv']['minted'] == False
    assert balance2 > balance1
    assert yveCrv.balanceOf(zap) == 0
    assert crv.balanceOf(zap) == 0
    assert yvBoost.balanceOf(zap) == 0
    assert weth.balanceOf(zap) == 0
    assert zap.balance() == 0

    chain.revert()
    
    # MAKE YVBOOST EXPENSIVE
    sushiswap.swapExactETHForTokens(
        0, [weth,yvBoost], user, 2 ** 256 - 1, {'from':user,'value':1e22}
    )
    balance1 = yvBoost.balanceOf(user)
    tx1 = zap.depositCrv(1e18, user, {'from':user})
    balance2 = yvBoost.balanceOf(user)
    print(tx1.events['DepositCrv'])
    assert tx1.events['DepositCrv']['minted'] == True
    assert balance2 > balance1
    assert yveCrv.balanceOf(zap) == 0
    assert crv.balanceOf(zap) == 0
    assert yvBoost.balanceOf(zap) == 0
    assert weth.balanceOf(zap) == 0
    assert zap.balance() == 0

    chain.revert()