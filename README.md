# predicate-contracts 

Solidity library for creating compliant smart contracts application (e.g. Uniswap V4 hooks) using the Predicate network.

## Installation

This repository depends on some submodules. Please run the following command before testing. 

```bash
git submodule update --init --recursive
```

### Foundry 

```shell
$ forge install PredicateLabs/predicate-contracts 
```

### Node

```bash
npm install @predicate/predicate-contracts
```


## Build

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

### Cast

```shell
$ cast <subcommand>
```

### Disclaimer 

This library is provided as-is, without any guarantees or warranties. Use at your own risk.