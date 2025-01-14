// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IIBCClient} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/02-client/IIBCClient.sol";
import {Height} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/Client.sol";

contract MockIBCClient is IIBCClient {
    event UpdateClientCommitments();

    function updateClient(MsgUpdateClient calldata) external {}

    function updateClientCommitments(
        string calldata,
        Height.Data[] calldata
    ) external {
        emit UpdateClientCommitments();
    }

    function createClient(
        MsgCreateClient calldata
    ) external pure returns (string memory clientId) {
        return "";
    }

    function routeUpdateClient(
        MsgUpdateClient calldata
    ) external pure returns (address, bytes4, bytes memory) {
        return (address(0), bytes4(0), "");
    }
}
