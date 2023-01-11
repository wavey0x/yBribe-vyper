from brownie import chain
import brownie


def test_add_bribes(gauge1, token1, token1_whale, add_bribe, bribe, WEEK):
    next_week = (chain.time() // WEEK + 1) * WEEK
    amount = 2_000e18
    add_bribe(gauge1, token1, amount, token1_whale)
    bribes = bribe.bribes(0).dict()
    assert bribes["gauge"] == gauge1
    assert bribes["owner"] == token1_whale
    assert bribes["reward_token"] == token1
    assert bribes["reward_amount"] == amount
    assert bribes["duration"] == 1
    assert bribes["end"] == next_week + WEEK
    assert bribes["blocked_list"] == []


def test_close_bribe(gauge1, token1, token1_whale, add_bribe, bribe, WEEK):
    amount = 2_000e18
    add_bribe(gauge1, token1, amount, token1_whale)
    chain.sleep(WEEK)
    tx = bribe.close_bribe(0, {"from": token1_whale})
    assert len(tx.events) == 0
    chain.sleep(WEEK)
    tx = bribe.close_bribe(0, {"from": token1_whale})
    assert tx.events["BribeClosed"]["remainingReward"] == amount


def test_update_owner(gauge1, token1, token1_whale, add_bribe, bribe, user):
    amount = 2_000e18
    add_bribe(gauge1, token1, amount, token1_whale)
    with brownie.reverts():
        bribe.update_owner(0, user, {"from": user})
    bribe.update_owner(0, user, {"from": token1_whale})
