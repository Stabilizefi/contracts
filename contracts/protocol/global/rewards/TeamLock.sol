// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;


import "../../../Interfaces/IToken.sol";
import "../../../Dependencies/SafeMath.sol";
import "../../../Dependencies/upgradeable/Initializable.sol";


contract TeamLock is Initializable {
    using SafeMath for uint;
    
    IToken public token;
    uint public unlockTime;
    uint public releaseTime;

    mapping (address => uint) public beneficiaryRewards;
    mapping (address => uint) public beneficiaryWithdrawed;

    event Initialize(address token, uint unlockTime, uint releaseTime);
    event Withdraw(address indexed beneficiary, uint amount);

    function initialize(
        address _tokenAddress,
        uint _lockTime,
        uint _releaseTime,
        address[] memory _beneficiaries,
        uint[] memory _rewards
    ) external initializer {
        
        token = IToken(_tokenAddress);
        unlockTime = token.getDeploymentStartTime().add(_lockTime);
        releaseTime = _releaseTime;

        require(_beneficiaries.length == _rewards.length, "invalid length");
        uint totalRewards;
        for (uint i = 0; i < _beneficiaries.length; i++) {
            address beneficiary = _beneficiaries[i];
            uint rewards = _rewards[i];
            beneficiaryRewards[beneficiary] = rewards;
            totalRewards = totalRewards.add(rewards);
        }

        require(totalRewards <= token.balanceOf(address(this)), "invalid total rewards");

        emit Initialize(_tokenAddress, unlockTime, _releaseTime);
    }

    function withdrawable(address _beneficiary) external view returns (uint) {
        if (block.timestamp <= unlockTime || beneficiaryRewards[_beneficiary] == 0) {
            return 0;
        }
        return _withdrawable(_beneficiary);
    }

    function withdraw(uint _amount) external {
        _requireLockupDurationHasPassed();
        _requireIsBeneficiary();

        uint withdrawableAmount = _withdrawable(msg.sender);
        require(_amount <= withdrawableAmount, "TeamLock: invalid amount");
        
        beneficiaryWithdrawed[msg.sender] = beneficiaryWithdrawed[msg.sender].add(_amount);
        token.transfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    function _withdrawable(address _beneficiary) internal view returns (uint) {
        uint rewards = beneficiaryRewards[_beneficiary];
        uint released = rewards.mul(block.timestamp.sub(unlockTime)).div(releaseTime);
        uint withdrawableAmount = released.sub(beneficiaryWithdrawed[_beneficiary]);
        return withdrawableAmount;
    }

    function _requireLockupDurationHasPassed() internal view {
        require(block.timestamp > unlockTime, "TeamLock: The lockup duration must have passed");
    }

    function _requireIsBeneficiary() internal view {
        require(beneficiaryRewards[msg.sender] > 0, "TeamLock: not beneficiary");
    }

}