// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./IPool.sol";


interface IActivePool is IPool {
    // --- Events ---

    event ActivePoolLUSDDebtUpdated(uint _LUSDDebt);
    event ActivePoolETHBalanceUpdated(uint _ETH);

    // --- Functions ---
    function sendETH(address _account, uint _amount) external;
    function getLUSDDebt() external view returns (uint);
    function increaseLUSDDebt(uint _amount) external;
    function decreaseLUSDDebt(uint _amount) external;
    function collTokenAddress() external view returns (address);
}
