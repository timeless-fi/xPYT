// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {WETH} from "solmate/tokens/WETH.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {Gate} from "timeless/Gate.sol";
import {Factory} from "timeless/Factory.sol";
import {IxPYT} from "timeless/external/IxPYT.sol";
import {YearnGate} from "timeless/gates/YearnGate.sol";
import {TestERC20} from "timeless/test/mocks/TestERC20.sol";
import {NegativeYieldToken} from "timeless/NegativeYieldToken.sol";
import {PerpetualYieldToken} from "timeless/PerpetualYieldToken.sol";
import {TestYearnVault} from "timeless/test/mocks/TestYearnVault.sol";

import {xPYT} from "../xPYT.sol";
import {CurveDeployer} from "./utils/CurveDeployer.sol";
import {CurveV2xPYT} from "../curve-v2/CurveV2xPYT.sol";
import {ICurveTokenV5} from "./external/ICurveTokenV5.sol";
import {ICurveFactory} from "../curve-v2/external/ICurveFactory.sol";
import {CurveV2xPYTFactory} from "../curve-v2/CurveV2xPYTFactory.sol";
import {ICurveCryptoSwap2ETH} from "../curve-v2/external/ICurveCryptoSwap2ETH.sol";

contract CurveV2xPYTTest is Test, CurveDeployer {
    uint8 internal constant PROTOCOL_FEE = 100;
    uint8 internal constant DECIMALS = 18;
    uint256 internal constant ONE = 10**DECIMALS;
    uint256 internal constant AMOUNT = 100 * ONE;
    uint256 internal constant POUNDER_REWARD_MULTIPLIER = ONE / 10;
    uint256 internal constant MIN_OUTPUT_MULTIPLIER = (9 * ONE) / 10;
    address internal constant SWEEP_RECIPIENT = address(0x1111);
    address internal constant PROTOCOL_FEE_RECIPIENT = address(0x69);
    address internal constant POUNDER_REWARD_RECIPIENT = address(0x4200);
    ERC4626 internal constant XPYT_NULL = ERC4626(address(0));

    WETH weth;
    Factory factory;
    Gate gate;
    TestERC20 underlying;
    address vault;
    NegativeYieldToken nyt;
    PerpetualYieldToken pyt;
    xPYT xpyt;
    CurveV2xPYTFactory xpytFactory;
    ICurveCryptoSwap2ETH curvePool;
    ICurveFactory curveFactory;

    function setUp() public {
        // deploy weth
        weth = new WETH();

        // deploy factory
        factory = new Factory(
            Factory.ProtocolFeeInfo({
                fee: uint8(PROTOCOL_FEE),
                recipient: PROTOCOL_FEE_RECIPIENT
            })
        );

        // deploy gate
        gate = new YearnGate(factory);

        // deploy underlying
        underlying = new TestERC20(DECIMALS);

        // deploy vault
        vault = address(new TestYearnVault(underlying));

        // deploy PYT & NYT
        (nyt, pyt) = factory.deployYieldTokenPair(gate, vault);

        // deploy curve factory
        curveFactory = deployCurveFactory(
            deployCurveCryptoSwap2ETH(weth),
            deployCurveTokenV5(),
            weth
        );
        vm.label(address(curveFactory), "CurveFactory");

        // deploy xPYT factory
        xpytFactory = new CurveV2xPYTFactory(curveFactory);

        // deploy xPYT
        (xpyt, curvePool) = xpytFactory.deployCurveV2xPYT(
            pyt,
            "CurveV2xPYT",
            "xPYT",
            POUNDER_REWARD_MULTIPLIER,
            MIN_OUTPUT_MULTIPLIER,
            CurveV2xPYTFactory.CurvePoolParams(
                "Curve LP",
                "CRV-LP",
                400000,
                145000000000000,
                26000000,
                45000000,
                2000000000000,
                230000000000000,
                146000000000000,
                0,
                600,
                ONE
            )
        );

        vm.label(address(curvePool), "CurveCryptoSwap2ETH");

        // mint underlying
        underlying.mint(address(this), 3 * AMOUNT);

        // mint xPYT & NYT
        underlying.approve(address(gate), type(uint256).max);
        gate.enterWithUnderlying(
            address(this),
            address(this),
            vault,
            IxPYT(address(xpyt)),
            2 * AMOUNT
        );

        // add liquidity
        nyt.approve(address(curvePool), type(uint256).max);
        xpyt.approve(address(curvePool), type(uint256).max);
        curvePool.add_liquidity([AMOUNT, AMOUNT], 0);

        // token balances:
        // underlying: AMOUNT
        // xPYT: AMOUNT
        // NYT: AMOUNT
    }

    function testBasic_pound() public {
        // mint yield to vault
        uint256 mintYieldAmount = AMOUNT / 100;
        underlying.mint(vault, mintYieldAmount);

        // pound
        (
            xPYT.PreviewPoundErrorCode errorCode,
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
        assertTrue(
            errorCode == xPYT.PreviewPoundErrorCode.OK,
            "pound unsuccessful"
        );
        assertEqDecimal(
            claimedYieldAmount,
            (mintYieldAmount * (1000 - PROTOCOL_FEE)) / 1000,
            DECIMALS,
            "claimedYieldAmount incorrect"
        );
        assertEqDecimal(
            claimedYieldAmount,
            expectedClaimedYieldAmount,
            DECIMALS,
            "expectedClaimedYieldAmount incorrect"
        );
        assertEqDecimal(
            pytCompounded,
            expectedPYTCompounded,
            DECIMALS,
            "pytCompounded incorrect"
        );
        assertEqDecimal(
            pounderReward,
            expectedPounderReward,
            DECIMALS,
            "pounderReward incorrect"
        );
        assertEqDecimal(
            pyt.balanceOf(address(xpyt)),
            xpyt.assetBalance(),
            DECIMALS,
            "xPYT's PYT balance incorrect after pound"
        );
    }

    function testBasic_sweep() public {
        // unwrap xPYT into PYT and send to the xPYT contract
        uint256 assets = xpyt.redeem(AMOUNT, address(this), address(this));
        pyt.transfer(address(xpyt), assets);

        // sweep
        uint256 expectedShares = xpyt.previewDeposit(assets);
        xpyt.sweep(SWEEP_RECIPIENT);

        // check shares balance
        assertEqDecimal(
            xpyt.balanceOf(SWEEP_RECIPIENT),
            expectedShares,
            DECIMALS,
            "shares minted incorrect"
        );
    }

    function testTriggerError_InvalidMultiplierValue() public {
        vm.expectRevert(
            abi.encodeWithSignature("Error_InvalidMultiplierValue()")
        );
        xpyt = new CurveV2xPYT(
            pyt,
            "xPYT",
            "xPYT",
            10 * ONE,
            10 * ONE
        );
    }
}
