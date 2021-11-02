// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../../../Interfaces/IToken.sol";
import "../../../Dependencies/SafeMath.sol";
import "../../../Dependencies/upgradeable/OwnableUpgradeable.sol";


contract Airdrop is OwnableUpgradeable {
    using SafeMath for uint;
    
    IToken public token;
    uint public unlockTime;
    uint public releaseTime;
    uint public totalRewards;

    address[] internal beneficiaries;

    mapping (address => uint) public beneficiaryRewards;
    mapping (address => uint) public beneficiaryWithdrawed;

    event Initialize(address token, uint totalRewards, uint _releaseTime);
    event StartRelease(uint unlockTime, uint rewardsPerBeneficiary);
    event Withdraw(address indexed beneficiary, uint amount);


    function initialize (
        address _tokenAddress,
        uint _totalRewards,
        uint _releaseTime
    ) external initializer {

        __Ownable_init();

        token = IToken(_tokenAddress);
        unlockTime = uint(-1);
        totalRewards = _totalRewards;
        releaseTime = _releaseTime;

        emit Initialize(_tokenAddress, _totalRewards, _releaseTime);
    }
    
    
    function setBeneficiary(
        address[] memory _beneficiaries
    ) external onlyOwner {
        require(initialized, "not initialized");
        require(unlockTime == uint(-1), "release started");
        
        for (uint i = 0; i < _beneficiaries.length; i++) {
            address beneficiary = _beneficiaries[i];
            beneficiaries.push(beneficiary);
        }
    }

    function startRelease() external onlyOwner {
        require(initialized, "not initialized");
        require(unlockTime == uint(-1), "release started");
        
        unlockTime = block.timestamp;
        
        uint beneficiariesCounts = beneficiaries.length;
        require(beneficiariesCounts > 0, "not set beneficiaries");

        uint rewardsPerBeneficiary = totalRewards.div(beneficiariesCounts);
        require(token.balanceOf(address(this)) >= rewardsPerBeneficiary.mul(beneficiariesCounts), "Insufficient rewards");

        for (uint i = 0; i < beneficiariesCounts; i++) {
            address beneficiary = beneficiaries[i];
            beneficiaryRewards[beneficiary] = rewardsPerBeneficiary;
        }  

        renounceOwnership();

        emit StartRelease(unlockTime, rewardsPerBeneficiary);
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
        require(block.timestamp >= unlockTime, "TeamLock: The lockup duration must have passed");
    }

    function _requireIsBeneficiary() internal view {
        require(beneficiaryRewards[msg.sender] > 0, "TeamLock: not beneficiary");
    }
}