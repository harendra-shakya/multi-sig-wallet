// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./MultiSigWallet.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract Factory {
    address payable immutable walletImplementation;

    event walletCreation(address cloneAddress, address createdBy);

    constructor() {
        walletImplementation = payable(address(new MultiSigWallet()));
    }

    function deploy(address[] memory _owners, uint256 _requiredApprovals) external {
        address payable clone = payable(Clones.clone(walletImplementation));
        MultiSigWallet(clone).initialize(_owners, _requiredApprovals);
        emit walletCreation(clone, msg.sender);
    }
}
