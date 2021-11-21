// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../../Dependencies/BaseMath.sol";
import "../../Dependencies/SafeMath.sol";
import "../../Interfaces/ITokenStaking.sol";
import "../../Interfaces/IToken.sol";
import "../../Interfaces/IVEToken.sol";
import "../../Dependencies/IERC20.sol";
import "../../utils/SafeToken.sol";
import "../../Dependencies/upgradeable/OwnableUpgradeable.sol";


contract TokenStakingV2 is ITokenStaking, BaseMath, OwnableUpgradeable {
    using SafeMath for uint;

    // --- Data ---
    string constant public NAME = "TokenStaking";
    address constant public GAS_TOKEN_ADDR = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    uint public totalTokenStaked;
    address public stakeToken;

    address[] public feeTokens;
    mapping (address => bool) public isFeeToken;
    mapping (address => address) public feeTokenMap;

    mapping (address => bool) public isTM;  // is valid trove manager
    mapping (address => bool) public isBO;  // is valid borrower operation
    mapping (address => bool) public isAP;  // is valid active pool

    mapping (address => uint) public stakes;
    mapping (address => uint256) public feePerTokenStaked;
    mapping (address => mapping(address => uint256)) public snapshots;

    // --- ReentrancyGuard Data---
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    // --- Lock Data ---
    uint public constant BONUS_PERCENT_DIVISOR = 100;
    IVEToken public VEToken;
    uint public bonusMultiplier;
    uint public unlockPeriod;
    uint public totalTokenLocked;
    uint public totalTokenUnlocked;
    
    mapping (address => uint) public lockedAmounts;
    mapping (address => uint) public unlockedAmounts;
    mapping (address => uint) public unlockTime;

    // --- ReentrancyGuard Functions ---
    function initializeReentrancyGuard() external onlyOwner {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    // --- Lock Functions ---
    function setVEToken(address _addr) external onlyOwner {
        VEToken = IVEToken(_addr);
        emit VETokenChanged(_addr);
    }

    function setBonusMultiplier(uint _bonusMultiplier) external onlyOwner {
        bonusMultiplier = _bonusMultiplier;
        emit BonusMultiplierChanged(_bonusMultiplier);
    }

    function setUnlockPeriod(uint _unlockPeriod) external onlyOwner {
        unlockPeriod = _unlockPeriod;
        emit UnlockPeriodChanged(_unlockPeriod);
    }
    
    function lock(uint _amount) nonReentrant external {
        _requireNonZeroAmount(_amount);

        if (_userShare(msg.sender) != 0) {
            _sendRewards();
        }
        _updateUserSnapshots(msg.sender);

        uint newLocked = lockedAmounts[msg.sender].add(_amount);
        lockedAmounts[msg.sender] = newLocked;
        emit LockChanged(msg.sender, newLocked);
        
        totalTokenLocked = totalTokenLocked.add(_amount);
        emit totalTokenLockedUpdated(totalTokenLocked);

        IToken(stakeToken).sendToTokenStaking(msg.sender, _amount);
        VEToken.mint(msg.sender, _amount);
    }

    function unlock(uint _amount) nonReentrant external {
        uint currentLocked = lockedAmounts[msg.sender];
        _requireUserHasLocked(currentLocked);

        _sendRewards();
        _updateUserSnapshots(msg.sender);

        if (_amount > 0) {
            uint unlockAmount = _amount < currentLocked ? _amount : currentLocked;
            uint newLocked = currentLocked.sub(unlockAmount);
            uint newUnlocked = unlockedAmounts[msg.sender].add(unlockAmount);
            uint newUnlockTime = block.timestamp.add(unlockPeriod);

            VEToken.burn(msg.sender, unlockAmount);
            
            lockedAmounts[msg.sender] = newLocked;
            emit LockChanged(msg.sender, newLocked);
            totalTokenLocked = totalTokenLocked.sub(unlockAmount);
            emit totalTokenLockedUpdated(totalTokenLocked);

            unlockedAmounts[msg.sender] = newUnlocked;
            emit UnlockChanged(msg.sender, newUnlocked);
            totalTokenUnlocked = totalTokenUnlocked.add(unlockAmount);
            emit totalTokenUnlockedUpdated(totalTokenUnlocked);

            unlockTime[msg.sender] = newUnlockTime;
            emit UnlockTimeChanged(msg.sender, newUnlockTime); 
        }
    }

    function withdraw() nonReentrant external {
        uint currentUnlocked = unlockedAmounts[msg.sender];
        _requireUserHasUnlocked(currentUnlocked);
        _requireLockupPeriodHasExpired();

        _sendRewards();
        _updateUserSnapshots(msg.sender);

        unlockedAmounts[msg.sender] = 0;
        emit UnlockChanged(msg.sender, 0);
        totalTokenUnlocked = totalTokenUnlocked.sub(currentUnlocked);
        emit totalTokenUnlockedUpdated(totalTokenUnlocked);

        SafeToken.safeTransfer(stakeToken, msg.sender, currentUnlocked);
    }

    function unlockedToLock(uint _amount) nonReentrant external {
        _requireNonZeroAmount(_amount);
        
        uint currentUnlocked = unlockedAmounts[msg.sender];
        _requireUserHasUnlocked(currentUnlocked);

        _sendRewards();
        _updateUserSnapshots(msg.sender);

        uint changeAmount = _amount < currentUnlocked ? _amount : currentUnlocked;
        uint newLocked = lockedAmounts[msg.sender].add(changeAmount);
        uint newUnlocked = currentUnlocked.sub(changeAmount);

        lockedAmounts[msg.sender] = newLocked;
        emit LockChanged(msg.sender, newLocked);
        totalTokenLocked = totalTokenLocked.add(changeAmount);
        emit totalTokenLockedUpdated(totalTokenLocked);

        unlockedAmounts[msg.sender] = newUnlocked;
        emit UnlockChanged(msg.sender, newUnlocked);
        totalTokenUnlocked = totalTokenUnlocked.sub(changeAmount);
        emit totalTokenUnlockedUpdated(totalTokenUnlocked);

        VEToken.mint(msg.sender, changeAmount);
    }

    function stakedToLock(uint _amount) nonReentrant external {
        _requireNonZeroAmount(_amount);
        
        uint currentStake = stakes[msg.sender];
        _requireUserHasStake(currentStake);

        _sendRewards();
        _updateUserSnapshots(msg.sender);

        uint changeAmount = _amount < currentStake ? _amount : currentStake;
        uint newLocked = lockedAmounts[msg.sender].add(changeAmount);
        uint newStake = currentStake.sub(changeAmount);

        lockedAmounts[msg.sender] = newLocked;
        emit LockChanged(msg.sender, newLocked);
        totalTokenLocked = totalTokenLocked.add(changeAmount);
        emit totalTokenLockedUpdated(totalTokenLocked);

        stakes[msg.sender] = newStake;
        emit StakeChanged(msg.sender, newStake);
        totalTokenStaked = totalTokenStaked.sub(changeAmount);
        emit totalTokenStakedUpdated(totalTokenStaked);

        VEToken.mint(msg.sender, changeAmount);
    }

    function claimRewards() nonReentrant external {
        if (_userShare(msg.sender) != 0) {
            _sendRewards();
            _updateUserSnapshots(msg.sender);
        }
    }

    function _userShare(address _user) internal view returns (uint) {
        
        uint share = lockedAmounts[_user].mul(bonusMultiplier).div(BONUS_PERCENT_DIVISOR)
            .add(unlockedAmounts[_user])
            .add(stakes[_user]);

        return share;
    } 
    
    // --- Functions ---

    function setAddresses(address _stakeToken) external initializer override {
        __Ownable_init();
        
        stakeToken = _stakeToken;
        
        feeTokenMap[_stakeToken] = _stakeToken;
        feeTokens.push(_stakeToken);
        isFeeToken[_stakeToken] = true;

        emit StakeTokenAddress(_stakeToken);
    }


    function addNewAsset(
        address _borrowingFeeToken,
        address _redeemingFeeToken,
        address _troveManager,
        address _borrowerOperation,
        address _activePool
    ) 
        external
        onlyOwner
        override 
    {
        require(!isFeeToken[_borrowingFeeToken], "fee token has been added!");
        require(!isFeeToken[_redeemingFeeToken], "fee token has been added!");
                
        isTM[_troveManager] = true;
        isBO[_borrowerOperation] = true;
        
        if (_redeemingFeeToken == GAS_TOKEN_ADDR) {
            isAP[_activePool] = true;
        }
        
        feeTokenMap[_troveManager] = _redeemingFeeToken;
        feeTokens.push(_redeemingFeeToken);
        isFeeToken[_redeemingFeeToken] = true;

        feeTokenMap[_borrowerOperation] = _borrowingFeeToken;
        feeTokens.push(_borrowingFeeToken);
        isFeeToken[_borrowingFeeToken] = true;

        emit NewAssetTokenAddress(
            _troveManager, _borrowerOperation, _activePool, _redeemingFeeToken, _borrowingFeeToken
        );
    }
    
    function stake(uint _amount) nonReentrant external override {
        _requireNonZeroAmount(_amount);

        if (_userShare(msg.sender) != 0) {
            _sendRewards();
        }
        _updateUserSnapshots(msg.sender);

        uint newStake = stakes[msg.sender].add(_amount);
        stakes[msg.sender] = newStake;
        totalTokenStaked = totalTokenStaked.add(_amount);
        emit totalTokenStakedUpdated(totalTokenStaked);

        IToken(stakeToken).sendToTokenStaking(msg.sender, _amount);
        emit StakeChanged(msg.sender, newStake);
    }

    // If requested amount > stake, send their entire stake.
    function unstake(uint _amount) nonReentrant external override {
        uint currentStake = stakes[msg.sender];
        _requireUserHasStake(currentStake);

        _sendRewards();
        _updateUserSnapshots(msg.sender);

        if (_amount > 0) {
            uint withdrawable = _amount < currentStake ? _amount : currentStake;
            uint newStake = currentStake.sub(withdrawable);

            // Decrease user's stake and total LQTY staked
            stakes[msg.sender] = newStake;
            totalTokenStaked = totalTokenStaked.sub(withdrawable);
            emit totalTokenStakedUpdated(totalTokenStaked);

            // Transfer unstaked LQTY to user
            SafeToken.safeTransfer(stakeToken, msg.sender, withdrawable);

            emit StakeChanged(msg.sender, newStake);
        }
    }

    function _sendRewards() internal {
        uint feeTokenCounts = feeTokens.length;
        for (uint i = 0 ; i < feeTokenCounts; i++) {
            address feeToken = feeTokens[i];
            uint tokenGain = _getPendingGain(feeToken, msg.sender);
            _transferOut(feeToken, msg.sender, tokenGain);
            emit StakingGainsWithdrawn(msg.sender, feeToken, tokenGain);
        }
    }

    function increaseBorrowingFee(uint _fee) external override {
        _requireCallerIsValidBorrowerOperations();
        _increaseFee(_fee);
    }

    function increaseRedeemingFee(uint _fee) external override {
        _requireCallerIsValidTroveManager();
        _increaseFee(_fee);
    }

    function increaseTransferFee(uint _fee) external override {
        _requireCallerIsStakeToken();
        _increaseFee(_fee);
    }

    function _increaseFee(uint256 _fee) internal {
        
        uint _feePerTokenStaked;
        address feeToken = feeTokenMap[msg.sender];

        if (totalTokenStaked > 0) {
            uint decimalFilling = _fillingDecimals(feeToken);
            uint totalShare = totalTokenLocked.mul(bonusMultiplier).div(BONUS_PERCENT_DIVISOR)
                .add(totalTokenStaked)
                .add(totalTokenUnlocked);
            _feePerTokenStaked = _fee.mul(decimalFilling).mul(DECIMAL_PRECISION).div(totalShare);
        }

        uint newFeePerTokenStaked = feePerTokenStaked[feeToken].add(_feePerTokenStaked);
        feePerTokenStaked[feeToken] = newFeePerTokenStaked;

        emit TokenFeeUpdated(feeToken, _fee, newFeePerTokenStaked);
    }

    function getPendingGain(address _token, address _user) external view override returns (uint) {
        return _getPendingGain(_token, _user);
    }

    function _getPendingGain(address _token, address _user) internal view returns (uint) {
        uint feePerTokenStakedSnapshot = snapshots[_user][_token];
        uint decimalFilling = _fillingDecimals(_token);
        uint tokenGain = _userShare(_user).mul(feePerTokenStaked[_token].sub(feePerTokenStakedSnapshot)).div(DECIMAL_PRECISION).div(decimalFilling);
        
        return tokenGain;
    }

    // --- Internal helper functions ---

    function _updateUserSnapshots(address _user) internal {
        uint feeTokenCounts = feeTokens.length;
        for (uint i = 0 ; i < feeTokenCounts; i++) {
            address feeToken = feeTokens[i];
            uint256 newFeePerTokenStaked = feePerTokenStaked[feeToken];
            snapshots[_user][feeToken] = newFeePerTokenStaked;
            emit StakerSnapshotsUpdated(_user, feeToken, newFeePerTokenStaked);
        }
    }

    function _transferOut(address _token, address _user, uint _amount) internal {
        if (_amount > 0) {
            if (_token == GAS_TOKEN_ADDR) {
                SafeToken.safeTransferETH(_user, _amount);
            } else {
                SafeToken.safeTransfer(_token, _user, _amount);
            }
        }
    }

    function _fillingDecimals(address token) internal view returns (uint256) {
        uint256 decimals;
        if (token == GAS_TOKEN_ADDR) {
            decimals = 18;
        } else {
            decimals = IERC20(token).decimals();
        }

        uint decimalFilling = 1;
        if (decimals < 18) {
            decimalFilling = 10 ** (18 - decimals);
        }


        return decimalFilling;
    }

    // --- 'require' functions ---

    function _requireCallerIsValidBorrowerOperations() internal view {
        require(isBO[msg.sender], "caller is not valid borrowerOperation");
    }

    function _requireCallerIsValidTroveManager() internal view {
        require(isTM[msg.sender], "caller is not valid troveManager");
    }

    function _requireCallerIsValidActivePool() internal view {
        require(isAP[msg.sender], "caller is not valid ActivePool");
    }

    function _requireCallerIsStakeToken() internal view {
        require(msg.sender == stakeToken, "caller is not stake token");
    }

    function _requireNonZeroAmount(uint _amount) internal pure {
        require(_amount > 0, 'amount must be non-zero');
    }

    function _requireUserHasStake(uint currentStake) internal pure {
        require(currentStake > 0, 'user must have a non-zero stake');
    }

    function _requireUserHasLocked(uint currentLocked) internal pure {
        require(currentLocked > 0, 'user must have a non-zero locked');
    }

    function _requireUserHasUnlocked(uint currentUnlocked) internal pure {
        require(currentUnlocked > 0, 'user must have a non-zero unlocked');
    }

    function _requireLockupPeriodHasExpired() internal view {
        require(block.timestamp > unlockTime[msg.sender], 'The lockup period has expired');
    }

    receive() external payable {
        _requireCallerIsValidActivePool();
    }
}
