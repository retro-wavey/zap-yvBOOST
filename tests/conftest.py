import pytest
from brownie import config
from brownie import Contract


@pytest.fixture
def gov(accounts):
    yield accounts.at("0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52", force=True)

@pytest.fixture
def sushiswap(accounts):
    yield Contract("0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F")

@pytest.fixture
def crv(accounts):
    yield Contract("0xD533a949740bb3306d119CC777fa900bA034cd52")

@pytest.fixture
def yveCrv(accounts):
    yield Contract("0xc5bddf9843308380375a611c18b50fb9341f502a")

@pytest.fixture
def crv_whale(accounts):
    yield accounts.at("0xF977814e90dA44bFA03b6295A0616a897441aceC", force=True)

@pytest.fixture
def yveCrv_whale(accounts):
    yield accounts.at("0x2D407dDb06311396fE14D4b49da5F0471447d45C", force=True)
     
@pytest.fixture
def user(accounts,crv_whale, crv, yveCrv,yveCrv_whale):
    user = accounts[0]
    eth_whale = accounts.at("0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8", force=True)
    eth_whale.transfer(user, "10000 ether")
    crv.transfer(user, crv.balanceOf(crv_whale),{'from':crv_whale})
    yveCrv.transfer(user, yveCrv.balanceOf(yveCrv_whale),{'from':yveCrv_whale})
    yield user

@pytest.fixture
def yvBoost(accounts):
    yield Contract("0x9d409a0A012CFbA9B15F6D4B36Ac57A46966Ab9a")

@pytest.fixture
def yvBoost(accounts):
    yield Contract("0x9d409a0A012CFbA9B15F6D4B36Ac57A46966Ab9a")

@pytest.fixture
def weth():
    yield Contract("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")

@pytest.fixture
def zap(Zap, gov):
    zap = gov.deploy(Zap)
    yield zap
