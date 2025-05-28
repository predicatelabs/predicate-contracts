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
help:
	@echo "Available targets:"
	@echo "  all             - Initialize, build, and test"
	@echo "  init            - Initialize git submodules"
	@echo "  build           - Build the project"
	@echo "  test            - Run tests"
	@echo "  format          - Format code"
	@echo "  snapshot        - Generate gas snapshots"
	@echo "  anvil           - Start Anvil local testnet"
	@echo "  cast            - Run Cast commands (usage: make cast ARGS='<subcommand>')"
	@echo "  install-foundry - Install Foundry"
	@echo "  install-npm     - Install via npm"
	@echo "  install         - Install Foundry and npm dependencies"
	@echo "  clean           - Remove build artifacts and cache files"
	@echo "  help            - Display this help message" 