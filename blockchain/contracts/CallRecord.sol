// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract CallRecord {
    address public owner;
    uint256 public totalRecords;

    struct CallData {
        string userId;
        uint256 timestamp;
        string category;
        bool isScam;
    }

    mapping(bytes32 => CallData) public records;
    mapping(bytes32 => bool) public exists;

    event RecordStored(bytes32 indexed callHash, string category, bool isScam, uint256 timestamp);
    event ScamFlagged(bytes32 indexed callHash, uint256 timestamp);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function storeRecord(
        bytes32 callHash,
        string memory userId,
        string memory category,
        bool isScam
    ) external onlyOwner {
        require(!exists[callHash], "Record already exists");

        records[callHash] = CallData({
            userId: userId,
            timestamp: block.timestamp,
            category: category,
            isScam: isScam
        });

        exists[callHash] = true;
        totalRecords++;

        emit RecordStored(callHash, category, isScam, block.timestamp);

        if (isScam) {
            emit ScamFlagged(callHash, block.timestamp);
        }
    }

    function verifyRecord(bytes32 callHash) external view returns (bool) {
        return exists[callHash];
    }

    function getRecord(bytes32 callHash) external view returns (CallData memory) {
        require(exists[callHash], "Record not found");
        return records[callHash];
    }

    function getOwner() external view returns (address) {
        return owner;
    }
}