// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IQuoter} from "v3-periphery/interfaces/IQuoter.sol";

import {xPYT} from "./xPYT.sol";
import {UniswapV3xPYT} from "./uniswap-v3/UniswapV3xPYT.sol";

/// @title xPYTFactory
/// @author zefram.eth
/// @notice Factory for deploying xPYT contracts
contract xPYTFactory {
    event DeployXPYT(ERC20 indexed asset_, xPYT deployed);

    function deployUniswapV3xPYT(
        ERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint256 pounderRewardMultiplier_,
        uint256 minOutputMultiplier_,
        address uniswapV3Factory_,
        IQuoter uniswapV3Quoter_,
        uint24 uniswapV3PoolFee_,
        uint32 uniswapV3TwapSecondsAgo_
    ) external returns (xPYT deployed) {
        deployed = new UniswapV3xPYT(
            asset_,
            name_,
            symbol_,
            pounderRewardMultiplier_,
            minOutputMultiplier_,
            uniswapV3Factory_,
            uniswapV3Quoter_,
            uniswapV3PoolFee_,
            uniswapV3TwapSecondsAgo_
        );

        emit DeployXPYT(asset_, deployed);
    }
}
