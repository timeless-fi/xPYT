# xPYT

xPYT is a permissionless vault framework for auto-compounding the yield earned by Timeless perpetual yield tokens (PYT) into more PYT. It is introduced for two reasons:

1. Makes it easier to build yield-leveraging strategies.
2. xPYT has better composability with other protocols that don't expect to claim the yield earned by PYT. (e.g. Rari Fuse, Uniswap, cross-chain bridges) If raw PYT is used instead of xPYT in contracts without Timeless support, the yield accrued to the contract will be lost, so xPYT should be used instead.

xPYT has the following features:

-   **Permissionless deployment**: Anyone can use the `xPYTFactory` contract to deploy xPYT vaults.
-   **Permissionless auto-compounding**: Rather than relying on centralized strategists/harvesters to perform the auto-compounding, xPYT makes the auto-compounding executable by anyone, and the caller would receive a portion of the claimed yield as reward. This means xPYT vaults can rely on MEV bots to perform the auto-compounding, rather than having to build out centralized infrastructure.
-   **Minimal sandwiching losses**: xPYT uses the TWAP oracle offered by Timeless AMM to make sure that when it auto-compounds yield into PYT the price it gets doesn't deviate too much from the TWAP, minimizing losses from sandwiching attacks.

## Architecture

-   [`xPYT.sol`](src/xPYT.sol): Permissionless auto-compounding vault for Timeless perpetual yield tokens
-   [`xPYTFactory.sol`](src/xPYTFactory.sol): Factory for deploying xPYT contracts

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
make update
```

### Compilation

```
make build
```

### Testing

```
make test
```
