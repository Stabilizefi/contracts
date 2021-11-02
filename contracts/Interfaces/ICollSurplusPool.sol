// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./IPool.sol";


interface ICollSurplusPool is IPool{

    // --- Events ---
    
    event CollBalanceUpdated(address indexed _account, uint _newBalance);

    // --- Contract setters ---

    function setAddresses(
        address _collTokenAddress,
        address _borrowerOperationsAddress,
        address _troveManagerAddress,
        address _activePoolAddress
    ) external;

    function getCollateral(address _account) external view returns (uint);
    function accountSurplus(address _account, uint _amount) external;
    function claimColl(address _account) external;

}
