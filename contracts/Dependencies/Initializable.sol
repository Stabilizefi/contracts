// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;


abstract contract Initializable {

    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool public initialized;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        require(!initialized, "Initializable: contract is already initialized");
        _;
        initialized = true; 
    }
}