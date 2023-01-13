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


def test_modify_bribe(
    gauge1, token1, token1_whale, add_bribe, bribe, WEEK, user, accounts
):
    amount = 2_000e18
    next_week = (chain.time() // WEEK + 1) * WEEK
    tx = add_bribe(gauge1, token1, amount, token1_whale)
    assert tx.return_value == bribe.next_id() - 1
    token1.approve(bribe, amount, {"from": token1_whale})
    with brownie.reverts():
        bribe.modify_bribe(0, 1, amount, {"from": user})

    with brownie.reverts():
        bribe.modify_bribe(0, 1, 0, {"from": token1_whale})

    bribe.modify_bribe(0, 1, amount, {"from": token1_whale})
    modified_bribe = bribe.modified_bribe(0).dict()
    assert modified_bribe["duration"] == 2
    assert modified_bribe["reward_amount"] == amount * 2
    assert modified_bribe["end"] == next_week + WEEK * 2

    token1.approve(bribe, 2**256 - 1, {"from": token1_whale})
    bribe.modify_bribe(0, 1, amount, [accounts[0], accounts[1]], {"from": token1_whale})
    assert bribe.modified_bribe(0)["blocked_list_modified"] == True
    count = 0
    for i in range(0, 100):
        try:
            len(bribe.modified_blocked_list(0, i))
            count += 1
        except:
            break
    assert count == 2
