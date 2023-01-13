from brownie import chain


def test_claim_reward(
    bribe, user, gauge1, token1, token1_whale, add_bribe, gauge_controller, WEEK
):
    assert token1.balanceOf(user) == 0
    add_bribe(gauge1, token1, 2_000e18, token1_whale)
    gauge_controller.vote_for_gauge_weights(gauge1, 10_000, {"from": user})
    chain.sleep(WEEK)
    chain.mine()
    gauge_controller.checkpoint({"from": user})
    gauge_controller.checkpoint_gauge(gauge1, {"from": user})
    claimable = bribe.claimable(user, 0)
    assert claimable != 0
    bribe.claim_reward(0, {"from": user})
    assert token1.balanceOf(user) == claimable


def test_claim_after_update(
    bribe, user, gauge1, token1, token1_whale, add_bribe, gauge_controller, WEEK
):
    assert token1.balanceOf(user) == 0
    add_bribe(gauge1, token1, 2_000e18, token1_whale, 2)
    gauge_controller.vote_for_gauge_weights(gauge1, 10_000, {"from": user})
    chain.sleep(WEEK)
    chain.mine()
    gauge_controller.checkpoint({"from": user})
    gauge_controller.checkpoint_gauge(gauge1, {"from": user})
    claimable = bribe.claimable(user, 0)
    bribe.claim_reward(0, {"from": user})
    token1.approve(bribe, 2_000e18, {"from": token1_whale})
    bribe.modify_bribe(0, 1, 2_000e18, {"from": token1_whale})
    chain.sleep(WEEK)
    chain.mine()
    bribe.claimable(
        user, 0
    ) > 2 * claimable  # it's much more than two times since it's redistributing what wasn't claimed during the first week
