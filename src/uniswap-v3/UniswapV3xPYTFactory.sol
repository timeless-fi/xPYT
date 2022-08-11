// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {NegativeYieldToken} from "timeless/NegativeYieldToken.sol";
import {PerpetualYieldToken} from "timeless/PerpetualYieldToken.sol";

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";

import {IQuoter} from "v3-periphery/interfaces/IQuoter.sol";

import {xPYT} from "../xPYT.sol";
import {UniswapV3xPYT} from "./UniswapV3xPYT.sol";

/// @title UniswapV3xPYTFactory
/// @author zefram.eth
/// @notice Factory for deploying xPYT contracts
contract UniswapV3xPYTFactory {
    event DeployXPYT(PerpetualYieldToken indexed pyt, xPYT deployed);

    IUniswapV3Factory public immutable uniswapV3Factory;
    IQuoter public immutable uniswapV3Quoter;

    constructor(IUniswapV3Factory uniswapV3Factory_, IQuoter uniswapV3Quoter_) {
        uniswapV3Factory = uniswapV3Factory_;
        uniswapV3Quoter = uniswapV3Quoter_;
    }

    function deployUniswapV3xPYT(
        PerpetualYieldToken pyt,
        NegativeYieldToken nyt,
        string memory name_,
        string memory symbol_,
        uint256 pounderRewardMultiplier_,
        uint256 minOutputMultiplier_,
        uint24 uniswapV3PoolFee_,
        uint32 uniswapV3TwapSecondsAgo_,
        uint160 sqrtPriceX96,
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
        pool.initialize(sqrtPriceX96);

        // update Uniswap pool observation
        pool.increaseObservationCardinalityNext(observationCardinalityNext);

        emit DeployXPYT(pyt, deployed);
    }
}
