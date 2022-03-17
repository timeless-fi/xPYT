// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {Gate} from "timeless/Gate.sol";
import {Factory} from "timeless/Factory.sol";
import {YearnGate} from "timeless/gates/YearnGate.sol";
import {TestERC20} from "timeless/test/mocks/TestERC20.sol";
import {NegativeYieldToken} from "timeless/NegativeYieldToken.sol";
import {PerpetualYieldToken} from "timeless/PerpetualYieldToken.sol";
import {TestYearnVault} from "timeless/test/mocks/TestYearnVault.sol";

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3MintCallback} from "v3-core/interfaces/callback/IUniswapV3MintCallback.sol";

import {IQuoter} from "v3-periphery/interfaces/IQuoter.sol";

import {xPYT} from "../xPYT.sol";
import {BaseTest, console} from "./base/BaseTest.sol";
import {TickMath} from "../uniswap-v3/lib/TickMath.sol";
import {LiquidityAmounts} from "./lib/LiquidityAmounts.sol";
import {UniswapDeployer} from "./utils/UniswapDeployer.sol";
import {UniswapV3xPYT} from "../uniswap-v3/UniswapV3xPYT.sol";
import {PoolAddress} from "../uniswap-v3/lib/PoolAddress.sol";

contract UniswapV3xPYTTest is
    BaseTest,
    UniswapDeployer,
    IUniswapV3MintCallback
{
    error Error_NotUniswapV3Pool();

    uint24 constant UNI_FEE = 500;
    uint8 internal constant PROTOCOL_FEE = 100;
    uint8 internal constant DECIMALS = 18;
    uint256 internal constant ONE = 10**DECIMALS;
    uint256 internal constant AMOUNT = 100 * ONE;
    uint32 internal constant TWAP_SECONDS_AGO = 1 days;
    uint256 internal constant POUNDER_REWARD_MULTIPLIER = ONE / 10;
    uint256 internal constant MIN_OUTPUT_MULTIPLIER = (9 * ONE) / 10;
    address internal constant PROTOCOL_FEE_RECIPIENT = address(0x69);
    address internal constant POUNDER_REWARD_RECIPIENT = address(0x4200);
    ERC4626 internal constant XPYT_NULL = ERC4626(address(0));

    Factory factory;
    Gate gate;
    TestERC20 underlying;
    address vault;
    NegativeYieldToken nyt;
    PerpetualYieldToken pyt;
    xPYT internal xpyt;
    IUniswapV3Factory uniswapV3Factory;
    IQuoter uniswapV3Quoter;
    IUniswapV3Pool uniswapV3Pool;

    function setUp() public {
        // deploy factory
        factory = new Factory(
            address(this),
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

        // deploy uniswap v3 factory
        uniswapV3Factory = IUniswapV3Factory(deployUniswapV3Factory());

        // deploy uniswap v3 quoter
        uniswapV3Quoter = IQuoter(
            deployUniswapV3Quoter(address(uniswapV3Factory), address(0))
        );

        // deploy xPYT
        xpyt = new UniswapV3xPYT(
            ERC20(address(pyt)),
            "xPYT",
            "xPYT",
            POUNDER_REWARD_MULTIPLIER,
            MIN_OUTPUT_MULTIPLIER,
            address(uniswapV3Factory),
            uniswapV3Quoter,
            UNI_FEE,
            TWAP_SECONDS_AGO
        );

        // deploy uniswap v3 pair
        uniswapV3Pool = IUniswapV3Pool(
            uniswapV3Factory.createPool(address(nyt), address(xpyt), UNI_FEE)
        );
        uniswapV3Pool.initialize(TickMath.getSqrtRatioAtTick(0));

        // mint underlying
        underlying.mint(address(this), 3 * AMOUNT);

        // mint xPYT & NYT
        underlying.approve(address(gate), type(uint256).max);
        gate.enterWithUnderlying(
            address(this),
            address(this),
            vault,
            xpyt,
            2 * AMOUNT
        );

        // add liquidity
        (address token0, address token1) = address(nyt) < address(xpyt)
            ? (address(nyt), address(xpyt))
            : (address(xpyt), address(nyt));
        _addLiquidity(
            AddLiquidityParams({
                token0: token0,
                token1: token1,
                fee: UNI_FEE,
                recipient: address(this),
                tickLower: -10000,
                tickUpper: 10000,
                amount0Desired: AMOUNT,
                amount1Desired: AMOUNT,
                amount0Min: 0,
                amount1Min: 0
            })
        );

        // token balances:
        // underlying: AMOUNT
        // xPYT: AMOUNT
        // NYT: AMOUNT
    }

    function test_basicPound() public {
        // wait for valid TWAP result
        vm.warp(TWAP_SECONDS_AGO);

        // mint yield to vault
        uint256 mintYieldAmount = AMOUNT / 100;
        underlying.mint(address(vault), mintYieldAmount);

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
    }

    function test_triggerError_InvalidMultiplierValue() public {
        vm.expectRevert(
            abi.encodeWithSignature("Error_InvalidMultiplierValue()")
        );
        xpyt = new UniswapV3xPYT(
            ERC20(address(pyt)),
            "xPYT",
            "xPYT",
            10 * ONE,
            10 * ONE,
            address(uniswapV3Factory),
            uniswapV3Quoter,
            UNI_FEE,
            TWAP_SECONDS_AGO
        );
    }

    function test_triggerError_ConsultTwapOracleFailed() public {
        // mint yield to vault
        uint256 mintYieldAmount = AMOUNT / 100;
        underlying.mint(address(vault), mintYieldAmount);

        // preview pound
        (xPYT.PreviewPoundErrorCode errorCode, , , ) = xpyt.previewPound();
        assertTrue(
            errorCode == xPYT.PreviewPoundErrorCode.TWAP_FAIL,
            "previewPound didn't return TWAP_FAIL"
        );

        // try pound and expect revert
        vm.expectRevert(
            abi.encodeWithSignature("Error_ConsultTwapOracleFailed()")
        );
        xpyt.pound(POUNDER_REWARD_RECIPIENT);
    }

    /// -----------------------------------------------------------------------
    /// Uniswap V3 add liquidity support
    /// -----------------------------------------------------------------------

    struct MintCallbackData {
        PoolAddress.PoolKey poolKey;
        address payer;
    }

    /// @inheritdoc IUniswapV3MintCallback
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        address pool = PoolAddress.computeAddress(
            address(uniswapV3Factory),
            decoded.poolKey
        );
        if (msg.sender != address(pool)) {
            revert Error_NotUniswapV3Pool();
        }

        if (amount0Owed > 0)
            _pay(
                ERC20(decoded.poolKey.token0),
                decoded.payer,
                msg.sender,
                amount0Owed
            );
        if (amount1Owed > 0)
            _pay(
                ERC20(decoded.poolKey.token1),
                decoded.payer,
                msg.sender,
                amount1Owed
            );
    }

    struct AddLiquidityParams {
        address token0;
        address token1;
        uint24 fee;
        address recipient;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    /// @notice Add liquidity to an initialized pool
    function _addLiquidity(AddLiquidityParams memory params)
        internal
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1,
            IUniswapV3Pool pool
        )
    {
        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({
            token0: params.token0,
            token1: params.token1,
            fee: params.fee
        });

        pool = IUniswapV3Pool(
            PoolAddress.computeAddress(address(uniswapV3Factory), poolKey)
        );

        // compute the liquidity amount
        {
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(
                params.tickLower
            );
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(
                params.tickUpper
            );

            liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                params.amount0Desired,
                params.amount1Desired
            );
        }

        (amount0, amount1) = pool.mint(
            params.recipient,
            params.tickLower,
            params.tickUpper,
            liquidity,
            abi.encode(
                MintCallbackData({poolKey: poolKey, payer: address(this)})
            )
        );

        require(
            amount0 >= params.amount0Min && amount1 >= params.amount1Min,
            "Price slippage check"
        );
    }

    /// @dev Pays tokens to the recipient using the payer's balance
    /// @param token The token to pay
    /// @param payer The address that will pay the tokens
    /// @param recipient_ The address that will receive the tokens
    /// @param value The amount of tokens to pay
    function _pay(
        ERC20 token,
        address payer,
        address recipient_,
        uint256 value
    ) internal {
        if (payer == address(this)) {
            // pay with tokens already in the contract
            token.transfer(recipient_, value);
        } else {
            // pull payment
            token.transferFrom(payer, recipient_, value);
        }
    }
}
