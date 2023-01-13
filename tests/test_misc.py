def test_set_operator(operator, bribe, user):
    with brownie.reverts():
        bribe.set_operator(user, {"from": user})
    with brownie.reverts():
        bribe.accept_operator({"from": user})
    bribe.set_operator(user, {"from": operator})
    bribe.accept_operator({"from": user})
