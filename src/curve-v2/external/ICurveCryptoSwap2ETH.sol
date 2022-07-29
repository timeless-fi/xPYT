// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface ICurveCryptoSwap2ETH {
    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy,
        bool use_eth,
        address receiver
    ) external returns (uint256);

    function get_dy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256);

    function initialize(
        uint256 A,
        uint256 gamma,
        uint256 mid_fee,
        uint256 out_fee,
        uint256 allowed_extra_profit,
        uint256 fee_gamma,
        uint256 adjustment_step,
        uint256 admin_fee,
        uint256 ma_half_time,
        uint256 initial_price,
        address _token,
        address[2] calldata _coins,
        uint256 _precisions
    ) external;

    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount)
        external
        returns (uint256);

    function price_oracle() external view returns (uint256);
}
