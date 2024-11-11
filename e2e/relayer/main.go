package main

import (
	"log"

	"github.com/hyperledger-labs/yui-relayer/cmd"

	ethereum "github.com/datachainlab/ethereum-ibc-relay-chain/pkg/relay/ethereum"
	hd "github.com/datachainlab/ibc-hd-signer/pkg/hd"
	mock "github.com/hyperledger-labs/yui-relayer/provers/mock/module"
)

func main() {
	if err := cmd.Execute(
		ethereum.Module{},   // Ethereum Chain Module
		hd.Module{},         // HD Signer Module
		mock.Module{},       // Mock Prover Module
	); err != nil {
		log.Fatal(err)
	}
}
