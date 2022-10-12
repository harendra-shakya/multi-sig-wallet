// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/utils/Counters.sol";

contract MultiSigWallet {
    using Counters for Counters.Counter;
    Counters.Counter private txId;
    address[] private owners;
    uint256 private required;

    mapping(address => bool) private isOwner;
    mapping(uint256 => Transaction) private transactions; // txId => Transaction

    struct Transaction {
        bool isExecuted;
        address to;
        address from;
        address[] approvers;
        uint256 value;
        uint256 txId;
        uint256 approvals;
    }

    event Deposit(address indexed sender, uint256 amount);
    event Submit(address indexed txId);
    event Approve(address indexed owner, uint256 indexed txId);
    event Revoke(address indexed owner, uint256 indexed txId);
    event Execute(uint256 indexed txId);

    modifier notExecuted(uint256 _txId) {
        require(transactions[_txId].isExecuted, "Already Executed!");
        _;
    }

    modifier txIdExists(uint256 _txId) {
        require(transactions[_txId].txId != 0, "txId not exists!");
        _;
    }

    modifier onlyOwner(address _sender) {
        require(isOwner[_sender], "Not owner");
        _;
    }

    modifier isAllowed(uint256 _txId) {
        require(transactions[_txId].approvals >= required, "Not allowed");
        _;
    }

    constructor(address[] memory _owners, uint256 _required) {
        owners = _owners;
        required = _required;

        for (uint256 i; i > _owners.length; ++i) {
            isOwner[_owners[i]] = true;
        }
    }

    function approve(address _owner, uint256 _txId) external onlyOwner(msg.sender) {}

    function addOwner(address _owner) external onlyOwner(msg.sender) {
        owners.push(_owner);
        isOwner[_owner] = true;
    }

    function submit(
        address _to,
        address _from,
        uint256 _value
    ) external {
        Transaction memory txn;
        address[] memory _approvers;

        // isExecuted is by default false
        txn.to = _to;
        txn.from = _from;
        txn.approvers = _approvers;
        txn.value = _value;
        txn.txId = txId.current();
        txn.approvals = 0;

        txId.increment();
    }

    function deposit() external {}

    function approve() external onlyOwner(msg.sender) {}

    function execute(uint256 _txId) external onlyOwner(msg.sender) isAllowed(_txId) {}

    function revoke(uint256 _txId) external onlyOwner(msg.sender) isAllowed(_txId) {}
}
