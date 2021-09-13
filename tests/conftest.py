from brownie import (
    accounts,
    interface,
    Controller,
    SettV3,
    MyStrategy,
)
from config import (
    BADGER_DEV_MULTISIG,
    WANT,
    REWARD_TOKEN,
    PROTECTED_TOKENS,
    FEES,
)
from dotmap import DotMap
import pytest
import time


@pytest.fixture
def deployed():
    """
    Deploys, vault, controller and strats and wires them up for you to test
    """
    deployer = accounts[0]

    strategist = deployer
    keeper = deployer
    guardian = deployer

    governance = accounts.at(BADGER_DEV_MULTISIG, force=True)

    controller = Controller.deploy({"from": deployer})
    controller.initialize(BADGER_DEV_MULTISIG, strategist, keeper, BADGER_DEV_MULTISIG)

    sett = SettV3.deploy({"from": deployer})
    sett.initialize(
        WANT,
        controller,
        BADGER_DEV_MULTISIG,
        keeper,
        guardian,
        False,
        "prefix",
        "PREFIX",
    )

    sett.unpause({"from": governance})
    controller.setVault(WANT, sett)

    ## TODO: Add guest list once we find compatible, tested, contract
    # guestList = VipCappedGuestListWrapperUpgradeable.deploy({"from": deployer})
    # guestList.initialize(sett, {"from": deployer})
    # guestList.setGuests([deployer], [True])
    # guestList.setUserDepositCap(100000000)
    # sett.setGuestList(guestList, {"from": governance})

    ## Start up Strategy
    strategy = MyStrategy.deploy({"from": deployer})
    strategy.initialize(
        BADGER_DEV_MULTISIG,
        strategist,
        controller,
        keeper,
        guardian,
        PROTECTED_TOKENS,
        FEES,
        {"from": deployer},
    )

    ## Tool that verifies bytecode (run independently) <- Webapp for anyone to verify

    ## Set up tokens
    want = interface.IERC20(WANT)
    # lpComponent = interface.IERC20(LP_COMPONENT)
    rewardToken = interface.IERC20(REWARD_TOKEN)

    ## Wire up Controller to Strart
    ## In testing will pass, but on live it will fail
    controller.approveStrategy(WANT, strategy, {"from": governance})
    controller.setStrategy(WANT, strategy, {"from": deployer})

    btc2xfli_address = strategy.btc2xfli()
    wbtc_address = strategy.wBTC()
    SUSHI = strategy.reward()
    btc2xfli = interface.IERC20(btc2xfli_address)
    wbtc = interface.IERC20(wbtc_address)
    sushi = interface.IERC20(SUSHI)

    ## Uniswap some tokens here
    router = interface.IUniswapRouterV2(strategy.SUSHISWAP_ROUTER())

    sushi.approve(router.address, 999999999999999999999999999999, {"from": deployer})
    btc2xfli.approve(router.address, 999999999999999999999999999999, {"from": deployer})
    wbtc.approve(router.address, 999999999999999999999999999999, {"from": deployer})

    deposit_amount = 15 * 10 ** 18

    # Buy wbtc with path ETH -> WETH -> WBTC
    router.swapExactETHForTokens(
        0,
        ["0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", wbtc_address],
        deployer,
        9999999999999999,
        {"value": deposit_amount, "from": deployer},
    )

    # Buy btc2xfli with path ETH -> WETH -> btc2xfli
    router.swapExactETHForTokens(
        0,
        ["0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", wbtc_address, btc2xfli_address],
        deployer,
        9999999999999999,
        {"value": deposit_amount, "from": deployer},
    )

    # Add WETH-SUSHI liquidity
    router.addLiquidity(
        btc2xfli_address,
        wbtc_address,
        btc2xfli.balanceOf(deployer),
        wbtc.balanceOf(deployer),
        btc2xfli.balanceOf(deployer) * 0.005,
        wbtc.balanceOf(deployer) * 0.005,
        deployer,
        int(time.time()) + 12000,
        {"from": deployer},
    )

    assert want.balanceOf(deployer) > 0
    print("Initial Want Balance: ", want.balanceOf(deployer.address))

    return DotMap(
        deployer=deployer,
        controller=controller,
        vault=sett,
        sett=sett,
        strategy=strategy,
        # guestList=guestList,
        want=want,
        # lpComponent=lpComponent,
        rewardToken=rewardToken,
    )


## Contracts ##


@pytest.fixture
def vault(deployed):
    return deployed.vault


@pytest.fixture
def sett(deployed):
    return deployed.sett


@pytest.fixture
def controller(deployed):
    return deployed.controller


@pytest.fixture
def strategy(deployed):
    return deployed.strategy


## Tokens ##


@pytest.fixture
def want(deployed):
    return deployed.want


@pytest.fixture
def tokens():
    return [WANT, REWARD_TOKEN]


## Accounts ##


@pytest.fixture
def deployer(deployed):
    return deployed.deployer


@pytest.fixture
def strategist(strategy):
    return accounts.at(strategy.strategist(), force=True)


@pytest.fixture
def settKeeper(vault):
    return accounts.at(vault.keeper(), force=True)


@pytest.fixture
def strategyKeeper(strategy):
    return accounts.at(strategy.keeper(), force=True)
