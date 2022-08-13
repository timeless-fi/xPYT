// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {NegativeYieldToken} from "timeless/NegativeYieldToken.sol";
import {PerpetualYieldToken} from "timeless/PerpetualYieldToken.sol";

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";

import {IQuoter} from "v3-periphery/interfaces/IQuoter.sol";

import {xPYT} from "../xPYT.sol";
import {TickMath} from "./lib/TickMath.sol";
import {UniswapV3xPYT} from "./UniswapV3xPYT.sol";

/// @title UniswapV3xPYTFactory
/// @author zefram.eth
/// @notice Factory for deploying UniswapV3xPYT contracts
contract UniswapV3xPYTFactory {
    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event DeployXPYT(
        PerpetualYieldToken indexed pyt,
        xPYT deployed,
        IUniswapV3Pool pool
    );

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    IUniswapV3Factory public immutable uniswapV3Factory;
    IQuoter public immutable uniswapV3Quoter;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(IUniswapV3Factory uniswapV3Factory_, IQuoter uniswapV3Quoter_) {
        uniswapV3Factory = uniswapV3Factory_;
        uniswapV3Quoter = uniswapV3Quoter_;
    }

    /// -----------------------------------------------------------------------
    /// Public functions
    /// -----------------------------------------------------------------------

    /// @notice Deploys a UniswapV3xPYT contract and its corresponding Uniswap V3 pool.
    /// @param pyt The PYT to deploy the xPYT for
    /// @param nyt The NYT associated with the PYT
    /// @param name_ The name of the xPYT token
    /// @param symbol_ The symbol of the xPYT token
    /// @param pounderRewardMultiplier_ The proportion of the yield claimed in pound() to give to the caller as reward
    /// @param minOutputMultiplier_ The minimum acceptable ratio between the NYT output in pound() and the expected NYT output
    /// based on the TWAP
    /// @param uniswapV3PoolFee_ The fee used by the Uniswap V3 pool used for swapping
    /// @param uniswapV3TwapSecondsAgo_ The number of seconds in the past from which to take the TWAP of the Uniswap V3 pool
    /// @param initialTickAssumingNytIsToken0 The initial tick of the Uniswap pool, which determines the initial pricing.
    /// Should be the tick assuming NYT is token0 of the pool, but if that's not the case it will be negated.
    /// @param observationCardinalityNext The initial observationCardinalityNext value of the Uniswap pool, which determines
    /// the maximum lookback period of the TWAP oracle. Set to 0 to not update the cardinality.
    /// @return deployed The deployed xPYT
    /// @return pool The deployed Uniswap pool
    function deployUniswapV3xPYT(
        PerpetualYieldToken pyt,
        NegativeYieldToken nyt,
        string memory name_,
        string memory symbol_,
        uint256 pounderRewardMultiplier_,
        uint256 minOutputMultiplier_,
        uint24 uniswapV3PoolFee_,
        uint32 uniswapV3TwapSecondsAgo_,
        int24 initialTickAssumingNytIsToken0,
        uint16 observationCardinalityNext
    ) external returns (xPYT deployed, IUniswapV3Pool pool) {
        // deploy xPYT
        deployed = new UniswapV3xPYT(
            pyt,
            name_,
            symbol_,
            pounderRewardMultiplier_,
            minOutputMultiplier_,
            address(uniswapV3Factory),
            uniswapV3Quoter,
            uniswapV3PoolFee_,
            uniswapV3TwapSecondsAgo_
        );

        // deploy Uniswap pool
        pool = IUniswapV3Pool(
            uniswapV3Factory.createPool(
                address(nyt),
                address(deployed),
                uniswapV3PoolFee_
            )
        );

        // initialize pool price
        if (address(nyt) > address(deployed)) {
            // NYT is actually token1 of the pool
            // negate initial tick
            initialTickAssumingNytIsToken0 = -initialTickAssumingNytIsToken0;
        }
        pool.initialize(
            TickMath.getSqrtRatioAtTick(initialTickAssumingNytIsToken0)
        );

        // update Uniswap pool observation
        if (observationCardinalityNext != 0) {
            pool.increaseObservationCardinalityNext(observationCardinalityNext);
        }

        emit DeployXPYT(pyt, deployed, pool);
    }
}
