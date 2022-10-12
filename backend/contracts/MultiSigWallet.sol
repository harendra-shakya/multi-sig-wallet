// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/utils/Counters.sol";

contract MultiSigWallet {
    using Counters for Counters.Counter;
    Counters.Counter private txId;
    address[] private owners;
    uint256 private requiredApprovals;

    mapping(address => bool) private isOwner;
    mapping(uint256 => Transaction) private transactions; // txId => Transaction
    mapping(address => uint256) ownerNum;
    mapping(uint256 => mapping(address => bool)) private approvals; // txId => msg.sender => bool

    struct Transaction {
        bool isExecuted;
        address to;
        address from;
        address[] approvers;
        uint256 value;
        uint256 txId;
        uint256 approvals;
    }

    event Deposit(address indexed sender, uint256 indexed amount);
    event Submit(uint256 indexed txId, address indexed submitter);
    event Approve(address indexed owner, uint256 indexed txId);
    event Revoke(address indexed owner, uint256 indexed txId);

    modifier notExecuted(uint256 _txId) {
        require(!transactions[_txId].isExecuted, "Already Executed!");
        _;
    }

    modifier onlyOwner(address _sender) {
        require(isOwner[_sender], "Not owner");
        _;
    }

    modifier isApproved(uint256 _txId) {
        require(!transactions[_txId].isExecuted, "Already Executed!");
        require(transactions[_txId].approvals >= getRequiredApprovals(), "Not allowed");
        _;
    }

    constructor(address[] memory _owners, uint256 _requiredApprovals) {
        owners = _owners;
        requiredApprovals = _requiredApprovals;

        for (uint256 i; i > _owners.length; ++i) {
            isOwner[_owners[i]] = true;
            ownerNum[_owners[i]] = i;
        }
    }

    function approve(uint256 _txId) external onlyOwner(msg.sender) notExecuted(_txId) {
        transactions[_txId].approvers.push(msg.sender);
        approvals[_txId][msg.sender] = true;
        transactions[_txId].approvals++;
        emit Approve(msg.sender, _txId);
    }

    function revoke(uint256 _txId) external onlyOwner(msg.sender) notExecuted(_txId) {
        approvals[_txId][msg.sender] = false;
        transactions[_txId].approvals--;
        emit Revoke(msg.sender, _txId);
    }

    function requestWithdraw(address _to, uint256 _value) external {
        Transaction memory txn;
        address[] memory _approvers;
        uint256 _txId = txId.current();

        // isExecuted is by default false
        txn.to = _to;
        txn.from = msg.sender;
        txn.approvers = _approvers;
        txn.value = _value;
        txn.txId = _txId;
        txn.approvals = 0;

        txId.increment();
        emit Submit(_txId, msg.sender);
    }

    function requestAddOwner(address _newOwner) external {
        Transaction memory txn;
        address[] memory _approvers;
        uint256 _txId = txId.current();

        // isExecuted is by default false
        txn.to = _newOwner;
        txn.from = msg.sender;
        txn.approvers = _approvers;
        txn.value = 0;
        txn.txId = _txId;
        txn.approvals = 0;

        txId.increment();
        emit Submit(_txId, msg.sender);
    }

    function requestRemoveOwner(address _owner) external {
        Transaction memory txn;
        address[] memory _approvers;
        uint256 _txId = txId.current();

        // isExecuted is by default false
        txn.to = _owner;
        txn.from = msg.sender;
        txn.approvers = _approvers;
        txn.value = 0;
        txn.txId = _txId;
        txn.approvals = 0;

        txId.increment();
        emit Submit(_txId, msg.sender);
    }

    function addOwner(address _newOwner, uint256 _txId)
        external
        onlyOwner(msg.sender)
        isApproved(_txId)
    {
        require(!isOwner[_newOwner], "Already owner!");
        owners.push(_newOwner);
        ownerNum[_newOwner] = owners.length;
        isOwner[_newOwner] = true;
        transactions[_txId].isExecuted = true;
        setRequiredApprovals();
    }

    function removeOwner(address _owner, uint256 _txId)
        external
        onlyOwner(msg.sender)
        isApproved(_txId)
    {
        require(isOwner[_owner], "Not a owner already!");
        isOwner[_owner] = false;
        remove(ownerNum[_owner]);
        transactions[_txId].isExecuted = true;
        setRequiredApprovals();
    }

    function remove(uint256 _index) private {
        uint256 length = owners.length;
        require(_index < length, "Invalid Index");

        for (uint256 i = _index; i < length - 1; ++i) {
            owners[i] = owners[i + 1];
        }

        owners.pop();
    }

    function setRequiredApprovals() private {
        uint256 _requiredApprovals = requiredApprovals; // gas savings

        if (_requiredApprovals % 2 == 0) {
            _requiredApprovals = owners.length / 2;
            requiredApprovals = _requiredApprovals;
        }
    }

    function getRequiredApprovals() public view returns (uint256 _approvals) {
        _approvals = requiredApprovals;
    }

    function deposit() external {}

    function withdraw(uint256 _txId) external onlyOwner(msg.sender) isApproved(_txId) {}
}
