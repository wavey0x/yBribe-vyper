from brownie import chain


def test_create_claim(
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
