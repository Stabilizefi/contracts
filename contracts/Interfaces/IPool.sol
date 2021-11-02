// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

// Common interface for the Pools.
interface IPool {
    
    // --- Events ---
    
    event CollTokenAddressChanged(address _newCollTokenAddress);
    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event StabilityPoolAddressChanged(address _newStabilityPoolAddress);
    event DefaultPoolAddressChanged(address _newDefaultPoolAddress);
    event CollSurplusPoolAddressChanged(address _newCollSurplusPoolAddress);
    event ActivePoolAddressChanged(address _newActivePoolAddress);
    
    event EtherSent(address _to, uint _amount);

    // --- Functions ---
    
    function getETH() external view returns (uint);
    function increaseColl(uint256 _amount) external;
}
