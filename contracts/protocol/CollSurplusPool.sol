// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Interfaces/ICollSurplusPool.sol";
import "../Dependencies/SafeMath.sol";
import "../utils/SafeToken.sol";

import "../Dependencies/upgradeable/Initializable.sol";


contract CollSurplusPool is ICollSurplusPool, Initializable {
    using SafeMath for uint256;

    string constant public NAME = "CollSurplusPool";
    address constant public GAS_TOKEN_ADDR = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    address public collTokenAddress;
    address public borrowerOperationsAddress;
    address public troveManagerAddress;
    address public activePoolAddress;

    uint256 internal collAmount;
    mapping (address => uint) internal balances;

    // --- Contract setters ---

    function setAddresses(
        address _collTokenAddress,
        address _borrowerOperationsAddress,
        address _troveManagerAddress,
        address _activePoolAddress
    )
        external
        override
        initializer
    {

        collTokenAddress = _collTokenAddress;
        borrowerOperationsAddress = _borrowerOperationsAddress;
        troveManagerAddress = _troveManagerAddress;
        activePoolAddress = _activePoolAddress;

        emit CollTokenAddressChanged(_collTokenAddress);
        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit TroveManagerAddressChanged(_troveManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
    }

    /* Returns the ETH state variable at ActivePool address.
       Not necessarily equal to the raw ether balance - ether can be forcibly sent to contracts. */
    function getETH() external view override returns (uint) {
        return collAmount;
    }

    function getCollateral(address _account) external view override returns (uint) {
        return balances[_account];
    }

    // --- Pool functionality ---

    function accountSurplus(address _account, uint _amount) external override {
        _requireCallerIsTroveManager();

        uint newAmount = balances[_account].add(_amount);
        balances[_account] = newAmount;

        emit CollBalanceUpdated(_account, newAmount);
    }

    function claimColl(address _account) external override {
        _requireCallerIsBorrowerOperations();
        uint claimableColl = balances[_account];
        require(claimableColl > 0, "CollSurplusPool: No collateral available to claim");

        balances[_account] = 0;
        emit CollBalanceUpdated(_account, 0);

        collAmount = collAmount.sub(claimableColl);
        emit EtherSent(_account, claimableColl);

        if (collTokenAddress == GAS_TOKEN_ADDR) {
            SafeToken.safeTransferETH(_account, claimableColl);
        } else {
            SafeToken.safeTransfer(collTokenAddress, _account, claimableColl);
        }
    }

    function increaseColl(uint256 _amount) external override {
        _requireCallerIsActivePool();
        collAmount = collAmount.add(_amount);
    }

    // --- 'require' functions ---

    function _requireCallerIsBorrowerOperations() internal view {
        require(
            msg.sender == borrowerOperationsAddress,
            "CollSurplusPool: Caller is not Borrower Operations");
    }

    function _requireCallerIsTroveManager() internal view {
        require(
            msg.sender == troveManagerAddress,
            "CollSurplusPool: Caller is not TroveManager");
    }

    function _requireCallerIsActivePool() internal view {
        require(
            msg.sender == activePoolAddress,
            "CollSurplusPool: Caller is not Active Pool");
    }

    // --- Fallback function ---

    receive() external payable {
        _requireCallerIsActivePool();
        collAmount = collAmount.add(msg.value);
    }
}
