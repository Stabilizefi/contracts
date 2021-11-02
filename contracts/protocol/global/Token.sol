// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../../Dependencies/SafeMath.sol";
import "../../Dependencies/Ownable.sol";
import "../../Interfaces/IToken.sol";
import "../../Interfaces/ITokenStaking.sol";
import "../../Interfaces/IUniswapV2Router.sol";
import "../../Interfaces/IUniswapFactory.sol";

/*
* Based upon OpenZeppelin's ERC20 contract:
* https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol
*  
* and their EIP2612 (ERC20Permit / ERC712) functionality:
* https://github.com/OpenZeppelin/openzeppelin-contracts/blob/53516bc555a454862470e7860a9b5254db4d00f5/contracts/token/ERC20/ERC20Permit.sol 
*
*/

contract Token is IToken, Ownable {
    using SafeMath for uint256;

    // --- ERC20 Data ---

    string internal _NAME;
    string internal _SYMBOL;
    string internal _VERSION;
    uint8  internal _DECIMALS;

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    uint private _totalSupply;

    // --- EIP 2612 Data ---

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 private constant _PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _TYPE_HASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    // Cache the domain separator as an immutable value, but also store the chain id that it corresponds to, in order to
    // invalidate the cached domain separator if the chain id changes.
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;

    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;
    
    mapping (address => uint256) private _nonces;

    // --- Token Data ---
    uint constant _10_MILLION = 1e25;

    uint internal immutable deploymentStartTime;
    address public immutable tokenStakingAddress;

    uint256 public transferFeeRatio;

    mapping(address => bool) public isExcludedFromFeeForSending;
    mapping(address => bool) public isExcludedFromFeeForReceiving;

    // --- Events ---
    event TransferFeeChange(uint256 origin, uint256 current);
    
    // --- Functions ---

    constructor(
        string memory _name,
        string memory _symbol,
        address _tokenStakingAddress,
        address _communityMultisigAddress,
        address _marketingMultisigAddress,
        address _teamLockAddress,
        address _airdropAddress,
        uint256 _transferFeeRatio
    ) public {
        
        _NAME = _name;
        _SYMBOL = _symbol;
        _VERSION = '1';
        _DECIMALS = 18;
        
        _requireValidTransferFeeRatio(_transferFeeRatio);
        transferFeeRatio = _transferFeeRatio;
        
        deploymentStartTime = block.timestamp;
        tokenStakingAddress = _tokenStakingAddress;
        
        // --- Set EIP 2612 Info ---

        bytes32 hashedName = keccak256(bytes(_NAME));
        bytes32 hashedVersion = keccak256(bytes(_VERSION));

        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_CHAIN_ID = _chainID();
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(_TYPE_HASH, hashedName, hashedVersion);

        // --- Initial Token allocations ---

        uint communityEntitlement = _10_MILLION.mul(77);
        _mint(_communityMultisigAddress, communityEntitlement);

        uint teamEntitlement = _10_MILLION.mul(10);
        _mint(_teamLockAddress, teamEntitlement);

        uint airdropEntitlement = _10_MILLION.mul(5).div(100);
        _mint(_airdropAddress, airdropEntitlement);

        uint marketingEntitlement = _10_MILLION.mul(100)
            .sub(communityEntitlement)
            .sub(teamEntitlement)
            .sub(airdropEntitlement);
        _mint(_marketingMultisigAddress, marketingEntitlement);

        // --- Exclude address form fee ---
        isExcludedFromFeeForSending[_communityMultisigAddress] = true;
        isExcludedFromFeeForSending[_marketingMultisigAddress] = true;
        isExcludedFromFeeForSending[_teamLockAddress] = true;

        isExcludedFromFeeForReceiving[_tokenStakingAddress] = true;
    }

    // --- External functions ---

    function setExcludedFromFeeForSending(
        address _addr,
        bool _enable
    ) external onlyOwner {
        isExcludedFromFeeForSending[_addr] = _enable;
    }

    function setExcludedFromFeeForReceiving(
        address _addr,
        bool _enable
    ) external onlyOwner {
        isExcludedFromFeeForReceiving[_addr] = _enable;
    }

    function setTransferFeeRatio(uint256 _transferFeeRatio) external onlyOwner {
        _requireValidTransferFeeRatio(_transferFeeRatio);
        uint256 OriginTransferFeeRatio = transferFeeRatio;
        transferFeeRatio = _transferFeeRatio;
        
        emit TransferFeeChange(OriginTransferFeeRatio, transferFeeRatio);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function getDeploymentStartTime() external view override returns (uint256) {
        return deploymentStartTime;
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {        
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external override returns (bool) {        
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external override returns (bool) {        
        _approve(msg.sender, spender, _allowances[msg.sender][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function sendToTokenStaking(address _sender, uint256 _amount) external override {
        _requireCallerIsTokenStaking();
        _transfer(_sender, tokenStakingAddress, _amount);
    }

    // --- EIP 2612 functionality ---

    function domainSeparator() public view override returns (bytes32) {    
        if (_chainID() == _CACHED_CHAIN_ID) {
            return _CACHED_DOMAIN_SEPARATOR;
        } else {
            return _buildDomainSeparator(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION);
        }
    }

    function permit
    (
        address owner, 
        address spender, 
        uint amount, 
        uint deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) 
        external 
        override 
    {            
        require(deadline >= now, 'Token: expired deadline');
        bytes32 digest = keccak256(abi.encodePacked('\x19\x01', 
                         domainSeparator(), keccak256(abi.encode(
                         _PERMIT_TYPEHASH, owner, spender, amount, 
                         _nonces[owner]++, deadline))));
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress == owner, 'Token: invalid signature');
        _approve(owner, spender, amount);
    }

    function nonces(address owner) external view override returns (uint256) { // FOR EIP 2612
        return _nonces[owner];
    }

    // --- Internal operations ---

    function _chainID() private pure returns (uint256 chainID) {
        assembly {
            chainID := chainid()
        }
    }

    function _buildDomainSeparator(bytes32 typeHash, bytes32 name, bytes32 version) private view returns (bytes32) {
        return keccak256(abi.encode(typeHash, name, version, _chainID(), address(this)));
    }

    function isTxExcludedFromFee(address sender, address recipient) internal view returns (bool) {
        if (
            isExcludedFromFeeForSending[sender] || 
            isExcludedFromFeeForReceiving[recipient]
        ) {
            return true;
        } else {
            return false;
        }
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        if (isTxExcludedFromFee(sender, recipient)) {
            _transferStandard(sender, recipient, amount);
        } else {
            _transferWithFee(sender, recipient, amount);
        }
    }

    function _transferWithFee(address sender, address recipient, uint256 amount) internal {
            
            uint256 burnAmount = amount.mul(transferFeeRatio).div(200);
            uint256 toStakingPoolAmount = amount.mul(transferFeeRatio).div(200);
            uint256 transferAmount = amount.sub(burnAmount).sub(toStakingPoolAmount);
            
            _burn(sender, burnAmount);
            _transferFeeToTokenStaking(sender, toStakingPoolAmount);
            _transferStandard(sender, recipient, transferAmount);
    }

    function _transferStandard(address sender, address recipient, uint256 amount) internal {
        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _transferFeeToTokenStaking(address sender, uint256 amount) internal {
        _transferStandard(sender, tokenStakingAddress, amount);
        ITokenStaking(tokenStakingAddress).increaseTransferFee(amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _balances[account] = _balances[account].sub(amount);
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
        
    function _requireCallerIsTokenStaking() internal view {
         require(msg.sender == tokenStakingAddress, "Token: caller must be the tokenStaking contract");
    }

    function _requireValidTransferFeeRatio(uint256 _ratio) internal pure {
        require(_ratio < 100, "Token: invalid transfer fee ratio");
    }

    // --- Optional functions ---

    function name() external view override returns (string memory) {
        return _NAME;
    }

    function symbol() external view override returns (string memory) {
        return _SYMBOL;
    }

    function decimals() external view override returns (uint8) {
        return _DECIMALS;
    }

    function version() external view override returns (string memory) {
        return _VERSION;
    }

    function permitTypeHash() external view override returns (bytes32) {
        return _PERMIT_TYPEHASH;
    }
}
