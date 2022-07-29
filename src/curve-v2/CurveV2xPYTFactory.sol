// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {console2} from "forge-std/console2.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

import {PerpetualYieldToken} from "timeless/PerpetualYieldToken.sol";

import {IQuoter} from "v3-periphery/interfaces/IQuoter.sol";

import {xPYT} from "../xPYT.sol";
import {CurveV2xPYT} from "./CurveV2xPYT.sol";
import {ICurveFactory} from "./external/ICurveFactory.sol";
import {ICurveCryptoSwap2ETH} from "./external/ICurveCryptoSwap2ETH.sol";

/// @title CurveV2xPYTFactory
/// @author zefram.eth
/// @notice Factory for deploying CurveV2xPYT contracts
contract CurveV2xPYTFactory {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using Bytes32AddressLib for bytes32;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event DeployXPYT(ERC20 indexed asset_, xPYT deployed);

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

    ICurveFactory public immutable curveFactory;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice The nonce of this account. Used for predicting deployment addresses.
    uint256 public nonce;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(ICurveFactory curveFactory_) {
        curveFactory = curveFactory_;
    }

    /// -----------------------------------------------------------------------
    /// Public functions
    /// -----------------------------------------------------------------------

    function deployCurveV2xPYT(
        PerpetualYieldToken pyt,
        string calldata name_,
        string calldata symbol_,
        uint256 pounderRewardMultiplier_,
        uint256 minOutputMultiplier_,
        CurvePoolParams calldata curvePoolParams
    ) external returns (CurveV2xPYT deployed, ICurveCryptoSwap2ETH curvePool) {
        // load nonce from storage to save gas
        uint256 nonce_ = nonce;

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

        // update nonce
        unchecked {
            nonce = nonce_ + 1;
        }

        // emit deployment event
        emit DeployXPYT(pyt, deployed);
    }

    function predictDeployment(uint256 nonce_) public view returns (address) {
        return
            keccak256(
                abi.encodePacked(
                    // Prefix (0xc0 + 54):
                    bytes1(0xF6),
                    // Creator length (0x80 + 20):
                    bytes1(0x94),
                    // Creator:
                    address(this),
                    // Nonce length (0x80 + 32):
                    bytes1(0xA0),
                    // Nonce:
                    nonce_
                )
            ).fromLast20Bytes(); // Convert the CREATE hash into an address.
    }

    function _deployCurvePool(
        address[2] memory coins,
        CurvePoolParams calldata p
    ) internal returns (ICurveCryptoSwap2ETH) {
        bytes memory cd = new bytes(576);
        address coin0 = coins[0];
        address coin1 = coins[1];
        uint256 num;
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
            let pos := add(calldataload(p), p)
            let tmp := calldataload(pos)
            mstore(add(cd, 0x1e0), tmp)
            tmp := calldataload(add(pos, 0x20))
            mstore(add(cd, 0x200), tmp)
            tmp := calldataload(add(pos, 0x40))
            mstore(add(cd, 0x220), tmp)
            tmp := calldataload(add(pos, 0x60))
            mstore(add(cd, 0x240), tmp)
        }
        cd = bytes.concat(ICurveFactory.deploy_pool.selector, cd);
        (bool success, bytes memory result) = address(curveFactory).call(cd);
        require(success);
        return abi.decode(result, (ICurveCryptoSwap2ETH));
        /*return
            curveFactory.deploy_pool(
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
            );*/
    }
}
