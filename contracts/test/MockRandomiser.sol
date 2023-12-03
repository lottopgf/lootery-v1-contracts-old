// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IRandomiserGen2.sol";
import "../interfaces/IRandomiserCallback.sol";

contract MockRandomiser is IRandomiserGen2, Ownable {
    uint256 public nextRequestId = 1;
    mapping(uint256 => address) private requestIdToCallbackMap;
    mapping(address => bool) public authorisedContracts;

    constructor() Ownable(msg.sender) {
        authorisedContracts[msg.sender] = true;
    }

    /**
     * Requests randomness
     */
    function getRandomNumber(
        address callbackContract,
        uint32 callbackGasLimit,
        uint16 minConfirmations
    ) public payable returns (uint256 requestId) {
        requestId = nextRequestId++;
        requestIdToCallbackMap[requestId] = callbackContract;
        return requestId;
    }

    /**
     * Callback function used by VRF Coordinator (V2)
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) external {
        require(requestId < nextRequestId, "Request ID doesn't exist");
        address callbackContract = requestIdToCallbackMap[requestId];
        delete requestIdToCallbackMap[requestId];
        IRandomiserCallback(callbackContract).receiveRandomWords(
            requestId,
            randomWords
        );
    }
}
