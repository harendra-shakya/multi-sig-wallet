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

    mapping(address => bool) private isOwner;
    mapping(uint256 => Transaction) private transactions; // txId => Transaction
    mapping(uint256 => OwnerChange) private ownerChanges; // txId => Transaction
    mapping(address => uint256) private ownerNum;
    mapping(uint256 => mapping(address => bool)) private approvals; // txId => msg.sender => bool

    struct Transaction {
        bool isExecuted;
        address to;
        address from;
        address token;
        address[] approvers;
        uint256 value;
        uint256 txId;
        uint256 approvals;
    }

    struct OwnerChange {
        bool isExecuted;
        bool isAddRequest;
        bool isRemoveRequest;
        address changeOwner;
        address[] approvers;
        uint256 txId;
        uint256 approvals;
    }

    event Deposit(address indexed sender, uint256 indexed amount);
    event Request(uint256 indexed txId, address indexed submitter);
    event Approve(address indexed caller, uint256 indexed txId);
    event Revoke(address indexed caller, uint256 indexed txId);
    event AddOwner(address indexed caller, uint256 indexed txId, address indexed addedOwner);
    event RemoveOwner(address indexed caller, uint256 indexed txId, address indexed removeOwner);
    event Withdraw(address indexed to, uint256 indexed txId, address from, uint256 indexed value);

    modifier notExecuted(uint256 _txId) {
        require(_txId <= txId.current(), "Tx id not exists!");
        require(!transactions[_txId].isExecuted, "Already Executed!");
        _;
    }

    modifier onlyOwner(address _sender) {
        require(isOwner[_sender], "Not owner");
        _;
    }

    modifier isApproved(uint256 _txId) {
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

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
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
        if (approvals[_txId][msg.sender]) {
            transactions[_txId].approvals--;
            approvals[_txId][msg.sender] = false;
        }
        emit Revoke(msg.sender, _txId);
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

    function requestWithdraw(
        address _to,
        uint256 _value,
        address _token
    ) external nonReentrant {
        Transaction memory transaction;
        address[] memory _approvers;
        uint256 _txId = txId.current();

        // isExecuted is by default false
        transaction.to = _to;
        transaction.from = address(this);
        transaction.token = _token;
        transaction.approvers = _approvers;
        transaction.value = _value;
        transaction.txId = _txId;
        transaction.approvals = 0;

        transactions[_txId] = transaction;
        txId.increment();
        emit Request(_txId, msg.sender);
    }

    function requestAddOwner(address _newOwner) external nonReentrant {
        require(!isOwner[_newOwner], "Already owner!");
        OwnerChange memory ownerChange;
        address[] memory _approvers;
        uint256 _txId = txId.current();

        ownerChange.isAddRequest = true;
        ownerChange.changeOwner = _newOwner;
        ownerChange.approvers = _approvers;
        ownerChange.txId = _txId;
        ownerChange.approvals = 0;

        ownerChanges[_txId] = ownerChange;
        txId.increment();
        emit Request(_txId, msg.sender);
    }

    function requestRemoveOwner(address _removingOwner) external nonReentrant {
        require(isOwner[_removingOwner], "Not a owner already!");

        OwnerChange memory ownerChange;
        address[] memory _approvers;
        uint256 _txId = txId.current();

        ownerChange.isRemoveRequest = true;
        ownerChange.changeOwner = _removingOwner;
        ownerChange.approvers = _approvers;
        ownerChange.txId = _txId;
        ownerChange.approvals = 0;

        ownerChanges[_txId] = ownerChange;
        txId.increment();
        emit Request(_txId, msg.sender);
    }

    function withdraw(uint256 _txId)
        external
        onlyOwner(msg.sender)
        notExecuted(_txId)
        isApproved(_txId)
        nonReentrant
    {
        address to = transactions[_txId].to;
        address token = transactions[_txId].token;
        uint256 value = transactions[_txId].value;

        _safeTranfer(token, to, value);
        transactions[_txId].isExecuted = true;
        emit Withdraw(to, _txId, transactions[_txId].from, value);
    }

    function isConfimed() external {
        // loop mapping and see how many of them confirmed
    }

    function addOwner(uint256 _txId)
        external
        onlyOwner(msg.sender)
        notExecuted(_txId)
        isApproved(_txId)
        nonReentrant
    {
        require(ownerChanges[_txId].isAddRequest, "Adding owner not requested");
        address newOwner = ownerChanges[_txId].changeOwner;
        owners.push(newOwner);
        ownerNum[newOwner] = owners.length;
        isOwner[newOwner] = true;
        ownerChanges[_txId].isExecuted = true;
        setRequiredApprovals();
        emit AddOwner(msg.sender, _txId, newOwner);
    }

    function removeOwner(uint256 _txId)
        external
        onlyOwner(msg.sender)
        notExecuted(_txId)
        isApproved(_txId)
        nonReentrant
    {
        require(ownerChanges[_txId].isRemoveRequest, "Removing owner not requested");
        address removingOwner = ownerChanges[_txId].changeOwner;
        isOwner[removingOwner] = false;
        remove(ownerNum[removingOwner]);
        ownerChanges[_txId].isExecuted = true;
        setRequiredApprovals();
        emit RemoveOwner(msg.sender, _txId, removingOwner);
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
}
