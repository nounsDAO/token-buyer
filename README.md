# Token Buyer

This project is under development by [Nouns DAO](https://nouns.wtf/). It's inspired by [YFI Buyer](https://github.com/banteg/yfi-buyer).

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

## Deploy to testnet

```sh
forge script script/DeployUSDC.s.sol:DeployUSDCGoerli --broadcast --verify -vvvvv --chain-id 5 --rpc-url <GOERLI_RPC> --keystores <KEYSTORE> --sender <DEPLOYER_ADDRESS>
```
