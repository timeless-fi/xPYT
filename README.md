# xPYT

xPYT is a permissionless vault framework for auto-compounding the yield earned by Timeless perpetual yield tokens (PYT) into more PYT. It is introduced for two reasons:

1. Makes it easier to build yield-leveraging strategies.
2. xPYT has better composability with other protocols that don't expect to claim the yield earned by PYT. (e.g. Rari Fuse, Uniswap, cross-chain bridges) If raw PYT is used instead of xPYT in contracts without Timeless support, the yield accrued to the contract will be lost, so xPYT should be used instead.

xPYT has the following features:

-   **Permissionless deployment**: Anyone can use the `xPYTFactory` contract to deploy xPYT vaults.
-   **Permissionless auto-compounding**: Rather than relying on centralized strategists/harvesters to perform the auto-compounding, xPYT makes the auto-compounding executable by anyone, and the caller would receive a portion of the claimed yield as reward. This means xPYT vaults can rely on MEV bots to perform the auto-compounding, rather than having to build out centralized infrastructure.
-   **Minimal sandwiching losses**: xPYT uses a TWAP oracle to make sure that when it auto-compounds yield into PYT the price it gets doesn't deviate too much from the TWAP, minimizing losses from sandwiching attacks.

## Architecture

-   [`xPYT.sol`](src/xPYT.sol): Permissionless auto-compounding vault for Timeless perpetual yield tokens
-   [`uniswap-v3/`](src/uniswap-v3/): Uniswap V3 support
    -   [`UniswapV3xPYT.sol`](src/uniswap-v3/UniswapV3xPYT.sol): xPYT implementation using Uniswap V3 to swap NYT into PYT
    -   [`UniswapV3xPYTFactory.sol`](src/uniswap-v3/UniswapV3xPYTFactory.sol): Factory for deploying UniswapV3xPYT contracts
    -   [`lib/`](src/uniswap-v3/lib/): Libraries used
        -   [`PoolAddress.sol`](src/uniswap-v3/lib/PoolAddress.sol): Provides functions for deriving a Uniswap V3 pool address from the factory, tokens, and the fee
        -   [`OracleLibrary.sol`](src/uniswap-v3/lib/OracleLibrary.sol): Provides functions to integrate with V3 pool oracle
        -   [`TickMath.sol`](src/uniswap-v3/lib/TickMath.sol): Math library for computing sqrt prices from ticks and vice versa
-   [`curve-v2/`](src/curve-v2/): Curve v2 support
    -   [`CurveV2xPYT.sol`](src/curve-v2/CurveV2xPYT.sol): xPYT implementation using Curve V2 to swap NYT into PYT
    -   [`CurveV2xPYTFactory.sol`](src/curve-v2/CurveV2xPYTFactory.sol): Factory for deploying CurveV2xPYT contracts

## Installation

To install with [DappTools](https://github.com/dapphub/dapptools):

```
dapp install timeless-fi/xPYT
```

To install with [Foundry](https://github.com/gakonst/foundry):

```
forge install timeless-fi/xPYT
```

## Local development

This project uses [Foundry](https://github.com/gakonst/foundry) as the development framework.

### Dependencies

```
make install
```

### Compilation

```
make build
```

### Testing

```
make test
```
