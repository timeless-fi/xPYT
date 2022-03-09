// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {Gate} from "timeless/Gate.sol";
import {FullMath} from "timeless/lib/FullMath.sol";
import {NegativeYieldToken} from "timeless/NegativeYieldToken.sol";
import {PerpetualYieldToken} from "timeless/PerpetualYieldToken.sol";

import {TLPool} from "timeless-amm/TLPool.sol";

/// @title xPYT
/// @author zefram.eth
/// @notice Permissionless auto-compounding vault for Timeless perpetual yield tokens
/// @dev Uses Timeless AMM to convert the NYT yield into PYT
contract xPYT is ERC4626, ReentrancyGuard {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error Error_TWAPResultInvalid();
    error Error_InvalidMultiplierValue();
    error Error_TWAPTimeElapsedInsufficient();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event Pound(
        address indexed sender,
        address indexed pounderRewardRecipient,
        uint256 yieldAmount,
        uint256 pytCompounded,
        uint256 pounderReward
    );

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    /// @notice The base unit for fixed point decimals.
    uint256 internal constant BONE = 10**18;

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    /// @notice The Gate associated with the PYT.
    Gate public immutable gate;

    /// @notice The vault associated with the PYT.
    address public immutable vault;

    /// @notice The TLPool contract used for selling NYT into PYT.
    TLPool public immutable ammPool;

    /// @notice The NYT associated with the PYT.
    NegativeYieldToken public immutable nyt;

    /// @notice The lookbackDistance value input to TLPool::quote().
    uint16 public immutable twapLookbackDistance;

    /// @notice The minimum acceptable timeElapsed value output by TLPool::quote().
    uint256 public immutable twapMinLookbackTime;

    /// @notice The minimum acceptable ratio between the NYT output in pound() and the expected NYT output
    /// based on the TWAP. Scaled by BONE.
    uint256 public immutable minOutputMultiplier;

    /// @notice The proportion of the yield claimed in pound() to give to the caller as reward. Scaled by BONE.
    uint256 public immutable pounderRewardMultiplier;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice The recorded balance of the deposited asset.
    /// @dev This is used instead of asset.balanceOf(address(this)) to prevent attackers from
    /// atomically increasing the vault share value and thus exploiting integrated lending protocols.
    uint256 public assetBalance;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        ERC20 asset_,
        string memory name_,
        string memory symbol_,
        TLPool ammPool_,
        uint256 pounderRewardMultiplier_,
        uint16 twapLookbackDistance_,
        uint256 twapMinLookbackTime_,
        uint256 minOutputMultiplier_
    ) ERC4626(asset_, name_, symbol_) {
        ammPool = ammPool_;
        twapLookbackDistance = twapLookbackDistance_;
        twapMinLookbackTime = twapMinLookbackTime_;
        if (minOutputMultiplier_ > BONE) {
            revert Error_InvalidMultiplierValue();
        }
        minOutputMultiplier = minOutputMultiplier_;
        pounderRewardMultiplier = pounderRewardMultiplier_;
        if (pounderRewardMultiplier_ > BONE) {
            revert Error_InvalidMultiplierValue();
        }
        Gate gate_ = PerpetualYieldToken(address(asset)).gate();
        gate = gate_;
        address vault_ = PerpetualYieldToken(address(asset)).vault();
        vault = vault_;
        nyt = gate_.getNegativeYieldTokenForVault(vault_);
    }

    /// -----------------------------------------------------------------------
    /// Compounding
    /// -----------------------------------------------------------------------

    /// @notice Claims the yield earned by the PYT held and sells the claimed NYT into more PYT.
    /// @dev Part of the claimed yield is given to the caller as reward, which incentivizes MEV bots
    /// to perform the auto-compounding for us.
    /// @param pounderRewardRecipient The address that will receive the caller reward
    /// @return yieldAmount The amount of yield claimed, in terms of the PYT's underlying asset
    /// @return pytCompounded The amount of PYT added to totalAssets
    /// @return pounderReward The amount of caller reward given, in PYT
    function pound(address pounderRewardRecipient)
        external
        virtual
        nonReentrant
        returns (
            uint256 yieldAmount,
            uint256 pytCompounded,
            uint256 pounderReward
        )
    {
        // claim yield from gate
        yieldAmount = gate.claimYieldAndEnter(
            address(this),
            vault,
            ERC4626(address(0))
        );

        // query the TWAP oracle
        (
            bool valid,
            uint256 pytPriceInUnderlying,
            uint256 timeElapsed
        ) = ammPool.quote(twapLookbackDistance);
        if (!valid) {
            revert Error_TWAPResultInvalid();
        }
        if (timeElapsed <= twapMinLookbackTime) {
            revert Error_TWAPTimeElapsedInsufficient();
        }

        // compute minAmountOut based on the TWAP & minOutputMultiplier
        uint256 nytPriceInUnderlying;
        unchecked {
            // the price of PYT/NYT never exceeds 1
            nytPriceInUnderlying = BONE - pytPriceInUnderlying;
        }
        uint256 nytPriceInPYT = FullMath.mulDiv(
            nytPriceInUnderlying,
            BONE,
            pytPriceInUnderlying
        );
        uint256 minAmountOut = FullMath.mulDiv(
            FullMath.mulDiv(yieldAmount, nytPriceInPYT, BONE),
            minOutputMultiplier,
            BONE
        );

        // swap NYT into PYT
        (uint256 tokenAmountOut, ) = ammPool.swapExactAmountIn(
            ERC20(address(nyt)),
            yieldAmount,
            asset,
            minAmountOut,
            address(this)
        );

        // record PYT balance increase
        unchecked {
            // token balance cannot exceed 256 bits since totalSupply is an uint256
            pytCompounded = yieldAmount + tokenAmountOut;
            pounderReward = FullMath.mulDiv(
                pytCompounded,
                pounderRewardMultiplier,
                BONE
            );
            pytCompounded -= pounderReward;
            assetBalance += pytCompounded;
        }

        // transfer pounder reward
        asset.safeTransfer(pounderRewardRecipient, pounderReward);

        emit Pound(
            msg.sender,
            pounderRewardRecipient,
            yieldAmount,
            pytCompounded,
            pounderReward
        );
    }

    /// @notice Previews the result of calling pound()
    /// @return success True if pound() won't revert, false otherwise
    /// @return yieldAmount The amount of yield claimed, in terms of the PYT's underlying asset
    /// @return pytCompounded The amount of PYT added to totalAssets
    /// @return pounderReward The amount of caller reward given, in PYT
    function previewPound()
        external
        view
        returns (
            bool success,
            uint256 yieldAmount,
            uint256 pytCompounded,
            uint256 pounderReward
        )
    {
        // get claimable yield amount from gate
        yieldAmount = gate.getClaimableYieldAmount(vault, address(this));

        // query the TWAP oracle
        (
            bool valid,
            uint256 pytPriceInUnderlying,
            uint256 timeElapsed
        ) = ammPool.quote(twapLookbackDistance);
        if (!valid || timeElapsed <= twapMinLookbackTime) {
            return (false, 0, 0, 0);
        }

        // compute minAmountOut based on the TWAP & minOutputMultiplier
        uint256 minAmountOut;
        {
            uint256 nytPriceInUnderlying;
            unchecked {
                // the price of PYT/NYT never exceeds 1
                nytPriceInUnderlying = BONE - pytPriceInUnderlying;
            }
            uint256 nytPriceInPYT = FullMath.mulDiv(
                nytPriceInUnderlying,
                BONE,
                pytPriceInUnderlying
            );
            minAmountOut = FullMath.mulDiv(
                FullMath.mulDiv(yieldAmount, nytPriceInPYT, BONE),
                minOutputMultiplier,
                BONE
            );
        }

        // simulate swapping NYT into PYT and check slippage
        ERC20 nytERC20 = ERC20(address(nyt));
        uint256 tokenAmountOut = ammPool.calcOutGivenIn(
            ammPool.getBalance(nytERC20),
            ammPool.getDenormalizedWeight(nytERC20),
            ammPool.getBalance(asset),
            ammPool.getDenormalizedWeight(asset),
            yieldAmount,
            ammPool.swapFee()
        );
        if (tokenAmountOut < minAmountOut) {
            return (false, 0, 0, 0);
        }

        // compute compounded PYT amount and pounder reward amount
        unchecked {
            // token balance cannot exceed 256 bits since totalSupply is an uint256
            pytCompounded = yieldAmount + tokenAmountOut;
            pounderReward = FullMath.mulDiv(
                pytCompounded,
                pounderRewardMultiplier,
                BONE
            );
            pytCompounded -= pounderReward;
        }

        // if execution has reached this point, the simulation was successful
        success = true;
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    function totalAssets() public view virtual override returns (uint256) {
        return assetBalance;
    }

    function beforeWithdraw(
        uint256 assets,
        uint256 /*shares*/
    ) internal virtual override {
        unchecked {
            assetBalance -= assets;
        }
    }

    function afterDeposit(
        uint256 assets,
        uint256 /*shares*/
    ) internal virtual override {
        assetBalance += assets;
    }
}
