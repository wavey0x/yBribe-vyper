import pytest, requests
from brownie import config, chain
from brownie import Contract


@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


@pytest.fixture
def crv():
    token_address = "0xD533a949740bb3306d119CC777fa900bA034cd52"
    yield Contract(token_address)


@pytest.fixture
def vecrv():
    token_address = "0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2"
    yield Contract(token_address)


@pytest.fixture
def gov(accounts):
    yield accounts.at("0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52", force=True)


@pytest.fixture
def user(accounts, crv, vecrv):
    user = accounts[0]
    w = accounts.at("0x8dAE6Cb04688C62d939ed9B68d32Bc62e49970b1", force=True)
    crv.transfer(user, crv.balanceOf(w), {"from": w})
    crv.approve(vecrv, 2**256 - 1, {"from": user})
    # 2 year lock
    vecrv.create_lock(
        crv.balanceOf(user), chain.time() + (2 * 365 * 24 * 60 * 60), {"from": user}
    )
    yield user


@pytest.fixture
def bribe(user, yBribe):
    bribe = user.deploy(yBribe)
    return bribe


@pytest.fixture
def helper(BribeHelper, user):
    helper = user.deploy(BribeHelper)
    return helper


@pytest.fixture
def rewards(accounts):
    yield accounts[1]


@pytest.fixture
def guardian(accounts):
    yield accounts[2]


@pytest.fixture
def management(accounts):
    yield accounts[3]


@pytest.fixture
def strategist(accounts):
    yield accounts[4]


@pytest.fixture
def keeper(accounts):
    yield accounts[5]


@pytest.fixture
def token1():  # SPELL
    token_address = "0x090185f2135308BaD17527004364eBcC2D37e5F6"
    yield Contract(token_address)


@pytest.fixture
def token2():  # INV
    token_address = "0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68"
    yield Contract(token_address)


@pytest.fixture
def fresh_token():  # INV
    token_address = "0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984"
    yield Contract(token_address)


@pytest.fixture
def fresh_token_whale(accounts, fresh_token, bribe):  # INV
    w = accounts.at("0x1a9C8182C09F50C8318d769245beA52c32BE35BC", force=True)
    u2 = accounts[1]
    fresh_token.transfer(u2, fresh_token.balanceOf(w), {"from": w})
    fresh_token.approve(bribe, 2**256 - 1, {"from": u2})
    yield u2


@pytest.fixture
def gauge1():  # MIM
    return Contract("0xd8b712d29381748dB89c36BCa0138d7c75866ddF")


@pytest.fixture
def gauge2():  # DOLA
    return Contract("0x8Fa728F393588E8D8dD1ca397E9a710E53fA553a")


@pytest.fixture
def token1_whale(accounts):
    return accounts.at("0x090185f2135308BaD17527004364eBcC2D37e5F6", force=True)


@pytest.fixture
def token2_whale(accounts):
    return accounts.at("0x1637e4e9941D55703a7A5E7807d6aDA3f7DCD61B", force=True)


@pytest.fixture
def token2_whale(accounts):
    return accounts.at("0x1637e4e9941D55703a7A5E7807d6aDA3f7DCD61B", force=True)


@pytest.fixture
def gauge_controller():
    return Contract("0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB")


@pytest.fixture
def WEEK():
    return 86400 * 7


@pytest.fixture(scope="session")
def RELATIVE_APPROX():
    # making this more lenient bc of single sided deposits incurring slippage
    yield 1e-3


@pytest.fixture
def voter1(accounts):
    return accounts.at("0x989AEb4d175e16225E39E87d0D97A3360524AD80", force=True)


@pytest.fixture
def voter2(accounts):
    return accounts.at("0xF147b8125d2ef93FB6965Db97D6746952a133934", force=True)


@pytest.fixture
def add_bribe(bribe):
    def add_bribe(gauge, token, amount, whale, weeks=1, blocklist=[]):
        token.approve(bribe, amount, {"from": whale})
        bribe.add_bribe(gauge, token, amount, weeks, blocklist, {"from": whale})

    yield add_bribe
