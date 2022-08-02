// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./interfaces/IMorpho.sol";
import "./interfaces/ILens.sol";
import "./interfaces/IUniswapV2Router02.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;

    IMorpho public constant MORPHO =
        IMorpho(0x8888882f8f843896699869179fB6E4f7e3B58888);
    ILens public constant LENS =
        ILens(0x930f1b46e1D081Ec1524efD95752bE3eCe51EF67);
    // MM_WANT = Morpho Market for want token
    address public constant MM_WANT =
        0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IUniswapV2Router02 private constant UNI_V2_ROUTER =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniswapV2Router02 private constant SUSHI_V2_ROUTER =
        IUniswapV2Router02(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    IUniswapV2Router02 public currentV2Router;
    uint256 public maxGasForMatching = 100000;
    uint256 public minCompToSell = 0.1 ether; // minimum amount of COMP to be sold

    constructor(address _vault) BaseStrategy(_vault) {
        // You can set these parameters on deployment to whatever you want
        // maxReportDelay = 6300;
        // profitFactor = 100;
        // debtThreshold = 0;
        want.safeApprove(address(MORPHO), type(uint256).max);
        currentV2Router = SUSHI_V2_ROUTER;
        IERC20 comp = IERC20(COMP);
        comp.safeApprove(address(SUSHI_V2_ROUTER), type(uint256).max);
        comp.safeApprove(address(UNI_V2_ROUTER), type(uint256).max);
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        return "StrategyMorphoDAI";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return want.balanceOf(address(this)) + balanceOfMMWant();
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        claimComp();
        sellComp();

        uint256 totalDebt = vault.strategies(address(this)).totalDebt;
        uint256 totalAssetsAfterProfit = estimatedTotalAssets();
        _profit = totalAssetsAfterProfit > totalDebt
            ? totalAssetsAfterProfit - totalDebt
            : 0;

        if (_debtOutstanding > 0) {
            (_debtPayment, _loss) = liquidatePosition(_debtOutstanding);
        }
        // Net profit and loss calculation
        if (_loss > _profit) {
            _loss -= _profit;
            _profit = 0;
        } else {
            _profit -= _loss;
            _loss = 0;
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        // TODO: Do something to invest excess `want` tokens (from the Vault) into your positions
        // NOTE: Try to adjust positions so that `_debtOutstanding` can be freed up on *next* harvest (not immediately)
        uint256 wantBalance = want.balanceOf(address(this));
        if (wantBalance > _debtOutstanding) {
            MORPHO.supply(
                MM_WANT,
                address(this),
                wantBalance - _debtOutstanding,
                maxGasForMatching
            );
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 wantBalance = want.balanceOf(address(this));
        if (_amountNeeded > wantBalance) {
            _liquidatedAmount = Math.min(
                _amountNeeded - wantBalance,
                balanceOfMMWant()
            );
            MORPHO.withdraw(MM_WANT, _liquidatedAmount);
            unchecked {
                _loss = _amountNeeded - _liquidatedAmount;
            }
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        uint256 balanceToWithdraw = balanceOfMMWant();
        if (balanceToWithdraw > 0) {
            MORPHO.withdraw(MM_WANT, balanceToWithdraw);
        }
        return want.balanceOf(address(this));
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary
    function prepareMigration(address _newStrategy) internal override {
        liquidateAllPositions();
        claimComp();
        sellComp();
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    // solhint-disable-next-line no-empty-blocks
    {

    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        // TODO create an accurate price oracle
        return _amtInWei;
    }

    /**
     * @notice
     *  Set the maximum amount of gas to consume to get matched in peer-to-peer.
     * @dev
     *  This value is needed in morpho supply liquidity calls.
     * @param _maxGasForMatching new gas value in
     */
    function setMaxGasForMatching(uint256 _maxGasForMatching)
        external
        onlyAuthorized
    {
        maxGasForMatching = _maxGasForMatching;
    }

    /**
     * @notice
     *  Set toggle v2 swap router between sushiv2 and univ2
     */
    function setToggleV2Router() external onlyAuthorized {
        currentV2Router = currentV2Router == SUSHI_V2_ROUTER
            ? UNI_V2_ROUTER
            : SUSHI_V2_ROUTER;
    }

    /**
     * @notice
     *  Set the minimum amount of compount token need to claim or sell it for `want` token.
     */
    function setMinCompToSell(uint256 _minCompToSell) external onlyAuthorized {
        minCompToSell = _minCompToSell;
    }

    /**
     * @notice
     *  Returns the current supply of want token in Moprho Market.
     * @return _balance of `want` token supplied to Morpho Market
     */
    function balanceOfMMWant() public view returns (uint256 _balance) {
        (, , _balance) = LENS.getCurrentSupplyBalanceInOf(
            MM_WANT,
            address(this)
        );
    }

    function claimComp() internal {
        address[] memory pools = new address[](1);
        pools[0] = MM_WANT;
        if (
            LENS.getUserUnclaimedRewards(pools, address(this)) > minCompToSell
        ) {
            // claim the underlying pool's rewards, currently COMP token
            MORPHO.claimRewards(pools, false);
        }
    }

    //sell comp function
    // see https://etherscan.io/address/0x62EA2aCe7a7861394f4A38B84D119498DBBb022c#code for different swaps
    function sellComp() internal {
        uint256 compBalance = IERC20(COMP).balanceOf(address(this));
        if (compBalance > minCompToSell) {
            currentV2Router.swapExactTokensForTokens(
                compBalance,
                0,
                getTokenOutPathV2(COMP, address(want)),
                address(this),
                block.timestamp
            );
        }
    }

    function getTokenOutPathV2(address _tokenIn, address _tokenOut)
        internal
        pure
        returns (address[] memory _path)
    {
        bool isWeth = _tokenIn == address(WETH) || _tokenOut == address(WETH);
        _path = new address[](isWeth ? 2 : 3);
        _path[0] = _tokenIn;

        if (isWeth) {
            _path[1] = _tokenOut;
        } else {
            _path[1] = address(WETH);
            _path[2] = _tokenOut;
        }
    }
}
