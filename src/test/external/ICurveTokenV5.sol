// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {ICurveCryptoSwap2ETH} from "../../curve-v2/external/ICurveCryptoSwap2ETH.sol";

interface ICurveTokenV5 {
    function initialize(
        string calldata name,
        string calldata symbol,
        ICurveCryptoSwap2ETH pool
    ) external;
}
