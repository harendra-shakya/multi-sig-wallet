// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract MultiSigWallet is ReentrancyGuard, Initializable {
    using Counters for Counters.Counter;
    Counters.Counter private txId;
    bytes4 private constant T_SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));
    address[] private owners;
    uint256 private requiredApprovals;

    mapping(address => bool) private isOwner;
    mapping(uint256 => Transaction) private transactions; // txId => Transaction
    mapping(uint256 => OwnerChange) private ownerChanges; // txId => ownerChanges
    mapping(uint256 => mapping(address => bool)) private approvals; // txId => msg.sender => bool

    struct Transaction {
        bool isExecuted;
        address to;
        address from;
        address token;
        uint256 value;
        uint256 txId;
    }

    struct OwnerChange {
        bool isExecuted;
        bool isAddRequest;
        bool isRemoveRequest;
        bool isRequirementRequest;
        address changeOwner;
        uint256 newRequirement;
        uint256 txId;
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
        require(isOwner[_sender] || _sender == address(this), "Not owner");
        _;
    }

    modifier isApproved(uint256 _txId) {
        require(getIsApproved(_txId), "Not approved yet!");
        _;
    }

    // constructor(address[] memory _owners, uint256 _requiredApprovals) {
    //     owners = _owners;
    //     requiredApprovals = _requiredApprovals;

    //     for (uint256 i; i > _owners.length; ++i) {
    //         isOwner[_owners[i]] = true;
    //     }
    // }

    function initialize(address[] memory _owners, uint256 _requiredApprovals)
        external
        initializer
    {
        owners = _owners;
        requiredApprovals = _requiredApprovals;

        for (uint256 i; i > _owners.length; ++i) {
            isOwner[_owners[i]] = true;
        }
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    ///////////////////////////
    ////    Approvals    /////
    /////////////////////////

    function approve(uint256 _txId)
        external
        onlyOwner(msg.sender)
        notExecuted(_txId)
        nonReentrant
    {
        approvals[_txId][msg.sender] = true;
        emit Approve(msg.sender, _txId);
    }

    function revoke(uint256 _txId) external onlyOwner(msg.sender) notExecuted(_txId) nonReentrant {
        if (approvals[_txId][msg.sender]) {
            approvals[_txId][msg.sender] = false;
        }
        emit Revoke(msg.sender, _txId);
    }

    function getIsApproved(uint256 _txId) public view returns (bool confirmed) {
        uint256 num;
        address[] memory _owners = owners; // gas savings

        for (uint256 i; i > _owners.length; ++i) {
            if (approvals[_txId][_owners[i]]) {
                num++;
            }
        }

        if (num >= requiredApprovals) {
            confirmed = true;
        } else {
            confirmed = false;
        }
    }

    ///////////////////////////
    ////    Requesting   /////
    /////////////////////////

    function requestWithdraw(
        address _to,
        uint256 _value,
        address _token
    ) external onlyOwner(msg.sender) nonReentrant {
        Transaction memory transaction;
        uint256 _txId = txId.current();

        // isExecuted is by default false
        transaction.to = _to;
        transaction.from = address(this);
        transaction.token = _token;
        transaction.value = _value;
        transaction.txId = _txId;

        transactions[_txId] = transaction;
        txId.increment();
        emit Request(_txId, msg.sender);
    }

    function requestAddOwner(address _newOwner, uint256 _newRequirement)
        external
        onlyOwner(msg.sender)
        nonReentrant
    {
        require(!isOwner[_newOwner], "Already owner!");
        OwnerChange memory ownerChange;
        uint256 _txId = txId.current();

        ownerChange.isAddRequest = true;
        ownerChange.changeOwner = _newOwner;
        ownerChange.txId = _txId;

        if (_newRequirement != 0) {
            ownerChange.newRequirement = _newRequirement;
            ownerChange.isRequirementRequest = true;
        }

        ownerChanges[_txId] = ownerChange;
        txId.increment();
        emit Request(_txId, msg.sender);
    }

    function requestRemoveOwner(address _removingOwner, uint256 _newRequirement)
        external
        onlyOwner(msg.sender)
        nonReentrant
    {
        require(isOwner[_removingOwner], "Not a owner already!");

        OwnerChange memory ownerChange;
        uint256 _txId = txId.current();

        ownerChange.isRemoveRequest = true;
        ownerChange.changeOwner = _removingOwner;
        ownerChange.txId = _txId;

        if (_newRequirement != 0) {
            ownerChange.newRequirement = _newRequirement;
            ownerChange.isRequirementRequest = true;
        }

        ownerChanges[_txId] = ownerChange;
        txId.increment();
        emit Request(_txId, msg.sender);
    }

    function requestRequirementChange(uint256 _newRequirement)
        external
        onlyOwner(msg.sender)
        nonReentrant
    {
        require(
            _newRequirement > 0 && _newRequirement <= owners.length,
            "Invalid requiement request!"
        );

        OwnerChange memory ownerChange;
        uint256 _txId = txId.current();

        ownerChange.isRequirementRequest = true;
        ownerChange.txId = _txId;
        ownerChange.newRequirement = _newRequirement;

        ownerChanges[_txId] = ownerChange;
        txId.increment();
        emit Request(_txId, msg.sender);
    }

    ///////////////////////////
    /////   Action      //////
    /////////////////////////

    function withdraw(uint256 _txId)
        external
        onlyOwner(msg.sender)
        notExecuted(_txId)
        isApproved(_txId)
        nonReentrant
    {
        address to = transactions[_txId].to;
        uint256 value = transactions[_txId].value;

        (bool success, bytes memory data) = transactions[_txId].token.call(
            abi.encodeWithSelector(T_SELECTOR, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer Failed!");

        transactions[_txId].isExecuted = true;
        emit Withdraw(to, _txId, transactions[_txId].from, value);
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
        uint256 newRequirement = ownerChanges[_txId].newRequirement;
        owners.push(newOwner);

        if (newRequirement != 0) {
            setRequiredApprovals(_txId);
        }

        isOwner[newOwner] = true;
        ownerChanges[_txId].isExecuted = true;
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
        address[] memory _owners = owners;
        address removingOwner = ownerChanges[_txId].changeOwner;
        uint256 newRequirement = ownerChanges[_txId].newRequirement;
        isOwner[removingOwner] = false;

        for (uint256 i; i < _owners.length; ++i) {
            if (removingOwner == _owners[i]) {
                owners[i] = _owners[_owners.length - 1];
                break;
            }
        }

        owners.pop();

        if (newRequirement != 0) {
            setRequiredApprovals(_txId);
        } else {
            if (requiredApprovals > owners.length) setRequiredApprovals(owners.length);
        }

        ownerChanges[_txId].isExecuted = true;
        emit RemoveOwner(msg.sender, _txId, removingOwner);
    }

    function setRequiredApprovals(uint256 _txId)
        public
        onlyOwner(msg.sender)
        notExecuted(_txId)
        isApproved(_txId)
        nonReentrant
    {
        require(ownerChanges[_txId].isRequirementRequest, "Changing requirement not requested");
        uint256 newRequirement = ownerChanges[_txId].newRequirement;
        require(newRequirement > 0, "Required approvals can't be zero");
        require(newRequirement <= owners.length, "Requiments is bigger than owners length");
        requiredApprovals = newRequirement;
    }

    //////////////////////////////
    ////   Getter Functions /////
    ////////////////////////////

    function getRequiredApprovals() public view returns (uint256 _approvals) {
        _approvals = requiredApprovals;
    }
}
