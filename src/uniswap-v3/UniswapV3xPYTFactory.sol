// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {PerpetualYieldToken} from "timeless/PerpetualYieldToken.sol";

import {IQuoter} from "v3-periphery/interfaces/IQuoter.sol";

import {xPYT} from "../xPYT.sol";
import {UniswapV3xPYT} from "./UniswapV3xPYT.sol";

/// @title UniswapV3xPYTFactory
/// @author zefram.eth
/// @notice Factory for deploying xPYT contracts
contract UniswapV3xPYTFactory {
    event DeployXPYT(PerpetualYieldToken indexed pyt, xPYT deployed);

    address public immutable uniswapV3Factory;
    IQuoter public immutable uniswapV3Quoter;

    constructor(address uniswapV3Factory_, IQuoter uniswapV3Quoter_) {
        uniswapV3Factory = uniswapV3Factory_;
        uniswapV3Quoter = uniswapV3Quoter_;
    }

    function deployUniswapV3xPYT(
        PerpetualYieldToken pyt,
        string memory name_,
        string memory symbol_,
        uint256 pounderRewardMultiplier_,
        uint256 minOutputMultiplier_,
        uint24 uniswapV3PoolFee_,
        uint32 uniswapV3TwapSecondsAgo_
    ) external returns (xPYT deployed) {
        deployed = new UniswapV3xPYT(
            pyt,
            name_,
            symbol_,
            pounderRewardMultiplier_,
            minOutputMultiplier_,
            uniswapV3Factory,
            uniswapV3Quoter,
            uniswapV3PoolFee_,
            uniswapV3TwapSecondsAgo_
        );

        emit DeployXPYT(pyt, deployed);
    }
}
