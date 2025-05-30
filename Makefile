.PHONY: all init build test format snapshot anvil cast help clean

all: init build test

# Initialize submodules
init:
	git submodule update --init --recursive

# Build the project
build:
	forge build

# Run tests
test:
	forge test

# Format code
format:
	forge fmt

# Generate gas snapshots
snapshot:
	forge snapshot

# Start Anvil local testnet
anvil:
	anvil

# Run Cast commands
cast:
	@echo "Usage: make cast ARGS='<subcommand>'"
	@if [ -n "$(ARGS)" ]; then \
		cast $(ARGS); \
	fi

# Install dependencies
install-foundry:
	@echo "Installing Foundry..."
	@curl -L https://foundry.paradigm.xyz | bash
	@. ~/.bashrc || . ~/.zshrc
	@foundryup

install-npm:
	npm install @predicate/predicate-contracts

install: install-foundry install-npm

# Clean build artifacts and cache
clean:
	forge clean
	rm -rf cache
	rm -rf out
	rm -rf node_modules

# Help target to display available commands
.PHONY: help

# Help target to display available commands
help:
    @awk '/^#/{c=substr($$0,3);next}c&&/^[[:alpha:]][[:alnum:]_-]+:/{print substr($$1,1,index($$1,":")),c}1{c=0}' $(MAKEFILE_LIST) | column -s: -t