# Token Buyer

This project is under development by [Nouns DAO](https://nouns.wtf/). It's inspired by [YFI Buyer](https://github.com/banteg/yfi-buyer).

[Technical spec](https://github.com/nounsDAO/nouns-tech/tree/main/payment-in-stablecoins)

The purpose of this project is to allow the DAO to pay with ERC20 tokens (e.g. stablecoins) in proposals.
It's not straightforward for a DAO to swap from ETH to an ERC20 without getting bad price due to sandwich bots pushing the slippage to the max.
It also allows the DAO to not necessarily hold a large position of the ERC20 to facilitate the payments. Instead, the swaps happens on a need basis.

When the DAO wants to pay with tokens, it can do a proposal a tx that calls `Payer.sendOrRegisterDebt(account, amount)`. That will transfer tokens if `Payer` has available balance, and otherwise will register a debt entry for that account and amount.

The `TokenBuyer` contract gets funded with ETH by the DAO, and offers anyone to swap ETH for tokens. The price is set by an external oracle (e.g. chainlink). There's an incentive to swap with `TokenBuyer` when the oracle price is lagging and favorable to other exchanges. Once a swap has happened, any outstanding debt is paid.

## Contracts

- [TokenBuyer](https://github.com/nounsDAO/token-buyer/blob/main/src/TokenBuyer.sol)

  - Gets funded with ETH (e.g. by the DAO treasury)
  - Allows anyone to swap ERC20 tokens (e.g. USDC) for ETH
  - ERC20 tokens are sent to `Payer`
  - The price is set according to an oracle (`PriceFeed`)
  - Limits the amount of ERC20 it will buy according to the amount of debt in `Payer` + some buffer
  - Once a swap happens, attempt to pay any outstanding debt in `Payer` by calling `Payer.payBackDebt`

- [Payer](https://github.com/nounsDAO/token-buyer/blob/main/src/Payer.sol)

  - Receives ERC20 tokens from `TokenBuyer`
  - Can be asked to send the tokens to an address by the owner (e.g. the DAO)
  - If there aren't enough tokens, registers a debt entry, and pays it out in FIFO order when more tokens are available

- [PriceFeed](https://github.com/nounsDAO/token-buyer/blob/main/src/PriceFeed.sol)

  - Returns a price for ETH/token from an external oracle (e.g. chainlink)

## Tests

Since we're running some tests with a mainnet fork, to get the best trace include your Etherscan API key when running tests:

```sh
forge test --etherscan-api-key <your api key here>
```

If you're ok with a less-readable trace simply run:

```sh
forge test
```

To run all tests except mainnet forking tests:

```sh
forge test --nmc '.*Fork.*' -vvv
```

## Deploy to testnet

```sh
forge script script/DeployUSDC.s.sol:DeployUSDCGoerli --broadcast --verify -vvvvv --chain-id 5 --rpc-url <GOERLI_RPC> --keystores <KEYSTORE> --sender <DEPLOYER_ADDRESS>
```

## Deploy to mainnet

```sh
forge script script/DeployUSDC.s.sol:DeployUSDCMainnet --broadcast --verify -vvvvv --chain-id 1 --rpc-url $MAINNET_RPC --sender $DEPLOYER_MAINNET -i 1
```

# Latest deployment

## Goerli

| Contract   | Address |
|----------- | --------|
| TokenBuyer | [0x61Ec4584c5B5eBaaD9f21Aac491fBB5B2ff30779](https://goerli.etherscan.io/address/0x61ec4584c5b5ebaad9f21aac491fbb5b2ff30779) |
| Payer | [0xD4A3bf1dF54699E63A2ef7F490E8E22b27B945f0](https://goerli.etherscan.io/address/0xd4a3bf1df54699e63a2ef7f490e8e22b27b945f0) |
| PriceFeed | [0x60C80ee511fce9631dce795C48D60Bbf6922e3e9](https://goerli.etherscan.io/address/0x60c80ee511fce9631dce795c48d60bbf6922e3e9) |

## Mainnet

| Contract   | Address |
|----------- | --------|
| TokenBuyer | [0x4f2aCdc74f6941390d9b1804faBc3E780388cfe5](https://etherscan.io/address/0x4f2aCdc74f6941390d9b1804faBc3E780388cfe5) |
| Payer | [0xd97Bcd9f47cEe35c0a9ec1dc40C1269afc9E8E1D](https://etherscan.io/address/0xd97Bcd9f47cEe35c0a9ec1dc40C1269afc9E8E1D) |
| PriceFeed | [0x05e651Bc3a7f7B7640cAD61dC383ca28Ae000cce](https://etherscan.io/address/0x05e651Bc3a7f7B7640cAD61dC383ca28Ae000cce) |
