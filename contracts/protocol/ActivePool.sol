// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import '../Interfaces/IActivePool.sol';
import "../Dependencies/SafeMath.sol";
import "../utils/SafeToken.sol";
import "../Dependencies/upgradeable/Initializable.sol";


/*
 * The Active Pool holds the ETH collateral and LUSD debt (but not LUSD tokens) for all active troves.
 *
 * When a trove is liquidated, it's ETH and LUSD debt are transferred from the Active Pool, to either the
 * Stability Pool, the Default Pool, or both, depending on the liquidation conditions.
 *
 */
contract ActivePool is IActivePool, Initializable {
    using SafeMath for uint256;

    string constant public NAME = "ActivePool";
    address constant public GAS_TOKEN_ADDR = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    
    address public override collTokenAddress;
    address public borrowerOperationsAddress;
    address public troveManagerAddress;
    address public stabilityPoolAddress;
    address public defaultPoolAddress;
    address public collSurplusPoolAddress;
    
    uint256 internal collAmount;
    uint256 internal LUSDDebt;

    // --- Contract setters ---

    function setAddresses(
        address _collTokenAddress,
        address _borrowerOperationsAddress,
        address _troveManagerAddress,
        address _stabilityPoolAddress,
        address _defaultPoolAddress,
        address _collSurplusPoolAddress
    )
        external
        initializer
    {
        collTokenAddress = _collTokenAddress;
        borrowerOperationsAddress = _borrowerOperationsAddress;
        troveManagerAddress = _troveManagerAddress;
        stabilityPoolAddress = _stabilityPoolAddress;
        defaultPoolAddress = _defaultPoolAddress;
        collSurplusPoolAddress = _collSurplusPoolAddress;

        emit CollTokenAddressChanged(_collTokenAddress);
        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit TroveManagerAddressChanged(_troveManagerAddress);
        emit StabilityPoolAddressChanged(_stabilityPoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
    * Returns the ETH state variable.
    *
    *Not necessarily equal to the the contract's raw ETH balance - ether can be forcibly sent to contracts.
    */
    function getETH() external view override returns (uint) {
        return collAmount;
    }

    function getLUSDDebt() external view override returns (uint) {
        return LUSDDebt;
    }

    // --- Pool functionality ---

    function sendETH(address _account, uint _amount) external override {
        _requireCallerIsBOorTroveMorSP();

        collAmount = collAmount.sub(_amount);
        emit ActivePoolETHBalanceUpdated(collAmount);
        emit EtherSent(_account, _amount);
        
        if (collTokenAddress == GAS_TOKEN_ADDR) {
            SafeToken.safeTransferETH(_account, _amount);
        } else {
            SafeToken.safeTransfer(collTokenAddress, _account, _amount);
            _increasePoolColl(_account, _amount);
        }
    }

    function _increasePoolColl(address _account, uint _amount) internal {
        if (
            _account == stabilityPoolAddress || 
            _account == defaultPoolAddress || 
            _account == collSurplusPoolAddress
        ) 
        {
            IPool(_account).increaseColl(_amount);
        }
    }

    function increaseLUSDDebt(uint _amount) external override {
        _requireCallerIsBOorTroveM();
        LUSDDebt  = LUSDDebt.add(_amount);
        emit ActivePoolLUSDDebtUpdated(LUSDDebt);
    }

    function decreaseLUSDDebt(uint _amount) external override {
        _requireCallerIsBOorTroveMorSP();
        LUSDDebt = LUSDDebt.sub(_amount);
        emit ActivePoolLUSDDebtUpdated(LUSDDebt);
    }

    function increaseColl(uint256 _amount) external override {
        _requireCallerIsBorrowerOperationsOrDefaultPool();
        collAmount = collAmount.add(_amount);
        emit ActivePoolETHBalanceUpdated(collAmount);
    }

    // --- 'require' functions ---

    function _requireCallerIsBorrowerOperationsOrDefaultPool() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
            msg.sender == defaultPoolAddress,
            "ActivePool: Caller is neither BO nor Default Pool");
    }

    function _requireCallerIsBOorTroveMorSP() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
            msg.sender == troveManagerAddress ||
            msg.sender == stabilityPoolAddress,
            "ActivePool: Caller is neither BorrowerOperations nor TroveManager nor StabilityPool");
    }

    function _requireCallerIsBOorTroveM() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
            msg.sender == troveManagerAddress,
            "ActivePool: Caller is neither BorrowerOperations nor TroveManager");
    }

    // --- Fallback function ---

    receive() external payable {
        _requireCallerIsBorrowerOperationsOrDefaultPool();
        collAmount = collAmount.add(msg.value);
        emit ActivePoolETHBalanceUpdated(collAmount);
    }
}
