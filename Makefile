-include .env

.PHONY: all test deploy

build:; forge build

test:; forge test

install:;forge install OpenZeppelin/openzeppelin-contracts && forge install smartcontractkit/chainlink-local@v0.2.5-beta.0
