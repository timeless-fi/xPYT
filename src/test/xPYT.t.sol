// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {Gate} from "timeless/Gate.sol";
import {Factory} from "timeless/Factory.sol";
import {YearnGate} from "timeless/gates/YearnGate.sol";
import {TestERC20} from "timeless/test/mocks/TestERC20.sol";
import {TestYearnVault} from "timeless/test/mocks/TestYearnVault.sol";

import {TLPool} from "timeless-amm/TLPool.sol";
import {TLFactory} from "timeless-amm/TLFactory.sol";

import {BaseTest, console} from "./base/BaseTest.sol";

import {xPYT} from "../xPYT.sol";

contract xPYTTest is BaseTest {
    uint8 internal constant PROTOCOL_FEE = 100;
    uint8 internal constant UNDERLYING_DECIMALS = 18;
    uint16 internal constant TWAP_LOOKBACK_DISTANCE = 0;
    uint64 internal constant ORACLE_UPDATE_INTERVAL = 1 days;
    uint256 internal constant BONE = 10**18;
    uint256 internal constant INITIAL_WEIGHT = BONE * 10**18;
    uint256 internal constant AMOUNT = 100 * BONE;
    uint256 internal constant SWAP_FEE = BONE / 1000;
    uint256 internal constant POUNDER_REWARD_MULTIPLIER = BONE / 10;
    uint256 internal constant TWAP_MIN_LOOKBACK_TIME = 12 hours;
    uint256 internal constant MIN_OUTPUT_MULTIPLIER = (9 * BONE) / 10;
    address internal constant PROTOCOL_FEE_RECIPIENT = address(0x69);
    address internal constant POUNDER_REWARD_RECIPIENT = address(0x4200);
    ERC4626 internal constant XPYT_NULL = ERC4626(address(0));

    xPYT internal xpyt;
    TLFactory internal factory;
    TLPool internal pool;
    Gate internal gate;
    TestYearnVault internal vault;
    TestERC20 internal underlying;
    Factory internal yieldTokenFactory;

    function setUp() public {
        // deploy Factory & Gate
        yieldTokenFactory = new Factory(
            address(this),
            Factory.ProtocolFeeInfo({
                fee: PROTOCOL_FEE,
                recipient: PROTOCOL_FEE_RECIPIENT
            })
        );
        gate = Gate(address(new YearnGate(yieldTokenFactory)));

        // deploy TLFactory
        TLPool implementation = new TLPool();
        factory = new TLFactory(
            implementation,
            address(this),
            TLFactory.ProtocolFeeInfo({
                fee: PROTOCOL_FEE,
                recipient: PROTOCOL_FEE_RECIPIENT
            })
        );

        // deploy underlying
        underlying = new TestERC20(UNDERLYING_DECIMALS);

        // deploy vault
        vault = new TestYearnVault(underlying);

        // mint underlying
        underlying.mint(address(this), 4 * AMOUNT);

        // mint PYT & NYT using underlying
        underlying.approve(address(gate), type(uint256).max);
        gate.enterWithUnderlying(
            address(this),
            address(vault),
            XPYT_NULL,
            2 * AMOUNT
        );

        // deploy TLPool
        underlying.approve(address(factory), type(uint256).max);
        gate.getNegativeYieldTokenForVault(address(vault)).approve(
            address(factory),
            type(uint256).max
        );
        gate.getPerpetualYieldTokenForVault(address(vault)).approve(
            address(factory),
            type(uint256).max
        );
        // NYT price is 0.4, PYT price is 0.6
        pool = factory.newTLPool(
            gate,
            address(vault),
            SWAP_FEE,
            ORACLE_UPDATE_INTERVAL,
            [AMOUNT, AMOUNT, AMOUNT],
            [
                INITIAL_WEIGHT,
                (INITIAL_WEIGHT * 4) / 10,
                (INITIAL_WEIGHT * 6) / 10
            ]
        );

        // deploy xPYT
        ERC20 pyt = ERC20(
            address(gate.getPerpetualYieldTokenForVault(address(vault)))
        );
        xpyt = new xPYT(
            pyt,
            "xPYT",
            "xPYT",
            pool,
            POUNDER_REWARD_MULTIPLIER,
            TWAP_LOOKBACK_DISTANCE,
            TWAP_MIN_LOOKBACK_TIME,
            MIN_OUTPUT_MULTIPLIER
        );

        // deposit into xPYT
        pyt.approve(address(xpyt), type(uint256).max);
        xpyt.deposit(AMOUNT, address(this));
    }

    function test_basicPound() public {
        // wait to update TWAP oracle
        vm.warp(ORACLE_UPDATE_INTERVAL);

        // do swap with pool to update TWAP
        uint256 swapAmount = AMOUNT / 10;
        ERC20 pyt = ERC20(
            address(gate.getPerpetualYieldTokenForVault(address(vault)))
        );
        underlying.transfer(address(pool), swapAmount);
        pool.swapExactAmountIn(underlying, swapAmount, pyt, 0, address(this));

        // wait for the minimum lookback time
        vm.warp(ORACLE_UPDATE_INTERVAL + TWAP_MIN_LOOKBACK_TIME);

        // mint yield to vault
        uint256 mintYieldAmount = AMOUNT / 100;
        underlying.mint(address(vault), mintYieldAmount);
        gate.getClaimableYieldAmount(address(vault), address(xpyt));

        // pound
        (
            bool success,
            uint256 expectedClaimedYieldAmount,
            uint256 expectedPYTCompounded,
            uint256 expectedPounderReward
        ) = xpyt.previewPound();
        (
            uint256 claimedYieldAmount,
            uint256 pytCompounded,
            uint256 pounderReward
        ) = xpyt.pound(POUNDER_REWARD_RECIPIENT);

        // check pound results
        assertTrue(success, "pound unsuccessful");
        assertEqDecimal(
            claimedYieldAmount,
            ((mintYieldAmount / 2) * (1000 - PROTOCOL_FEE)) / 1000,
            UNDERLYING_DECIMALS,
            "claimedYieldAmount incorrect"
        );
        assertEqDecimal(
            claimedYieldAmount,
            expectedClaimedYieldAmount,
            UNDERLYING_DECIMALS,
            "expectedClaimedYieldAmount incorrect"
        );
        assertEqDecimal(
            pytCompounded,
            expectedPYTCompounded,
            UNDERLYING_DECIMALS,
            "pytCompounded incorrect"
        );
        assertEqDecimal(
            pounderReward,
            expectedPounderReward,
            UNDERLYING_DECIMALS,
            "pounderReward incorrect"
        );
    }
}
