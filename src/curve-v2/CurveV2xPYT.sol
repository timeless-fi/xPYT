// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {FullMath} from "timeless/lib/FullMath.sol";

import {xPYT} from "../xPYT.sol";
import {ICurveCryptoSwap2ETH} from "./external/ICurveCryptoSwap2ETH.sol";

/// @title CurveV2xPYT
/// @author zefram.eth
/// @notice xPYT implementation using Curve V2 to swap NYT into PYT
/// @dev Assumes for all Curve pools used, coins[0] is NYT and coins[1] is xPYT.
contract CurveV2xPYT is xPYT {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error CurveV2xPYT__AlreadyInitialized();

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice The Curve V2 pool to swap with
    ICurveCryptoSwap2ETH public curvePool;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        ERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint256 pounderRewardMultiplier_,
        uint256 minOutputMultiplier_
    )
        xPYT(
            asset_,
            name_,
            symbol_,
            pounderRewardMultiplier_,
            minOutputMultiplier_
        )
    {}

    function initialize(ICurveCryptoSwap2ETH curvePool_) external {
        // can't initialize twice
        if (address(curvePool) != address(0)) {
            revert CurveV2xPYT__AlreadyInitialized();
        }

        curvePool = curvePool_;

        // initialize allowance slot to make future swaps cheaper
        nyt.approve(address(curvePool_), 1);
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
        uint256 xPytPriceInNyt = curvePool.price_oracle(); // price of xPYT in NYT, scaled by ONE. Unit is NYT/xPYT
        xPytAmountOut = FullMath.mulDiv(nytAmountIn, ONE, xPytPriceInNyt);
        success = true;
    }

    /// @inheritdoc xPYT
    function _swap(uint256 nytAmountIn)
        internal
        virtual
        override
        returns (uint256 xPytAmountOut)
    {
        ICurveCryptoSwap2ETH curvePool_ = curvePool;
        nyt.approve(address(curvePool_), nytAmountIn + 1);
        return curvePool_.exchange(0, 1, nytAmountIn, 0, false, address(this));
    }

    /// @inheritdoc xPYT
    function _quote(uint256 nytAmountIn)
        internal
        virtual
        override
        returns (uint256 xPytAmountOut)
    {
        return curvePool.get_dy(0, 1, nytAmountIn);
    }
}
