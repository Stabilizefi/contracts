// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import '../Interfaces/IDefaultPool.sol';
import "../Dependencies/SafeMath.sol";
import "../utils/SafeToken.sol";
import "../Dependencies/upgradeable/Initializable.sol";


/*
 * The Default Pool holds the collateral and LUSD debt (but not LUSD tokens) from liquidations that have been redistributed
 * to active troves but not yet "applied", i.e. not yet recorded on a recipient active trove's struct.
 *
 * When a trove makes an operation that applies its pending collateral and LUSD debt, its pending collateral and LUSD debt is moved
 * from the Default Pool to the Active Pool.
 */
contract DefaultPool is IDefaultPool, Initializable{
    using SafeMath for uint256;

    string constant public NAME = "DefaultPool";
    address constant public GAS_TOKEN_ADDR = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    
    address public collTokenAddress;
    address public troveManagerAddress;
    address public activePoolAddress;
    
    uint256 internal collAmount;
    uint256 internal LUSDDebt;

    // --- Dependency setters ---

    function setAddresses(
        address _collTokenAddress,
        address _troveManagerAddress,
        address _activePoolAddress
    )
        external
        initializer
    {   

        collTokenAddress = _collTokenAddress;
        troveManagerAddress = _troveManagerAddress;
        activePoolAddress = _activePoolAddress;

        emit CollTokenAddressChanged(_collTokenAddress);
        emit TroveManagerAddressChanged(_troveManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
    * Returns the ETH state variable.
    *
    * Not necessarily equal to the the contract's raw ETH balance - ether can be forcibly sent to contracts.
    */
    function getETH() external view override returns (uint) {
        return collAmount;
    }

    function getLUSDDebt() external view override returns (uint) {
        return LUSDDebt;
    }

    // --- Pool functionality ---

    function sendETHToActivePool(uint _amount) external override {
        _requireCallerIsTroveManager();
        address activePool = activePoolAddress; // cache to save an SLOAD
        
        collAmount = collAmount.sub(_amount);
        emit DefaultPoolETHBalanceUpdated(collAmount);
        emit EtherSent(activePool, _amount);

        if (collTokenAddress == GAS_TOKEN_ADDR) {
            SafeToken.safeTransferETH(activePool, _amount);
        } else {
            SafeToken.safeTransfer(collTokenAddress, activePool, _amount);
            _increasePoolColl(activePool, _amount);
        }
    }

    function _increasePoolColl(address _account, uint _amount) internal {
        IPool(_account).increaseColl(_amount);
    }

    function increaseLUSDDebt(uint _amount) external override {
        _requireCallerIsTroveManager();
        LUSDDebt = LUSDDebt.add(_amount);
        emit DefaultPoolLUSDDebtUpdated(LUSDDebt);
    }

    function decreaseLUSDDebt(uint _amount) external override {
        _requireCallerIsTroveManager();
        LUSDDebt = LUSDDebt.sub(_amount);
        emit DefaultPoolLUSDDebtUpdated(LUSDDebt);
    }

    function increaseColl(uint256 _amount) external override {
        _requireCallerIsActivePool();
        collAmount = collAmount.add(_amount);
        emit DefaultPoolETHBalanceUpdated(collAmount);
    }

    // --- 'require' functions ---

    function _requireCallerIsActivePool() internal view {
        require(msg.sender == activePoolAddress, "DefaultPool: Caller is not the ActivePool");
    }

    function _requireCallerIsTroveManager() internal view {
        require(msg.sender == troveManagerAddress, "DefaultPool: Caller is not the TroveManager");
    }

    // --- Fallback function ---

    receive() external payable {
        _requireCallerIsActivePool();
        collAmount = collAmount.add(msg.value);
        emit DefaultPoolETHBalanceUpdated(collAmount);
    }
}
