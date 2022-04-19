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

/// @title xPYT
/// @author zefram.eth
/// @notice Permissionless auto-compounding vault for Timeless perpetual yield tokens
abstract contract xPYT is ERC4626, ReentrancyGuard {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error Error_InsufficientOutput();
    error Error_InvalidMultiplierValue();
    error Error_ConsultTwapOracleFailed();

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
    /// Enums
    /// -----------------------------------------------------------------------

    enum PreviewPoundErrorCode {
        OK,
        TWAP_FAIL,
        INSUFFICIENT_OUTPUT
    }

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    /// @notice The base unit for fixed point decimals.
    uint256 internal constant ONE = 10**18;

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    /// @notice The Gate associated with the PYT.
    Gate public immutable gate;

    /// @notice The vault associated with the PYT.
    address public immutable vault;

    /// @notice The NYT associated with the PYT.
    NegativeYieldToken public immutable nyt;

    /// @notice The minimum acceptable ratio between the NYT output in pound() and the expected NYT output
    /// based on the TWAP. Scaled by ONE.
    uint256 public immutable minOutputMultiplier;

    /// @notice The proportion of the yield claimed in pound() to give to the caller as reward. Scaled by ONE.
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
        uint256 pounderRewardMultiplier_,
        uint256 minOutputMultiplier_
    ) ERC4626(asset_, name_, symbol_) {
        if (minOutputMultiplier_ > ONE) {
            revert Error_InvalidMultiplierValue();
        }
        minOutputMultiplier = minOutputMultiplier_;
        pounderRewardMultiplier = pounderRewardMultiplier_;
        if (pounderRewardMultiplier_ > ONE) {
            revert Error_InvalidMultiplierValue();
        }
        Gate gate_ = PerpetualYieldToken(address(asset_)).gate();
        gate = gate_;
        address vault_ = PerpetualYieldToken(address(asset_)).vault();
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
    /// @return yieldAmount The amount of PYT & NYT claimed as yield
    /// @return pytCompounded The amount of PYT distributed to xPYT holders
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
            address(this),
            vault,
            ERC4626(address(0))
        );

        // compute minXpytAmountOut based on the TWAP & minOutputMultiplier
        (bool success, uint256 twapQuoteAmountOut) = _getTwapQuote(yieldAmount);
        if (!success) {
            revert Error_ConsultTwapOracleFailed();
        }
        uint256 minXpytAmountOut = FullMath.mulDiv(
            twapQuoteAmountOut,
            minOutputMultiplier,
            ONE
        );

        // swap NYT into xPYT
        uint256 xPytAmountOut = _swap(yieldAmount);
        if (xPytAmountOut < minXpytAmountOut) {
            revert Error_InsufficientOutput();
        }

        // burn the xPYT
        uint256 pytAmountRedeemed = convertToAssets(xPytAmountOut);
        _burn(address(this), xPytAmountOut);

        // record PYT balance increase
        unchecked {
            // token balance cannot exceed 256 bits since totalSupply is an uint256
            pytCompounded = yieldAmount + pytAmountRedeemed;
            pounderReward = FullMath.mulDiv(
                pytCompounded,
                pounderRewardMultiplier,
                ONE
            );
            pytCompounded -= pounderReward;
            // don't add pytAmountRedeemed to assetBalance since it's already in the vault,
            // we just burnt the corresponding xPYT
            assetBalance += yieldAmount;
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
    /// @return errorCode The end state of pound()
    /// @return yieldAmount The amount of PYT & NYT claimed as yield
    /// @return pytCompounded The amount of PYT distributed to xPYT holders
    /// @return pounderReward The amount of caller reward given, in PYT
    function previewPound()
        external
        returns (
            PreviewPoundErrorCode errorCode,
            uint256 yieldAmount,
            uint256 pytCompounded,
            uint256 pounderReward
        )
    {
        // get claimable yield amount from gate
        yieldAmount = gate.getClaimableYieldAmount(vault, address(this));

        // compute minXpytAmountOut based on the TWAP & minOutputMultiplier
        (bool twapSuccess, uint256 twapQuoteAmountOut) = _getTwapQuote(
            yieldAmount
        );
        if (!twapSuccess) {
            return (PreviewPoundErrorCode.TWAP_FAIL, 0, 0, 0);
        }
        uint256 minXpytAmountOut = FullMath.mulDiv(
            twapQuoteAmountOut,
            minOutputMultiplier,
            ONE
        );

        // simulate swapping NYT into PYT
        uint256 xPytAmountOut = _quote(yieldAmount);
        if (xPytAmountOut < minXpytAmountOut) {
            return (PreviewPoundErrorCode.INSUFFICIENT_OUTPUT, 0, 0, 0);
        }

        // burn the xPYT
        uint256 pytAmountRedeemed = convertToAssets(xPytAmountOut);

        // compute compounded PYT amount and pounder reward amount
        unchecked {
            // token balance cannot exceed 256 bits since totalSupply is an uint256
            pytCompounded = yieldAmount + pytAmountRedeemed;
            pounderReward = FullMath.mulDiv(
                pytCompounded,
                pounderRewardMultiplier,
                ONE
            );
            // don't add pytAmountRedeemed to assetBalance since it's already in the vault,
            // we just burnt the corresponding xPYT
            pytCompounded -= pounderReward;
        }

        // if execution has reached this point, the simulation was successful
        errorCode = PreviewPoundErrorCode.OK;
    }

    /// -----------------------------------------------------------------------
    /// Sweeping
    /// -----------------------------------------------------------------------

    /// @notice Uses the extra asset balance of the xPYT contract to mint shares
    /// @param receiver The recipient of the minted shares
    /// @return shares The amount of shares minted
    function sweep(address receiver) external virtual returns (uint256 shares) {
        uint256 assets = asset.balanceOf(address(this)) - assetBalance;

        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
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

    /// -----------------------------------------------------------------------
    /// Internal utilities
    /// -----------------------------------------------------------------------

    /// @dev Consults the TWAP oracle to get a quote for how much xPYT will be received from swapping
    /// `nytAmountIn` NYT.
    /// @param nytAmountIn The amount of NYT to swap
    /// @return success True if the call to the TWAP oracle was successful, false otherwise
    /// @return xPytAmountOut The amount of xPYT that will be received from the swap
    function _getTwapQuote(uint256 nytAmountIn)
        internal
        view
        virtual
        returns (bool success, uint256 xPytAmountOut);

    /// @dev Swaps `nytAmountIn` NYT into xPYT using the underlying DEX
    /// @param nytAmountIn The amount of NYT to swap
    /// @return xPytAmountOut The amount of xPYT received from the swap
    function _swap(uint256 nytAmountIn)
        internal
        virtual
        returns (uint256 xPytAmountOut);

    /// @dev Gets a quote from the underlying DEX for swapping `nytAmountIn` NYT into xPYT
    /// @param nytAmountIn The amount of NYT to swap
    /// @return xPytAmountOut The amount of xPYT that will be received from the swap
    function _quote(uint256 nytAmountIn)
        internal
        virtual
        returns (uint256 xPytAmountOut);
}
