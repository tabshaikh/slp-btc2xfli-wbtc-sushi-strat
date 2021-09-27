import brownie
from brownie import *
from helpers.constants import MaxUint256
from helpers.SnapshotManager import SnapshotManager
from helpers.time import days

"""
  TODO: Put your tests here to prove the strat is good!
  See test_harvest_flow, for the basic tests
  See test_strategy_permissions, for tests at the permissions level
"""


def test_custom_harvest(deployer, vault, strategy, want):
    # Setup
    startingBalance = want.balanceOf(deployer)
    reward = interface.IERC20(strategy.reward())

    depositAmount = startingBalance // 2
    assert startingBalance >= depositAmount
    assert startingBalance >= 0
    # End Setup
    print("Setup Complete")

    # Deposit
    # Before deposit we want balance of vault to be 0
    assert want.balanceOf(vault) == 0

    want.approve(vault, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    available = vault.available()
    # After deposit check if available balance > 0
    assert available > 0
    print("Avaiable amount in vault: ", vault.available())

    # deposit into strat
    vault.earn({"from": deployer})

    chef = Contract.from_explorer(strategy.CHEF())
    poolId = strategy.pid()
    (amount, _) = chef.userInfo(poolId, strategy.address)
    # check if deposited amount is > 0
    assert amount > 0

    chain.sleep(days(1))  # sleep for a day
    chain.mine(500)  # Mine so we get some interest

    # Harvest rewards
    strategy.harvest({"from": deployer})

    # Strategy should have some want after swapping rewards of harvest
    assert strategy.balanceOfWant() > 0
    assert strategy.isTendable()
    # Strategy shouldn't have any rewards left
    assert reward.balanceOf(strategy) == 0

    strategy.tend({"from": deployer})
    # Strategy should re-deposit all extra want
    assert strategy.balanceOfWant() == 0
