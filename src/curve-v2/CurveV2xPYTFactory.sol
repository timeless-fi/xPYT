// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {PerpetualYieldToken} from "timeless/PerpetualYieldToken.sol";

import {xPYT} from "../xPYT.sol";
import {CurveV2xPYT} from "./CurveV2xPYT.sol";
import {ICurveFactory} from "./external/ICurveFactory.sol";
import {ICurveCryptoSwap2ETH} from "./external/ICurveCryptoSwap2ETH.sol";

/// @title CurveV2xPYTFactory
/// @author zefram.eth
/// @notice Factory for deploying CurveV2xPYT contracts
contract CurveV2xPYTFactory {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error CurveV2xPYTFactory__StringTooLong();
    error CurveV2xPYTFactory__PoolCreationFailed();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event DeployXPYT(
        PerpetualYieldToken indexed pyt,
        xPYT deployed,
        ICurveCryptoSwap2ETH pool
    );

    /// -----------------------------------------------------------------------
    /// Structs
    /// -----------------------------------------------------------------------

    struct CurvePoolParams {
        string name;
        string symbol;
        uint256 A;
        uint256 gamma;
        uint256 mid_fee;
        uint256 out_fee;
        uint256 allowed_extra_profit;
        uint256 fee_gamma;
        uint256 adjustment_step;
        uint256 admin_fee;
        uint256 ma_half_time;
        uint256 initial_price;
    }

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The official Curve factory contract for v2 crypto pools
    ICurveFactory public immutable curveFactory;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(ICurveFactory curveFactory_) {
        curveFactory = curveFactory_;
    }

    /// -----------------------------------------------------------------------
    /// Public functions
    /// -----------------------------------------------------------------------

    /// @notice Deploys a CurveV2xPYT contract and its corresponding Curve V2 pool.
    /// @param pyt The PYT to deploy the xPYT for
    /// @param name_ The name of the xPYT token
    /// @param symbol_ The symbol of the xPYT token
    /// @param pounderRewardMultiplier_ The proportion of the yield claimed in pound() to give to the caller as reward
    /// @param minOutputMultiplier_ The minimum acceptable ratio between the NYT output in pound() and the expected NYT output
    /// based on the TWAP
    /// @param curvePoolParams The parameters of the Curve pool to deploy
    /// @return deployed The deployed xPYT
    /// @return curvePool The deployed Curve pool
    function deployCurveV2xPYT(
        PerpetualYieldToken pyt,
        string calldata name_,
        string calldata symbol_,
        uint256 pounderRewardMultiplier_,
        uint256 minOutputMultiplier_,
        CurvePoolParams calldata curvePoolParams
    ) external returns (CurveV2xPYT deployed, ICurveCryptoSwap2ETH curvePool) {
        // deploy xPYT
        deployed = new CurveV2xPYT(
            pyt,
            name_,
            symbol_,
            pounderRewardMultiplier_,
            minOutputMultiplier_
        );

        // deploy curve pool
        address[2] memory coins;
        {
            coins[0] = address(
                pyt.gate().getNegativeYieldTokenForVault(pyt.vault())
            ); // NYT
            coins[1] = address(deployed); // xPYT
        }
        curvePool = _deployCurvePool(coins, curvePoolParams);

        // initialize xPYT
        deployed.initialize(curvePool);

        // emit deployment event
        emit DeployXPYT(pyt, deployed, curvePool);
    }

    /// @dev Calls the Curve factory and deploys a new Curve v2 crypto pool
    function _deployCurvePool(
        address[2] memory coins,
        CurvePoolParams calldata p
    ) internal returns (ICurveCryptoSwap2ETH) {
        // ensure the lengths of the name and symbol are within limits
        if (_getStringLength(p.name) > 32 || _getStringLength(p.symbol) > 10) {
            revert CurveV2xPYTFactory__StringTooLong();
        }

        // incrementally construct calldata to curveFactory.deploy_pool()
        // in order to get around the stack-too-deep error
        /**
            Equivalent to:

            return curveFactory.deploy_pool(
                p.name,
                p.symbol,
                coins,
                p.A,
                p.gamma,
                p.mid_fee,
                p.out_fee,
                p.allowed_extra_profit,
                p.fee_gamma,
                p.adjustment_step,
                p.admin_fee,
                p.ma_half_time,
                p.initial_price
            );
         */

        bytes memory cd = new bytes(576); // calldata to the curve factory
        address coin0 = coins[0];
        address coin1 = coins[1];
        uint256 num; // temporary variable for passing contents of p to Yul

        // append the pointers to p.name and p.symbol
        // append the coins array
        assembly {
            mstore(
                add(cd, 0x20),
                0x00000000000000000000000000000000000000000000000000000000000001c0
            )
            mstore(
                add(cd, 0x40),
                0x0000000000000000000000000000000000000000000000000000000000000200
            )
            mstore(add(cd, 0x60), coin0)
            mstore(add(cd, 0x80), coin1)
        }

        // append the numerical parameters
        num = p.A;
        assembly {
            mstore(add(cd, 0xa0), num)
        }
        num = p.gamma;
        assembly {
            mstore(add(cd, 0xc0), num)
        }
        num = p.mid_fee;
        assembly {
            mstore(add(cd, 0xe0), num)
        }
        num = p.out_fee;
        assembly {
            mstore(add(cd, 0x100), num)
        }
        num = p.allowed_extra_profit;
        assembly {
            mstore(add(cd, 0x120), num)
        }
        num = p.fee_gamma;
        assembly {
            mstore(add(cd, 0x140), num)
        }
        num = p.adjustment_step;
        assembly {
            mstore(add(cd, 0x160), num)
        }
        num = p.admin_fee;
        assembly {
            mstore(add(cd, 0x180), num)
        }
        num = p.ma_half_time;
        assembly {
            mstore(add(cd, 0x1a0), num)
        }
        num = p.initial_price;

        assembly {
            mstore(add(cd, 0x1c0), num)

            // append the contents of p.name and p.symbol
            let pos := add(calldataload(p), p) // the position of p.name in calldata
            let tmp := calldataload(pos) // load p.name.length
            mstore(add(cd, 0x1e0), tmp)
            tmp := calldataload(add(pos, 0x20)) // load p.name
            mstore(add(cd, 0x200), tmp)
            tmp := calldataload(add(pos, 0x40)) // load p.symbol
            mstore(add(cd, 0x220), tmp)
            tmp := calldataload(add(pos, 0x60)) // load p.symbol.length
            mstore(add(cd, 0x240), tmp)
        }

        // prepend the function selector
        cd = bytes.concat(ICurveFactory.deploy_pool.selector, cd);

        // make the call to the curve factory
        (bool success, bytes memory result) = address(curveFactory).call(cd);
        if (!success) {
            revert CurveV2xPYTFactory__PoolCreationFailed();
        }

        // return the deployed pool
        return abi.decode(result, (ICurveCryptoSwap2ETH));
    }

    /// -----------------------------------------------------------------------
    /// Internal utilities
    /// -----------------------------------------------------------------------

    function _getStringLength(string calldata str)
        internal
        pure
        returns (uint256 len)
    {
        assembly {
            len := str.length
        }
    }
}
