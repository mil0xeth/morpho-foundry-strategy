# Yearn Strategy Foundry Mix

## Strategy

This repo contains a strategy for [Morpho protocol](https://morpho.xyz/) on Ethereum mainnet.
The strategy supplies the `want` token to Morpho protocol. If the protocol can find a match from the borrowing side it
connects two sides for a peer-to-peer deal providing [better APY for both sides](https://docs.morpho.xyz/start-here/how-it-works).
Otherwise, the liquidity is supplied to the underlying protocol, currently, only Compound, which provides lower APY and
reward tokens COMP which are swapped for `want` token using Sushi v2 or Uniswap v2.
When a new borrower comes in, he is matched with the highest liquidity supplier.
This flow goes until the full p2p liquidity is matched or all provided gas is used.

### Possible Improvements

- Add Uniswap V3 for swapping reward `COMP` tokens for `want` tokens. For reference see [strategy](https://etherscan.io/address/0x62EA2aCe7a7861394f4A38B84D119498DBBb022c#code)

## What you'll find here

- Basic Solidity Smart Contract for creating your own Yearn Strategy ([`Strategy.sol`](src/Strategy.sol))

- Configured github template with Foundry framework for starting your yearn strategy project.

- Sample test suite. ([`tests`](src/test/))

## How does it work for the User

Let's say Alice holds 100 DAI and wants to start earning yield % on them.

For this Alice needs to `DAI.approve(vault.address, 100)`.

Then Alice will call `Vault.deposit(100)`.

Vault will then transfer 100 DAI from Alice to itself, and mint Alice the corresponding shares.

Alice can then redeem those shares using `Vault.withdrawAll()` for the corresponding DAI balance (exchanged at `Vault.pricePerShare()`).

## Installation and Setup

1. To install with [Foundry](https://github.com/gakonst/foundry).

2. Fork this repository (easier) or create a new repository using it as template. [Create from template](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-repository-from-a-template)

3. Clone your newly created repository recursively to include modules.

```sh
git clone --recursive https://github.com/myuser/foundry-yearn-strategy

cd foundry-yearn-strategy
```

NOTE: if you create from template you may need to run the following command to fetch the git submodules (.gitmodules for exact releases) `git submodule init && git submodule update`

4. Build the project.

```sh
make build
```

5. Sign up for [Infura](https://infura.io/) and generate an API key and copy your RPC url. Store it in the `ETH_RPC_URL` environment variable.
NOTE: you can use other services.

6. Use .env file
  1. Make a copy of `.env.example`
  2. Add the values for `ETH_RPC_URL`, `ETHERSCAN_API_KEY` and other example vars
     NOTE: If you set up a global environment variable, that will take precedence.

7. Run tests
```sh
make test
```

## Basic Use

To deploy the demo Yearn Strategy in a development environment:

TODO

## Implementing Strategy Logic

[`contracts/Strategy.sol`](contracts/Strategy.sol) is where you implement your own logic for your strategy. In particular:

- Create a descriptive name for your strategy via `Strategy.name()`.
- Invest your want tokens via `Strategy.adjustPosition()`.
- Take profits and report losses via `Strategy.prepareReturn()`.
- Unwind enough of your position to payback withdrawals via `Strategy.liquidatePosition()`.
- Unwind all of your positions via `Strategy.exitPosition()`.
- Fill in a way to estimate the total `want` tokens managed by the strategy via `Strategy.estimatedTotalAssets()`.
- Migrate all the positions managed by your strategy via `Strategy.prepareMigration()`.
- Make a list of all position tokens that should be protected against movements via `Strategy.protectedTokens()`.

Check out vault docs from more info on [link](https://docs.yearn.finance/vaults/0.3.0/smart-contracts/BaseStrategy#adjustposition).

## Testing

Tests run in fork environment, you need to complete [Installation and Setup](#installation-and-setup) step 6 to be able to run these commands.

```sh
make test
```
Run tests with traces (very useful)

```sh
make trace
```
Run specific test contract (e.g. `test/StrategyOperation.t.sol`)

```sh
make test-contract contract=StrategyOperationsTest
```
Run specific test contract with traces (e.g. `test/StrategyOperation.t.sol`)

```sh
make trace-contract contract=StrategyOperationsTest
```

See here for some tips on testing [`Testing Tips`](https://book.getfoundry.sh/forge/tests.html)

## Deploying Contracts

You can Deploy and verify your strategies if PRIV_KEY and ETHERSCAN_API_KEY are both set in the .env by using the command

```sh
make deploy
```

Before deploying, update the constructor-args variable within the Makefile to include any parameters applicable. 
Make sure to seperate each argument only by a space, no commas.

The deploy script is coded to deploy the "Strategy" contract within the Strategy.sol file. 
This can be updated by simply updating to src/YourContract.sol:YourContract.

# Resources

- Yearn [Discord channel](https://discord.com/invite/6PNv2nF/)
- [Getting help on Foundry](https://github.com/gakonst/foundry#getting-help)
- [Forge Standard Lib](https://github.com/brockelmore/forge-std)
- [Awesome Foundry](https://github.com/crisgarner/awesome-foundry)
- [Foundry Book](https://book.getfoundry.sh/)
- [Learn Foundry Tutorial](https://www.youtube.com/watch?v=Rp_V7bYiTCM)
