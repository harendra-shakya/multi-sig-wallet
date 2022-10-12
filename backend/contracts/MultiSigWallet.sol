// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract MultiSigWallet is ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private txId;
    address[] private owners;
    uint256 private requiredApprovals;
    bytes4 private constant T_SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));
    bytes4 private constant TF_SELECTOR =
        bytes4(keccak256(bytes("transferFrom(address,address,uint256)")));

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

    function approve(uint256 _txId)
        external
        onlyOwner(msg.sender)
        notExecuted(_txId)
        nonReentrant
    {
        transactions[_txId].approvers.push(msg.sender);
        approvals[_txId][msg.sender] = true;
        transactions[_txId].approvals++;
        emit Approve(msg.sender, _txId);
    }

    function revoke(uint256 _txId) external onlyOwner(msg.sender) notExecuted(_txId) nonReentrant {
        approvals[_txId][msg.sender] = false;
        transactions[_txId].approvals--;
        emit Revoke(msg.sender, _txId);
    }

    function requestWithdraw(address _to, uint256 _value) external nonReentrant {
        Transaction memory transaction;
        address[] memory _approvers;
        uint256 _txId = txId.current();

        // isExecuted is by default false
        transaction.to = _to;
        transaction.from = msg.sender;
        transaction.approvers = _approvers;
        transaction.value = _value;
        transaction.txId = _txId;
        transaction.approvals = 0;

        transactions[_txId] = transaction;
        txId.increment();
        emit Submit(_txId, msg.sender);
    }

    function _safeTranfer(
        address token,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(T_SELECTOR, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer Failed!");
    }

    function withdraw(
        uint256 _txId,
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner(msg.sender) isApproved(_txId) nonReentrant {
        _safeTranfer(_token, _to, _amount);
    }

    function _safeTranferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(TF_SELECTOR, from, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer Failed!");
    }

    function requestAddOwner(address _newOwner) external nonReentrant {
        Transaction memory transaction;
        address[] memory _approvers;
        uint256 _txId = txId.current();

        // isExecuted is by default false
        transaction.to = _newOwner;
        transaction.from = msg.sender;
        transaction.approvers = _approvers;
        transaction.value = 0;
        transaction.txId = _txId;
        transaction.approvals = 0;

        transactions[_txId] = transaction;
        txId.increment();
        emit Submit(_txId, msg.sender);
    }

    function requestRemoveOwner(address _owner) external nonReentrant {
        Transaction memory transaction;
        address[] memory _approvers;
        uint256 _txId = txId.current();

        // isExecuted is by default false
        transaction.to = _owner;
        transaction.from = msg.sender;
        transaction.approvers = _approvers;
        transaction.value = 0;
        transaction.txId = _txId;
        transaction.approvals = 0;

        transactions[_txId] = transaction;
        txId.increment();
        emit Submit(_txId, msg.sender);
    }

    function addOwner(address _newOwner, uint256 _txId)
        external
        onlyOwner(msg.sender)
        isApproved(_txId)
        nonReentrant
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
        nonReentrant
    {
        require(isOwner[_owner], "Not a owner already!");
        isOwner[_owner] = false;
        remove(ownerNum[_owner]);
        transactions[_txId].isExecuted = true;
        setRequiredApprovals();
    }

    function remove(uint256 _index) private nonReentrant {
        uint256 length = owners.length;
        require(_index < length, "Invalid Index");

        for (uint256 i = _index; i < length - 1; ++i) {
            owners[i] = owners[i + 1];
        }

        owners.pop();
    }

    function setRequiredApprovals() private nonReentrant {
        uint256 _requiredApprovals = requiredApprovals; // gas savings

        if (_requiredApprovals % 2 == 0) {
            _requiredApprovals = owners.length / 2;
            requiredApprovals = _requiredApprovals;
        }
    }

    function getRequiredApprovals() public view returns (uint256 _approvals) {
        _approvals = requiredApprovals;
    }

    function deposit() external nonReentrant {}
}
