// SPDX-License-Identifier: MIT

pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import {IMasterChef} from "../interfaces/sushi/IMasterChef.sol";
import {IUniswapRouterV2} from "../interfaces/uniswap/IUniswapRouterV2.sol";

import "../interfaces/badger/IController.sol";

import {BaseStrategy} from "../deps/BaseStrategy.sol";

contract MyStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    // address public want // Inherited from BaseStrategy, the token the strategy wants, swaps into and tries to grow
    address public reward; // Token we farm and swap to want / lpComponent

    // pair info https://sushiswap-vision.vercel.app/pair/0x164fe0239d703379bddde3c80e4d4800a1cd452b

    address public constant CHEF = 0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd; // MasterChef contract address on mainnet
    address public constant SUSHISWAP_ROUTER =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    address public constant btc2xfli =
        0x0B498ff89709d3838a063f1dFA463091F9801c2b;
    address public constant wBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 public constant pid = 234; // BTC2XFLI-WBTC-SUSHI pool ID
    uint256 public slippage = 50; // in terms of bps = 0.5%
    uint256 public constant MAX_BPS = 10_000;

    // Used to signal to the Badger Tree that rewards where sent to it
    event TreeDistribution(
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );

    function initialize(
        address _governance,
        address _strategist,
        address _controller,
        address _keeper,
        address _guardian,
        address[2] memory _wantConfig,
        uint256[3] memory _feeConfig
    ) public initializer {
        __BaseStrategy_init(
            _governance,
            _strategist,
            _controller,
            _keeper,
            _guardian
        );

        /// @dev Add config here
        want = _wantConfig[0];
        reward = _wantConfig[1];

        performanceFeeGovernance = _feeConfig[0];
        performanceFeeStrategist = _feeConfig[1];
        withdrawalFee = _feeConfig[2];

        /// @dev do one off approvals here
        IERC20Upgradeable(want).safeApprove(CHEF, type(uint256).max);

        // Adding approve for uniswap router else it gives STF(Safe transfer failure) error
        IERC20Upgradeable(reward).safeApprove(
            SUSHISWAP_ROUTER,
            type(uint256).max
        );
        IERC20Upgradeable(wETH).safeApprove(
            SUSHISWAP_ROUTER,
            type(uint256).max
        );
        IERC20Upgradeable(wBTC).safeApprove(
            SUSHISWAP_ROUTER,
            type(uint256).max
        );
        IERC20Upgradeable(btc2xfli).safeApprove(
            SUSHISWAP_ROUTER,
            type(uint256).max
        );
    }

    /// ===== View Functions =====

    // @dev Specify the name of the strategy
    function getName() external pure override returns (string memory) {
        return "SLP-BTC2xFLI-WBTC-Sushi-Strategy";
    }

    // @dev Specify the version of the Strategy, for upgrades
    function version() external pure returns (string memory) {
        return "1.0";
    }

    /// @dev Balance of want currently held in strategy positions
    function balanceOfPool() public view override returns (uint256) {
        (uint256 staked, ) = IMasterChef(CHEF).userInfo(pid, address(this));
        return staked;
    }

    /// @dev Returns true if this strategy requires tending
    function isTendable() public view override returns (bool) {
        return balanceOfWant() > 0;
    }

    // @dev These are the tokens that cannot be moved except by the vault
    function getProtectedTokens()
        public
        view
        override
        returns (address[] memory)
    {
        address[] memory protectedTokens = new address[](3);
        protectedTokens[0] = want;
        protectedTokens[1] = reward;
        return protectedTokens;
    }

    /// ===== Permissioned Actions: Governance =====

    /// ===== Internal Core Implementations =====

    /// @dev security check to avoid moving tokens that would cause a rugpull, edit based on strat
    function _onlyNotProtectedTokens(address _asset) internal override {
        address[] memory protectedTokens = getProtectedTokens();

        for (uint256 x = 0; x < protectedTokens.length; x++) {
            require(
                address(protectedTokens[x]) != _asset,
                "Asset is protected"
            );
        }
    }

    /// @dev invest the amount of want
    /// @notice When this function is called, the controller has already sent want to this
    /// @notice Just get the current balance and then invest accordingly
    function _deposit(uint256 _amount) internal override {
        IMasterChef(CHEF).deposit(pid, _amount);
    }

    /// @dev utility function to withdraw everything for migration
    function _withdrawAll() internal override {
        IMasterChef(CHEF).withdraw(pid, balanceOfPool());
    }

    /// @dev withdraw the specified amount of want, liquidate from lpComponent to want, paying off any necessary debt for the conversion
    function _withdrawSome(uint256 _amount)
        internal
        override
        returns (uint256)
    {
        uint256 inPool = balanceOfPool();
        if (_amount > inPool) {
            _amount = inPool;
        }

        IMasterChef(CHEF).withdraw(pid, _amount);

        return _amount;
    }

    /// @dev Harvest from strategy mechanics, realizing increase in underlying position
    function harvest() external whenNotPaused returns (uint256 harvested) {
        _onlyAuthorizedActors();

        uint256 _before = IERC20Upgradeable(want).balanceOf(address(this));

        // Get total rewards (SUSHI)

        IMasterChef(CHEF).withdraw(pid, 0);

        uint256 rewardsAmount = IERC20Upgradeable(reward).balanceOf(
            address(this)
        );

        if (rewardsAmount > 0) {
            // Swap half sushi to btc2xfli and half to wbtc

            // Swap Sushi for wBTC through path: SUSHI -> wBTC
            uint256 sushiTowbtcAmount = rewardsAmount.mul(5_000).div(MAX_BPS);

            address[] memory path = new address[](3);
            path[0] = reward;
            path[1] = wETH;
            path[2] = wBTC;
            IUniswapRouterV2(SUSHISWAP_ROUTER).swapExactTokensForTokens(
                sushiTowbtcAmount,
                0,
                path,
                address(this),
                now
            );

            // Swap Sushi for btc2xfli through path: SUSHI -> btc2xfli
            uint256 sushiTobtc2xfliAmount = rewardsAmount.sub(
                sushiTowbtcAmount
            );
            path = new address[](4);
            path[0] = reward;
            path[1] = wETH;
            path[2] = wBTC;
            path[3] = btc2xfli;
            IUniswapRouterV2(SUSHISWAP_ROUTER).swapExactTokensForTokens(
                sushiTobtc2xfliAmount,
                0,
                path,
                address(this),
                now
            );

            // Add liquidity for BTC2xFLI-WBTC pool
            uint256 wbtcIn = IERC20Upgradeable(wBTC).balanceOf(address(this));
            uint256 btc2xfliIn = IERC20Upgradeable(btc2xfli).balanceOf(
                address(this)
            );

            IUniswapRouterV2(SUSHISWAP_ROUTER).addLiquidity(
                btc2xfli,
                wBTC,
                btc2xfliIn,
                wbtcIn,
                btc2xfliIn.mul(slippage).div(MAX_BPS),
                wbtcIn.mul(slippage).div(MAX_BPS),
                address(this),
                now
            );
        }
        // harvest rewards

        uint256 earned = IERC20Upgradeable(want).balanceOf(address(this)).sub(
            _before
        );

        /// @notice Keep this in so you get paid!
        (
            uint256 governancePerformanceFee,
            uint256 strategistPerformanceFee
        ) = _processPerformanceFees(earned);

        /// @dev Harvest event that every strategy MUST have, see BaseStrategy
        emit Harvest(earned, block.number);

        /// @dev Harvest must return the amount of want increased
        return earned;
    }

    // Alternative Harvest with Price received from harvester, used to avoid exessive front-running
    function harvest(uint256 price)
        external
        whenNotPaused
        returns (uint256 harvested)
    {}

    /// @dev Rebalance, Compound or Pay off debt here
    function tend() external whenNotPaused {
        _onlyAuthorizedActors();
        uint256 balanceOfWant = IERC20Upgradeable(want).balanceOf(
            address(this)
        );
        if (balanceOfWant > 0) {
            _deposit(balanceOfWant);
        }
    }

    /// @notice sets slippage tolerance for liquidity provision in terms of BPS ie.
    /// @notice minSlippage = 0
    /// @notice maxSlippage = 10_000
    function setSlippageTolerance(uint256 _s) external whenNotPaused {
        _onlyGovernanceOrStrategist();
        require(_s <= 10_000, "slippage out of bounds");
        slippage = _s;
    }

    /// ===== Internal Helper Functions =====

    /// @dev used to manage the governance and strategist fee, make sure to use it to get paid!
    function _processPerformanceFees(uint256 _amount)
        internal
        returns (
            uint256 governancePerformanceFee,
            uint256 strategistPerformanceFee
        )
    {
        governancePerformanceFee = _processFee(
            want,
            _amount,
            performanceFeeGovernance,
            IController(controller).rewards()
        );

        strategistPerformanceFee = _processFee(
            want,
            _amount,
            performanceFeeStrategist,
            strategist
        );
    }

    /// @dev used to manage the governance and strategist fee on earned rewards, make sure to use it to get paid!
    function _processRewardsFees(uint256 _amount, address _token)
        internal
        returns (uint256 governanceRewardsFee, uint256 strategistRewardsFee)
    {
        governanceRewardsFee = _processFee(
            _token,
            _amount,
            performanceFeeGovernance,
            IController(controller).rewards()
        );

        strategistRewardsFee = _processFee(
            _token,
            _amount,
            performanceFeeStrategist,
            strategist
        );
    }
}
