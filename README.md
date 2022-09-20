# Token Buyer

This project is under development by [Nouns DAO](https://nouns.wtf/). It's inspired by [YFI Buyer](https://github.com/banteg/yfi-buyer).

This project provides a trustless ability to buy an ERC-20 token in exchange for ETH.

## Tests

Since we're running some tests with a mainnet fork, to get the best trace include your Etherscan API key when running tests:

```sh
forge test --etherscan-api-key <your api key here>
```

If you're ok with a less-readable trace simply run:

```sh
forge test
```

## Deploy to Rinkeby

```sh
forge script script/DeployUSDC.s.sol:DeployUSDCGoerli --broadcast --verify -vvvvv --chain-id % --rpc-url <GOERLI_RPC> --keystores <KEYSTORE> --sender <DEPLOYER_ADDRESS>
```
