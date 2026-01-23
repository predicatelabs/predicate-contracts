# Contributing

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

## Setup

```bash
git clone https://github.com/PredicateLabs/predicate-contracts
cd predicate-contracts
git submodule update --init --recursive
```

## Commands

```bash
forge build      # Compile contracts
forge test       # Run tests
forge fmt        # Format code
```

## Pull Requests

- Ensure all tests pass (`forge test`)
- Format code before committing (`forge fmt`)
- Keep changes focused and well-documented
