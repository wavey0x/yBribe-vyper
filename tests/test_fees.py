import brownie
from brownie import Contract, accounts, chain
import pytest


def test_fees(fee_recipient, bribe, operator, gauge1, token1, token1_whale, add_bribe):
    amount = 2_000e18
    bribe.set_fee_recipient(fee_recipient, {"from": operator})
    assert token1.balanceOf(fee_recipient) == 0

    fee = bribe.deposit_fee()
    # Fee is taken on Add
    tx = add_bribe(gauge1, token1, amount, token1_whale)
    fee_amt = tx.events["BribeAdded"]["deposit_fee"]
    assert token1.balanceOf(fee_recipient) == amount * fee // 10**18
    assert fee_amt == amount * fee // 10**18


def test_set_fee_recipient(fee_recipient, bribe, operator, user):
    with brownie.reverts():
        bribe.set_fee_recipient(fee_recipient, {"from": user})
    with brownie.reverts():
        bribe.set_fee_recipient(fee_recipient, {"from": fee_recipient})

    bribe.set_fee_recipient(fee_recipient, {"from": operator})
    bribe.set_fee_recipient(operator, {"from": fee_recipient})


def test_set_update_fee(operator, bribe, user):
    with brownie.reverts():
        bribe.update_fee(2 * 10**16, {"from": user})
    with brownie.reverts():
        bribe.update_fee(10 * 10**16, {"from": operator})
    bribe.update_fee(2 * 10**16, {"from": operator})
