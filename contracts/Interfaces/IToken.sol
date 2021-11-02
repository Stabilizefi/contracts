// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Dependencies/IERC20.sol";
import "../Dependencies/IERC2612.sol";

interface IToken is IERC20, IERC2612 { 

    // --- Functions ---
    
    function sendToTokenStaking(address _sender, uint256 _amount) external;

    function getDeploymentStartTime() external view returns (uint256);
}
