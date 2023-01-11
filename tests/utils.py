import brownie
from brownie import Contract, convert


def to_address(i):
    return convert.to_address(convert.to_bytes(i, "bytes20"))
