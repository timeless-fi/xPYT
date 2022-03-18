// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "v3-core/interfaces/callback/IUniswapV3SwapCallback.sol";

import {IQuoter} from "v3-periphery/interfaces/IQuoter.sol";

import {xPYT} from "../xPYT.sol";
import {PoolAddress} from "./lib/PoolAddress.sol";
import {OracleLibrary} from "./lib/OracleLibrary.sol";

/// @title UniswapV3xPYT
/// @author zefram.eth
/// @notice xPYT implementation using Uniswap V3 to swap NYT into PYT
contract UniswapV3xPYT is xPYT, IUniswapV3SwapCallback {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error Error_NotUniswapV3Pool();
    error Error_BothTokenDeltasAreZero();

    /// -----------------------------------------------------------------------
    /// Structs
    /// -----------------------------------------------------------------------

    struct SwapCallbackData {
        ERC20 tokenIn;
        ERC20 tokenOut;
        uint24 fee;
    }

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick + 1. Equivalent to getSqrtRatioAtTick(MIN_TICK) + 1
    /// Copied from v3-core/libraries/TickMath.sol
    uint160 internal constant MIN_SQRT_RATIO_PLUS_ONE = 4295128740;

    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick - 1. Equivalent to getSqrtRatioAtTick(MAX_TICK) - 1
    /// Copied from v3-core/libraries/TickMath.sol
    uint160 internal constant MAX_SQRT_RATIO_MINUS_ONE =
        1461446703485210103287273052203988822378723970341;

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    /// @notice The official Uniswap V3 factory address
    address public immutable uniswapV3Factory;

    /// @notice The Uniswap V3 Quoter deployment
    IQuoter public immutable uniswapV3Quoter;

    /// @notice The fee used by the Uniswap V3 pool used for swapping
    uint24 public immutable uniswapV3PoolFee;

    /// @notice The number of seconds in the past from which to take the TWAP of the Uniswap V3 pool
    uint32 public immutable uniswapV3TwapSecondsAgo;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        ERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint256 pounderRewardMultiplier_,
        uint256 minOutputMultiplier_,
        address uniswapV3Factory_,
        IQuoter uniswapV3Quoter_,
        uint24 uniswapV3PoolFee_,
        uint32 uniswapV3TwapSecondsAgo_
    )
        xPYT(
            asset_,
            name_,
            symbol_,
            pounderRewardMultiplier_,
            minOutputMultiplier_
        )
    {
        uniswapV3Factory = uniswapV3Factory_;
        uniswapV3Quoter = uniswapV3Quoter_;
        uniswapV3PoolFee = uniswapV3PoolFee_;
        uniswapV3TwapSecondsAgo = uniswapV3TwapSecondsAgo_;
    }

    /// -----------------------------------------------------------------------
    /// Uniswap V3 support
    /// -----------------------------------------------------------------------

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        // determine amount to pay
        uint256 amountToPay;
        if (amount0Delta > 0) {
            amountToPay = uint256(amount0Delta);
        } else if (amount1Delta > 0) {
            amountToPay = uint256(amount1Delta);
        } else {
            revert Error_BothTokenDeltasAreZero();
        }

        // decode callback data
        SwapCallbackData memory callbackData = abi.decode(
            data,
            (SwapCallbackData)
        );

        // verify sender
        address pool = PoolAddress.computeAddress(
            uniswapV3Factory,
            PoolAddress.getPoolKey(
                address(callbackData.tokenIn),
                address(callbackData.tokenOut),
                callbackData.fee
            )
        );
        if (msg.sender != address(pool)) {
            revert Error_NotUniswapV3Pool();
        }

        // pay tokens to the Uniswap V3 pool
        callbackData.tokenIn.safeTransfer(msg.sender, amountToPay);
    }

    /// -----------------------------------------------------------------------
    /// Internal utilities
    /// -----------------------------------------------------------------------

    /// @inheritdoc xPYT
    function _getTwapQuote(uint256 nytAmountIn)
        internal
        view
        virtual
        override
        returns (bool success, uint256 xPytAmountOut)
    {
        // get uniswap v3 pool
        address uniPool = PoolAddress.computeAddress(
            uniswapV3Factory,
            PoolAddress.getPoolKey(
                address(nyt),
                address(this),
                uniswapV3PoolFee
            )
        );

        // ensure oldest observation is at or before (block.timestamp - uniswapV3TwapSecondsAgo)
        uint32 oldestObservationSecondsAgo = OracleLibrary
            .getOldestObservationSecondsAgo(uniPool);
        if (oldestObservationSecondsAgo < uniswapV3TwapSecondsAgo) {
            return (false, 0);
        }

        // get mean tick from TWAP oracle
        (int24 arithmeticMeanTick, ) = OracleLibrary.consult(
            uniPool,
            uniswapV3TwapSecondsAgo
        );

        // convert mean tick to quote
        success = true;
        xPytAmountOut = OracleLibrary.getQuoteAtTick(
            arithmeticMeanTick,
            uint128(nytAmountIn),
            address(nyt),
            address(this)
        );
    }

    /// @inheritdoc xPYT
    function _swap(uint256 nytAmountIn)
        internal
        virtual
        override
        returns (uint256 xPytAmountOut)
    {
        // get uniswap v3 pool
        IUniswapV3Pool uniPool = IUniswapV3Pool(
            PoolAddress.computeAddress(
                uniswapV3Factory,
                PoolAddress.getPoolKey(
                    address(nyt),
                    address(this),
                    uniswapV3PoolFee
                )
            )
        );

        // do swap
        bytes memory swapCallbackData = abi.encode(
            SwapCallbackData({
                tokenIn: ERC20(address(nyt)),
                tokenOut: this,
                fee: uniswapV3PoolFee
            })
        );
        bool zeroForOne = address(nyt) < address(this);
        (int256 amount0, int256 amount1) = uniPool.swap(
            address(this),
            zeroForOne,
            int256(nytAmountIn),
            zeroForOne ? MIN_SQRT_RATIO_PLUS_ONE : MAX_SQRT_RATIO_MINUS_ONE,
            swapCallbackData
        );

        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    /// @inheritdoc xPYT
    function _quote(uint256 nytAmountIn)
        internal
        virtual
        override
        returns (uint256 xPytAmountOut)
    {
        bool zeroForOne = address(nyt) < address(this);
        return
            uniswapV3Quoter.quoteExactInputSingle(
                address(nyt),
                address(this),
                uniswapV3PoolFee,
                nytAmountIn,
                zeroForOne ? MIN_SQRT_RATIO_PLUS_ONE : MAX_SQRT_RATIO_MINUS_ONE
            );
    }
}
