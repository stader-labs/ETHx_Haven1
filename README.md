## HsETH

### Haven1 ETHx Wrapper designed by Stader Labs

hsETH is an ERC-20 token developed by Stader Labs, specifically designed for the Staders restaking ecosystem. It allows users to deposit ETH tokens into the contract and mint liquid hsETH, providing unique opportunities for decentralized exchange liquidity pools. This facilitates easy entry and exit from positions representing restaked assets.

### Deployment

| Contract                  | Address                                    | Network |
| ------------------------- | ------------------------------------------ | ------- |
| ProxyAdmin                | 0x6904603c27392310D19E389105CA792FB935C43C | Holesky |
| HsETH                     | 0x217EBabCf15EC6deaCF11f737d79275e95C97EFE | Holesky |
| StaderHavenStakingManager | 0xDBAaD20ffd67dfaeBdE40b842cB78eAa18F1BB74 | Holesky |
| ProxyAdmin                | 0x12eA3B1265d5D41a3b582410241537A751FC52ff | Sepolia |
| HsETH                     | 0x063d4c8CFeF375C2Fc1710934504e2b7aB85fd15 | Sepolia |

#### Deployment Process

##### hsETH

1. Deploy ProxyAdmin or choose an existing Admin
   ```bash
   $ HSETH_ADMIN=0x2E1F5C7f87096fb7FfFbB6654Fc3b2CE303aEff5 forge script ./script/HSETH.s.sol:DeployHSETH --sig 'deployAdmin()' --broadcast --slow --rpc-url ${RPC_URL} --private-key ${PRIVATE_KEY} --etherscan-api-key ${ETHERSCAN_API_KEY} --verify
   ```
   Make note of deployment details, contract address and owner.
2. Deploy HsETH contract with ProxyAdmin as owner
   ```bash
   $ HSETH_ADMIN=0x2E1F5C7f87096fb7FfFbB6654Fc3b2CE303aEff5 PROXY_ADMIN=0x6904603c27392310D19E389105CA792FB935C43C forge script ./script/HSETH.s.sol:DeployHSETH --sig 'proxyDeploy()' --broadcast --slow --rpc-url ${RPC_URL} --private-key ${PRIVATE_KEY} --etherscan-api-key ${ETHERSCAN_API_KEY} --verify
   ```
3. Upgrade HsETH Contract as required
   ```bash
   $ PROXY_ADMIN=0x6904603c27392310D19E389105CA792FB935C43C PROXY_ADDRESS=0x217EBabCf15EC6deaCF11f737d79275e95C97EFE forge script ./script/HSETH.s.sol:DeployHSETH --sig 'proxyUpgrade()' --broadcast --slow --rpc-url ${RPC_URL} --private-key ${PRIVATE_KEY} --etherscan-api-key ${ETHERSCAN_API_KEY} --verify
   ```

##### StaderHavenStakingManager

1. Deploy StaderHavenStakingManager
   ```bash
   $ HSETH_ADMIN=0x2E1F5C7f87096fb7FfFbB6654Fc3b2CE303aEff5 PROXY_ADMIN=0x6904603c27392310D19E389105CA792FB935C43C  HSETH=0x217EBabCf15EC6deaCF11f737d79275e95C97EFE TREASURY=0x2E1F5C7f87096fb7FfFbB6654Fc3b2CE303aEff5 STADER_CONFIG=0x50FD3384783EE49011E7b57d7A3430a762b3f3F2 forge script ./script/StaderHavenStakingManager.s.sol:DeployStakingManager --sig 'proxyDeploy()' --broadcast --slow --rpc-url ${HOLESKY_URL} --private-key ${PRIVATE_KEY} --etherscan-api-key ${ETHERSCAN_API_KEY} --verify
   ```
2. Upgrade StaderHavenStakingManager as needed
   ```bash
   $ PROXY_ADMIN=0x6904603c27392310D19E389105CA792FB935C43C PROXY_ADDRESS=0xDBAaD20ffd67dfaeBdE40b842cB78eAa18F1BB74 forge script ./script/StaderHavenStakingManager.s.sol:DeployStakingManager --sig 'proxyUpgrade()' --broadcast --slow --rpc-url ${HOLESKY_URL} --private-key ${PRIVATE_KEY} --etherscan-api-key ${ETHERSCAN_API_KEY} --verify
   ```
## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
