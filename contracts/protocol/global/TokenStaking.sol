// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../../Dependencies/BaseMath.sol";
import "../../Dependencies/SafeMath.sol";
import "../../Interfaces/ITokenStaking.sol";
import "../../Interfaces/IToken.sol";
import "../../Dependencies/IERC20.sol";
import "../../utils/SafeToken.sol";
import "../../Dependencies/upgradeable/OwnableUpgradeable.sol";



contract TokenStaking is ITokenStaking, BaseMath, OwnableUpgradeable {
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
    
    function stake(uint _amount) external override {
        _requireNonZeroAmount(_amount);

        uint currentStake = stakes[msg.sender];

        if (currentStake != 0) {
            _sendRewards();
        }

        _updateUserSnapshots(msg.sender);

        uint newStake = currentStake.add(_amount);
        stakes[msg.sender] = newStake;
        totalTokenStaked = totalTokenStaked.add(_amount);
        emit totalTokenStakedUpdated(totalTokenStaked);

        IToken(stakeToken).sendToTokenStaking(msg.sender, _amount);
        emit StakeChanged(msg.sender, newStake);
    }

    // If requested amount > stake, send their entire stake.
    function unstake(uint _amount) external override {
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
            _feePerTokenStaked = _fee.mul(decimalFilling).mul(DECIMAL_PRECISION).div(totalTokenStaked);
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
        uint tokenGain = stakes[_user].mul(feePerTokenStaked[_token].sub(feePerTokenStakedSnapshot)).div(DECIMAL_PRECISION).div(decimalFilling);
        
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

    receive() external payable {
        _requireCallerIsValidActivePool();
    }
}
