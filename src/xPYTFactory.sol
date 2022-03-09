// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {TLPool} from "timeless-amm/TLPool.sol";

import {xPYT} from "./xPYT.sol";

/// @title xPYTFactory
/// @author zefram.eth
/// @notice Factory for deploying xPYT contracts
contract xPYTFactory {
    event DeployXPYT(ERC20 indexed asset_, xPYT deployed);

    function deployXPYT(
        ERC20 asset_,
        string memory name_,
        string memory symbol_,
        TLPool ammPool_,
        uint256 pounderRewardMultiplier_,
        uint16 twapLookbackDistance_,
        uint256 twapMinLookbackTime_,
        uint256 minOutputMultiplier_
    ) external returns (xPYT deployed) {
        deployed = new xPYT(
            asset_,
            name_,
            symbol_,
            ammPool_,
            pounderRewardMultiplier_,
            twapLookbackDistance_,
            twapMinLookbackTime_,
            minOutputMultiplier_
        );

        emit DeployXPYT(asset_, deployed);
    }
}
